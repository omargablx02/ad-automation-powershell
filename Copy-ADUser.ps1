<#
.SYNOPSIS
    Clone an existing Active Directory user into a new account.

.DESCRIPTION
    Creates a new user with the same OU placement, organisational attributes,
    home folder settings, logon hours and group memberships as a template
    account - without ever copying the password, the SID or a privileged group.

    The account is named after the person, not after the SAM: Eslam Ali becomes
    CN=Eslam_Ali with SamAccountName ea. The home folder follows the SAM, so it
    lands in Home\ea, while the profile folder follows the full name, so it
    lands in Profiles\Eslam_Ali. Either name can be overridden with
    HomeFolderName or ProfileFolderName.

    What is copied:
      OU placement, Title, Department, Company, Manager, Office, StreetAddress,
      City, State, PostalCode, Country, OfficePhone, Description, logon hours,
      Logon Workstations, PasswordNeverExpires, CannotChangePassword and every
      non-privileged group membership.

    What is never copied:
      The password. The new user gets a fresh one and must change it at first
      logon. The SID is always new. AccountExpirationDate is only copied when
      the template actually has one. Privileged groups - Domain Admins,
      Enterprise Admins, Schema Admins, Administrators, Account, Backup, Server
      and Print Operators, Group Policy Creator Owners, Protected Users,
      DnsAdmins and Domain Controllers - are listed and skipped.

    Every value that is not supplied on the command line is asked for, so the
    script can be started with no parameters at all. The two folder roots offer
    a default of \\<this computer>\Home and \\<this computer>\Profiles: press
    Enter to accept it, or type a single dash to skip that folder.

    An existing account is skipped instead of throwing, and every run ends with
    a per-object result plus a summary.

.PARAMETER SourceUser
    SamAccountName of the template user to copy. Asked for if omitted.

.PARAMETER SamAccountName
    SamAccountName for the new user. Asked for if omitted.

.PARAMETER GivenName
    First name of the new user. Asked for if omitted.

.PARAMETER Surname
    Last name of the new user. Asked for if omitted.

.PARAMETER DisplayName
    Name of the new account object (CN and displayName). Defaults to
    Firstname_Lastname, so Ahmed Sayed becomes Ahmed_Sayed. This is the name
    that shows up in Active Directory Users and Computers, not the SAM.

.PARAMETER HomeFolderName
    Folder name used under HomeRoot. Defaults to the SamAccountName, so Eslam
    Ali becomes Home\ea. Override it when the share uses a different
    convention.

.PARAMETER ProfileFolderName
    Folder name used under ProfileRoot. Defaults to DisplayName, so Eslam Ali
    becomes Profiles\Eslam_Ali. Override it when the share uses a different
    convention.

.PARAMETER Password
    Initial password as a SecureString. If omitted the script prompts, so the
    password is never stored in the script or in the command line.

.PARAMETER HomeRoot
    UNC root that holds the home folders, for example \\SERVER\Home. When
    supplied the folder is created and locked down to the new user. Asked for
    if omitted, so an interactive run still creates the folder. Type - to skip
    it and configure no home directory.

.PARAMETER ProfileRoot
    UNC root that holds the roaming profile folders. Optional, same behaviour:
    asked for when omitted, and a single dash skips it.

.PARAMETER HomeDriveLetter
    Drive letter mapped to the home folder. Default H:.

.EXAMPLE
    .\Copy-ADUser.ps1 -SourceUser ahmed_hassan -SamAccountName omar_farouk -GivenName Omar -Surname Farouk -HomeRoot \\ACTIVEDIR\Home -WhatIf

.EXAMPLE
    .\Copy-ADUser.ps1 -SourceUser ahmed_hassan -SamAccountName omar_farouk -GivenName Omar -Surname Farouk -HomeRoot \\ACTIVEDIR\Home

.EXAMPLE
    .\Copy-ADUser.ps1 -SourceUser jf -SamAccountName ea -GivenName Eslam -Surname Ali -HomeFolderName ea -ProfileFolderName Eslam_Ali -HomeRoot \\ACTIVEDIR\Home -ProfileRoot \\ACTIVEDIR\Profiles

.EXAMPLE
    .\Copy-ADUser.ps1

.NOTES
    Requires RSAT-AD-PowerShell and an elevated session.
    The template account is never modified.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$SourceUser,

    [string]$SamAccountName,

    [string]$GivenName,

    [string]$Surname,

    [string]$DisplayName,

    [string]$HomeFolderName,

    [string]$ProfileFolderName,

    [SecureString]$Password,

    [string]$HomeRoot,

    [string]$ProfileRoot,

    [string]$HomeDriveLetter = 'H:'
)

Import-Module ActiveDirectory -ErrorAction Stop

# Groups that must never travel from a template to a new account.
$PrivilegedGroups = @(
    'Domain Admins'
    'Enterprise Admins'
    'Schema Admins'
    'Administrators'
    'Account Operators'
    'Backup Operators'
    'Server Operators'
    'Print Operators'
    'Group Policy Creator Owners'
    'Protected Users'
    'DnsAdmins'
    'Domain Controllers'
    'Read-only Domain Controllers'
)

function Grant-FolderAccess {
    <#
        Break inheritance, drop the inherited ACEs and grant Full Control to the
        account plus Administrators and SYSTEM only. Without this step every
        authenticated user keeps the read access inherited from the parent share.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Account
    )

    $acl = Get-Acl -Path $Path
    $acl.SetAccessRuleProtection($true, $false)

    $inheritance = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $propagation = [System.Security.AccessControl.PropagationFlags]::None
    $allow       = [System.Security.AccessControl.AccessControlType]::Allow

    foreach ($identity in @($Account, 'BUILTIN\Administrators', 'NT AUTHORITY\SYSTEM')) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $identity, 'FullControl', $inheritance, $propagation, $allow)
        $acl.AddAccessRule($rule)
    }

    Set-Acl -Path $Path -AclObject $acl -ErrorAction Stop
}

function Add-FolderAccess {
    <#
        Add a single Full Control entry for the account without touching any
        other entry. Used when the folder already exists and only the new
        account is missing from its ACL.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Account,
        [string]$Sid
    )

    $acl = Get-Acl -LiteralPath $Path

    $inheritance = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $propagation = [System.Security.AccessControl.PropagationFlags]::None
    $allow       = [System.Security.AccessControl.AccessControlType]::Allow

    # Prefer the account SID when we have it: the file server may not be able to
    # resolve "DOMAIN\sam" yet, but the SID is already known from the new account.
    if ($Sid) {
        $identity = [System.Security.Principal.SecurityIdentifier]::new($Sid)
        $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $identity, 'FullControl', $inheritance, $propagation, $allow)
    }
    else {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $Account, 'FullControl', $inheritance, $propagation, $allow)
    }
    $acl.AddAccessRule($rule)

    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}

function Test-FolderAccess {
    <#
        Report whether an Allow rule for that SID already exists on the folder.
        The comparison is done on SIDs, so an entry left behind by a deleted
        account does not count as access for the account that replaced it.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Sid
    )

    $acl = Get-Acl -LiteralPath $Path

    foreach ($rule in $acl.Access) {
        if ($rule.AccessControlType -ne 'Allow') {
            continue
        }

        try {
            $ruleSid = $rule.IdentityReference.Translate(
                [System.Security.Principal.SecurityIdentifier]).Value
        }
        catch {
            continue
        }

        if ($ruleSid -eq $Sid) {
            return $true
        }
    }

    return $false
}

function Read-HostDefault {
    <#
        Read-Host has no -Default, so this wrapper prints one in square brackets
        and returns it when the operator just presses Enter. A single dash means
        "no value", which is how an optional folder root is skipped.
    #>
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Default
    )

    $answer = Read-Host -Prompt "$Prompt [$Default]"

    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $Default
    }

    $answer = $answer.Trim()

    if ($answer -eq '-') {
        return ''
    }

    return $answer
}

if ([string]::IsNullOrWhiteSpace($SourceUser)) {
    $SourceUser = Read-Host -Prompt 'Template (source) SamAccountName'
}

if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
    $SamAccountName = Read-Host -Prompt 'SamAccountName for the new user'
}

if ([string]::IsNullOrWhiteSpace($GivenName)) {
    $GivenName = Read-Host -Prompt 'First name'
}

if ([string]::IsNullOrWhiteSpace($Surname)) {
    $Surname = Read-Host -Prompt 'Last name'
}

if ([string]::IsNullOrWhiteSpace($SourceUser) -or [string]::IsNullOrWhiteSpace($SamAccountName) -or
    [string]::IsNullOrWhiteSpace($GivenName) -or [string]::IsNullOrWhiteSpace($Surname)) {
    Write-Warning 'Operation cancelled: template, SamAccountName, first name and last name are all required.'
    return
}

if ($SourceUser -eq $SamAccountName) {
    Write-Warning 'Operation cancelled: the new SamAccountName cannot be the template account.'
    return
}

# Both folder roots are asked for, so a plain interactive run still builds the
# home and profile folders instead of silently skipping them.
if ([string]::IsNullOrWhiteSpace($HomeRoot)) {
    $HomeRoot = Read-HostDefault -Prompt 'Home folder root (dash to skip)' -Default "\\$env:COMPUTERNAME\Home"
}

if ([string]::IsNullOrWhiteSpace($ProfileRoot)) {
    $ProfileRoot = Read-HostDefault -Prompt 'Profile folder root (dash to skip)' -Default "\\$env:COMPUTERNAME\Profiles"
}

foreach ($root in @($HomeRoot, $ProfileRoot)) {
    if (-not [string]::IsNullOrWhiteSpace($root) -and -not (Test-Path -LiteralPath $root)) {
        Write-Host "[WARN] '$root' is not reachable from here; the folder step will report the reason." -ForegroundColor Yellow
    }
}

$Domain        = Get-ADDomain
$DomainFQDN    = $Domain.DNSRoot
$DomainNetBIOS = $Domain.NetBIOSName
$UserUPN       = "$SamAccountName@$DomainFQDN"

# The account name follows the person, not the SAM: Eslam Ali -> Eslam_Ali.
if ([string]::IsNullOrWhiteSpace($DisplayName)) {
    $DisplayName = "$($GivenName)_$($Surname)".Trim()
}

# The home folder follows the SAM, the profile folder follows the full name.
if ([string]::IsNullOrWhiteSpace($HomeFolderName)) {
    $HomeFolderName = $SamAccountName
}

if ([string]::IsNullOrWhiteSpace($ProfileFolderName)) {
    $ProfileFolderName = $DisplayName
}

foreach ($folderName in @($HomeFolderName, $ProfileFolderName)) {
    if ($folderName -match '[\\/:*?"<>|]') {
        Write-Host "[FAIL] The folder name '$folderName' contains a character Windows does not allow." -ForegroundColor Red
        return
    }
}

Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ' AD user clone                               ' -ForegroundColor Cyan
Write-Host '=============================================' -ForegroundColor Cyan

# --- 1. Template ------------------------------------------------------------
$templateProperties = @(
    'MemberOf'
    'Title'
    'Department'
    'Company'
    'Manager'
    'Office'
    'StreetAddress'
    'City'
    'State'
    'PostalCode'
    'Country'
    'OfficePhone'
    'Description'
    'logonHours'
    'userWorkstations'
    'AccountExpirationDate'
    'PasswordNeverExpires'
    'CannotChangePassword'
    'Enabled'
)

try {
    $Source = Get-ADUser -Identity $SourceUser -Properties $templateProperties -ErrorAction Stop
}
catch {
    Write-Host "[FAIL] Template user '$SourceUser' was not found." -ForegroundColor Red
    return
}

# --- 2. Refuse to touch an existing account ---------------------------------
$existing = Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'" -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "[SKIP] '$SamAccountName' already exists: $($existing.DistinguishedName)" -ForegroundColor Yellow
    Write-Host '[SKIP] Nothing was created and nothing was changed.' -ForegroundColor Yellow
    return
}

$upnTaken = Get-ADUser -Filter "UserPrincipalName -eq '$UserUPN'" -ErrorAction SilentlyContinue
if ($upnTaken) {
    Write-Host "[FAIL] The UPN '$UserUPN' is already in use by '$($upnTaken.SamAccountName)'." -ForegroundColor Red
    return
}

# --- 3. Password ------------------------------------------------------------
if (-not $Password -or $Password.Length -eq 0) {
    $Password = Read-Host -Prompt "Initial password for $SamAccountName" -AsSecureString
}

if (-not $Password -or $Password.Length -eq 0) {
    Write-Host '[FAIL] A password is required to create the account.' -ForegroundColor Red
    return
}

# --- 4. Build the plan before changing anything -----------------------------
$ParentPath = ($Source.DistinguishedName -split '(?<!\\),', 2)[1]

$params = @{
    Name              = $DisplayName
    DisplayName       = $DisplayName
    SamAccountName    = $SamAccountName
    UserPrincipalName = $UserUPN
    GivenName         = $GivenName
    Surname           = $Surname
    Path              = $ParentPath
    AccountPassword   = $Password
    Enabled           = $true
}

if ([bool]$Source.CannotChangePassword) {
    $params.CannotChangePassword = $true
}
else {
    $params.ChangePasswordAtLogon = $true
}

if ([bool]$Source.PasswordNeverExpires) {
    $params.PasswordNeverExpires = $true
}

$copyableAttributes = [ordered]@{
    Title         = $Source.Title
    Department    = $Source.Department
    Company       = $Source.Company
    Manager       = $Source.Manager
    Office        = $Source.Office
    StreetAddress = $Source.StreetAddress
    City          = $Source.City
    State         = $Source.State
    PostalCode    = $Source.PostalCode
    Country       = $Source.Country
    OfficePhone   = $Source.OfficePhone
    Description   = $Source.Description
}

foreach ($key in $copyableAttributes.Keys) {
    $value = $copyableAttributes[$key]
    if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
        $params[$key] = $value
    }
}

if ($null -ne $Source.AccountExpirationDate) {
    $params.AccountExpirationDate = $Source.AccountExpirationDate
}

if (-not [string]::IsNullOrWhiteSpace($HomeRoot)) {
    $params.HomeDirectory = Join-Path -Path $HomeRoot -ChildPath $HomeFolderName
    $params.HomeDrive     = $HomeDriveLetter
}

if (-not [string]::IsNullOrWhiteSpace($ProfileRoot)) {
    $params.ProfilePath = Join-Path -Path $ProfileRoot -ChildPath $ProfileFolderName
}

# --- 5. Split the group memberships into copy / skip -------------------------
$privilegedSids = @{}
foreach ($groupName in $PrivilegedGroups) {
    $groupObject = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue |
                   Select-Object -First 1
    if ($groupObject) {
        $privilegedSids[$groupObject.SID.Value] = $groupObject.Name
    }
}

$groupsToCopy = @()
$groupsSkipped = @()

foreach ($groupDN in @($Source.MemberOf)) {
    $group = Get-ADGroup -Identity $groupDN -ErrorAction SilentlyContinue
    if (-not $group) {
        continue
    }

    if ($privilegedSids.ContainsKey($group.SID.Value)) {
        $groupsSkipped += $group.Name
        continue
    }

    $groupsToCopy += $group
}

# --- 6. Show the plan -------------------------------------------------------
Write-Host "[INFO] Template     : $($Source.DistinguishedName)" -ForegroundColor Cyan
Write-Host "[INFO] Account name : $DisplayName" -ForegroundColor Cyan
Write-Host "[INFO] New account  : $UserUPN" -ForegroundColor Cyan
Write-Host "[INFO] Target OU    : $ParentPath" -ForegroundColor Cyan
Write-Host "[INFO] Groups to add: $($groupsToCopy.Count)" -ForegroundColor Cyan

if ($params.ContainsKey('HomeDirectory')) {
    Write-Host "[INFO] Home folder  : $($params.HomeDirectory) ($($params.HomeDrive))" -ForegroundColor Cyan
}

if ($params.ContainsKey('ProfilePath')) {
    Write-Host "[INFO] Profile path : $($params.ProfilePath)" -ForegroundColor Cyan
}

if ($groupsSkipped.Count -gt 0) {
    Write-Host "[INFO] Privileged groups skipped: $($groupsSkipped -join ', ')" -ForegroundColor Yellow
}

if (-not $Source.Enabled) {
    Write-Host '[INFO] Template is disabled; the new account is created enabled.' -ForegroundColor Yellow
}

if (-not $PSCmdlet.ShouldProcess($SamAccountName, "Create AD user from template '$SourceUser'")) {
    return
}

# --- 7. Create the account --------------------------------------------------
try {
    New-ADUser @params -ErrorAction Stop
    $NewUserSid = (Get-ADUser -Identity $SamAccountName -ErrorAction SilentlyContinue).SID.Value
    Write-Host "[ OK ] Account '$SamAccountName' created." -ForegroundColor Green
}
catch {
    $message = $_.Exception.Message
    if ($message -match 'password does not meet') {
        Write-Host '[FAIL] The password does not meet the domain policy (length, complexity or history).' -ForegroundColor Red
    }
    elseif ($message -match 'already exists') {
        Write-Host "[SKIP] '$SamAccountName' already exists. Nothing else was changed." -ForegroundColor Yellow
    }
    else {
        Write-Host "[FAIL] $message" -ForegroundColor Red
    }
    return
}

# --- 8. Logon hours and Logon Workstations ----------------------------------
if ($null -ne $Source.logonHours) {
    try {
        Set-ADUser -Identity $SamAccountName -Replace @{ logonHours = $Source.logonHours } -ErrorAction Stop
        Write-Host '[ OK ] Logon hours copied.' -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Logon hours not copied: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if (-not [string]::IsNullOrWhiteSpace($Source.userWorkstations)) {
    try {
        Set-ADUser -Identity $SamAccountName -LogonWorkstations $Source.userWorkstations -ErrorAction Stop
        Write-Host "[ OK ] Logon Workstations restriction copied: $($Source.userWorkstations)" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Logon Workstations not copied: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# --- 9. Home folder on the file server --------------------------------------
if ($params.ContainsKey('HomeDirectory')) {
    $homePath    = $params.HomeDirectory
    $homeAccount = "$DomainNetBIOS\$SamAccountName"

    if (Test-Path -LiteralPath $homePath) {
        if ($NewUserSid -and (Test-FolderAccess -Path $homePath -Sid $NewUserSid)) {
            Write-Host "[SKIP] Home folder already exists: $homePath" -ForegroundColor Yellow
        }
        else {
            Write-Host "[WARN] Home folder exists but '$homeAccount' has no permission on it: $homePath" -ForegroundColor Yellow

            if ($PSCmdlet.ShouldProcess($homePath, 'Grant the new account access to the existing home folder')) {
                try {
                    Add-FolderAccess -Path $homePath -Account $homeAccount -Sid $NewUserSid
                    Write-Host "[ OK ] Access granted on the existing home folder: $homePath" -ForegroundColor Green
                }
                catch {
                    Write-Host "[WARN] Could not grant access: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
    }
    elseif ($PSCmdlet.ShouldProcess($homePath, 'Create home folder and lock down permissions')) {
        try {
            New-Item -Path $homePath -ItemType Directory -ErrorAction Stop | Out-Null
            Grant-FolderAccess -Path $homePath -Account $homeAccount
            Write-Host "[ OK ] Home folder created: $homePath" -ForegroundColor Green
        }
        catch {
            Write-Host "[WARN] Home folder: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# --- 10. Profile folder -----------------------------------------------------
if ($params.ContainsKey('ProfilePath')) {
    $profilePath    = $params.ProfilePath
    $profileAccount = "$DomainNetBIOS\$SamAccountName"

    if (Test-Path -LiteralPath $profilePath) {
        if ($NewUserSid -and (Test-FolderAccess -Path $profilePath -Sid $NewUserSid)) {
            Write-Host "[SKIP] Profile folder already exists: $profilePath" -ForegroundColor Yellow
        }
        else {
            Write-Host "[WARN] Profile folder exists but '$profileAccount' has no permission on it: $profilePath" -ForegroundColor Yellow

            if ($PSCmdlet.ShouldProcess($profilePath, 'Grant the new account access to the existing profile folder')) {
                try {
                    Add-FolderAccess -Path $profilePath -Account $profileAccount -Sid $NewUserSid
                    Write-Host "[ OK ] Access granted on the existing profile folder: $profilePath" -ForegroundColor Green
                }
                catch {
                    Write-Host "[WARN] Could not grant access: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
    }
    elseif ($PSCmdlet.ShouldProcess($profilePath, 'Create profile folder and lock down permissions')) {
        try {
            New-Item -Path $profilePath -ItemType Directory -ErrorAction Stop | Out-Null
            Grant-FolderAccess -Path $profilePath -Account $profileAccount
            Write-Host "[ OK ] Profile folder created: $profilePath" -ForegroundColor Green
        }
        catch {
            Write-Host "[WARN] Profile folder: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# --- 11. Group memberships --------------------------------------------------
$groupsAdded = 0
$groupsFailed = 0

foreach ($group in $groupsToCopy) {
    try {
        Add-ADGroupMember -Identity $group -Members $SamAccountName -ErrorAction Stop
        Write-Host "[ OK ] Added to group: $($group.Name)" -ForegroundColor Green
        $groupsAdded++
    }
    catch {
        Write-Host "[WARN] Group '$($group.Name)': $($_.Exception.Message)" -ForegroundColor Yellow
        $groupsFailed++
    }
}

# --- 12. Summary ------------------------------------------------------------
Write-Host '---------------------------------------------' -ForegroundColor Cyan
Write-Host "[DONE] $SamAccountName created in $ParentPath" -ForegroundColor Green
Write-Host "[DONE] Groups added: $groupsAdded of $($groupsToCopy.Count)" -ForegroundColor Green

if ($groupsSkipped.Count -gt 0) {
    Write-Host "[DONE] Privileged groups not copied: $($groupsSkipped -join ', ')" -ForegroundColor Yellow
}

if ($groupsFailed -gt 0) {
    Write-Host "[WARN] Groups that failed: $groupsFailed" -ForegroundColor Yellow
}

if ($params.ContainsKey('ChangePasswordAtLogon')) {
    Write-Host '[INFO] The new account must change its password at first logon.' -ForegroundColor Cyan
}
