<#
    Pester 5 tests for the AD automation scripts.

    The scripts are executed for real: their #Requires lines are stripped, the
    ActiveDirectory module import is removed, and every AD cmdlet they call is
    answered by a small in-memory stub. Nothing here touches a real domain.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot

    function Reset-FakeAD {
        $script:AD = @{
            DomainDN  = 'DC=bash,DC=local'
            DNSRoot   = 'bash.local'
            OUs       = [System.Collections.Generic.List[object]]::new()
            Users     = @{}
            Computers = @{}
            Calls     = [System.Collections.Generic.List[object]]::new()
            Prompts   = [System.Collections.Generic.List[string]]::new()
        }
        $script:Answer = 'Y'

        Add-FakeOU -Name 'Corporate_HQ'    -ParentDN $script:AD.DomainDN
        Add-FakeOU -Name 'IT_Department'   -ParentDN 'OU=Corporate_HQ,DC=bash,DC=local'
        Add-FakeOU -Name 'Human_Resources' -ParentDN 'OU=Corporate_HQ,DC=bash,DC=local'
        Add-FakeOU -Name 'Sales_Marketing' -ParentDN 'OU=Corporate_HQ,DC=bash,DC=local'
    }

    function Add-FakeOU {
        param([string]$Name, [string]$ParentDN)
        $script:AD.OUs.Add([pscustomobject]@{
            Name              = $Name
            DistinguishedName = "OU=$Name,$ParentDN"
        })
    }

    function Add-FakeComputer {
        param([string]$Name, [string]$ParentDN, [bool]$Protected = $true)
        $script:AD.Computers[$Name] = [pscustomobject]@{
            Name                            = $Name
            DistinguishedName               = "CN=$Name,$ParentDN"
            ProtectedFromAccidentalDeletion = $Protected
        }
    }

    function Get-FakeComputerByDN {
        param([string]$DN)
        $script:AD.Computers.Values | Where-Object DistinguishedName -eq $DN | Select-Object -First 1
    }

    function Invoke-AdScript {
        <#
            Runs one of the repo scripts in a sandbox. Any parameter not supplied
            falls back to the script default; CSVs are always passed explicitly
            because scriptblocks do not get a $PSScriptRoot.
        #>
        [CmdletBinding()]
        param([string]$ScriptName, [hashtable]$Parameters = @{})

        $path = Join-Path $script:RepoRoot $ScriptName
        $text = Get-Content -LiteralPath $path -Raw
        $text = [regex]::Replace($text, '(?m)^\s*#Requires[^\r\n]*\r?\n?', '')
        $text = $text -replace 'Import-Module ActiveDirectory -ErrorAction Stop', ''

        # Keep high-impact scripts from blocking on a confirmation prompt in tests.
        $ConfirmPreference = 'None'
        $sb = [scriptblock]::Create($text)
        & $sb @Parameters 6>$null
    }

    # The real AD module ships this type; the stub world needs it for typed catches.
    if (-not ('Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException' -as [type])) {
        Add-Type -TypeDefinition @'
namespace Microsoft.ActiveDirectory.Management {
    public class ADIdentityNotFoundException : System.Exception {
        public ADIdentityNotFoundException(string message) : base(message) { }
    }
}
'@
    }

    # ---- stubbed ActiveDirectory cmdlets -------------------------------------

    function Get-ADDomain {
        [CmdletBinding()]
        param()
        [pscustomobject]@{
            DNSRoot           = $script:AD.DNSRoot
            DistinguishedName = $script:AD.DomainDN
        }
    }

    function Get-ADOrganizationalUnit {
        [CmdletBinding()]
        param([string]$Filter)
        if ($Filter -match "DistinguishedName -eq '([^']*)'") {
            $dn = $Matches[1]
            return $script:AD.OUs | Where-Object DistinguishedName -eq $dn
        }
        if ($Filter -match "Name -eq '([^']*)'") {
            $name = $Matches[1]
            $script:AD.OUs | Where-Object Name -eq $name
        }
    }

    function New-ADOrganizationalUnit {
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [string]$Name,
            [string]$Path,
            [bool]$ProtectedFromAccidentalDeletion
        )
        $script:AD.Calls.Add([pscustomobject]@{
            Cmdlet    = 'New-ADOrganizationalUnit'
            Name      = $Name
            Path      = $Path
            Protected = $ProtectedFromAccidentalDeletion
        })
        Add-FakeOU -Name $Name -ParentDN $Path
    }

    function Get-ADUser {
        [CmdletBinding()]
        param([string]$Filter, [string]$Identity)

        if ($Identity) {
            if (-not $script:AD.Users.ContainsKey($Identity)) {
                throw "Cannot find an object with identity: '$Identity'."
            }
            return $script:AD.Users[$Identity]
        }
        if ($Filter -match "SamAccountName -eq '([^']*)'") {
            $sam = $Matches[1]
            if ($script:AD.Users.ContainsKey($sam)) { return $script:AD.Users[$sam] }
        }
    }

    function New-ADUser {
        [CmdletBinding()]
        param(
            [string]$Name,
            [string]$SamAccountName,
            [string]$UserPrincipalName,
            [string]$GivenName,
            [string]$Surname,
            [string]$Path,
            [securestring]$AccountPassword,
            [bool]$Enabled,
            [bool]$ChangePasswordAtLogon
        )
        $script:AD.Calls.Add([pscustomobject]@{
            Cmdlet = 'New-ADUser'
            Sam    = $SamAccountName
            UPN    = $UserPrincipalName
            Path   = $Path
            Name   = $Name
        })
        $script:AD.Users[$SamAccountName] = [pscustomobject]@{
            SamAccountName    = $SamAccountName
            UserPrincipalName = $UserPrincipalName
            DistinguishedName = "CN=$Name,$Path"
        }
    }

    function Remove-ADUser {
        [CmdletBinding(SupportsShouldProcess)]
        param([string]$Identity)
        $script:AD.Calls.Add([pscustomobject]@{ Cmdlet = 'Remove-ADUser'; Sam = $Identity })
        $script:AD.Users.Remove($Identity)
    }

    function Get-ADComputer {
        [CmdletBinding()]
        param([string]$Filter, [string]$Identity)

        if ($Identity) {
            if (-not $script:AD.Computers.ContainsKey($Identity)) {
                throw "Cannot find an object with identity: '$Identity'."
            }
            return $script:AD.Computers[$Identity]
        }
        if ($Filter -match "Name -eq '([^']*)'") {
            $name = $Matches[1]
            if ($script:AD.Computers.ContainsKey($name)) { return $script:AD.Computers[$name] }
        }
    }

    function New-ADComputer {
        [CmdletBinding()]
        param(
            [string]$Name,
            [string]$SamAccountName,
            [string]$Path,
            [string]$Description,
            [bool]$Enabled,
            [bool]$ProtectedFromAccidentalDeletion
        )
        $script:AD.Calls.Add([pscustomobject]@{
            Cmdlet    = 'New-ADComputer'
            Name      = $Name
            Path      = $Path
            Protected = $ProtectedFromAccidentalDeletion
        })
        Add-FakeComputer -Name $Name -ParentDN $Path -Protected $ProtectedFromAccidentalDeletion
    }

    function Remove-ADComputer {
        [CmdletBinding(SupportsShouldProcess)]
        param([string]$Identity)
        $script:AD.Calls.Add([pscustomobject]@{ Cmdlet = 'Remove-ADComputer'; DN = $Identity })
        $computer = Get-FakeComputerByDN -DN $Identity
        if ($computer) { $script:AD.Computers.Remove($computer.Name) }
    }

    function Get-ADObject {
        [CmdletBinding()]
        param([string]$Identity, [string[]]$Properties)
        $computer = Get-FakeComputerByDN -DN $Identity
        if (-not $computer) { throw "Cannot find an object with identity: '$Identity'." }
        [pscustomobject]@{
            DistinguishedName               = $computer.DistinguishedName
            ProtectedFromAccidentalDeletion = $computer.ProtectedFromAccidentalDeletion
        }
    }

    function Set-ADObject {
        [CmdletBinding()]
        param([string]$Identity, [bool]$ProtectedFromAccidentalDeletion)
        $script:AD.Calls.Add([pscustomobject]@{
            Cmdlet    = 'Set-ADObject'
            DN        = $Identity
            Protected = $ProtectedFromAccidentalDeletion
        })
        $computer = Get-FakeComputerByDN -DN $Identity
        if ($computer) {
            $computer.ProtectedFromAccidentalDeletion = $ProtectedFromAccidentalDeletion
        }
    }

    function Move-ADObject {
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(ValueFromPipeline)]
            [object]$Identity,
            [string]$TargetPath
        )
        process {
            $script:AD.Calls.Add([pscustomobject]@{
                Cmdlet = 'Move-ADObject'
                DN     = $Identity.DistinguishedName
                Target = $TargetPath
            })
            $computer = Get-FakeComputerByDN -DN $Identity.DistinguishedName
            if ($computer) { $computer.DistinguishedName = "CN=$($computer.Name),$TargetPath" }
        }
    }

    function Read-Host {
        [CmdletBinding()]
        param([string]$Prompt, [switch]$AsSecureString)
        $script:AD.Prompts.Add($Prompt)
        if ($AsSecureString) {
            return (ConvertTo-SecureString 'P@ssw0rd-Only-For-Tests' -AsPlainText -Force)
        }
        return $script:Answer
    }

    function New-TestCsv {
        param([string[]]$Lines)
        $path = Join-Path $TestDrive ('csv-' + [guid]::NewGuid().ToString('N') + '.csv')
        Set-Content -LiteralPath $path -Value $Lines -Encoding ascii
        return $path
    }
}

Describe 'Auto_OU.ps1' {

    BeforeEach { Reset-FakeAD }

    It 'replaces the placeholder domain with the detected domain' {
        $csv = New-TestCsv @(
            'Name,Path',
            'Corporate_HQ,"DC=company,DC=local"',
            'IT_Department,"OU=Corporate_HQ,DC=company,DC=local"'
        )
        $script:AD.OUs.Clear()

        Invoke-AdScript 'Auto_OU.ps1' @{ CsvPath = $csv }

        $created = @($script:AD.Calls | Where-Object Cmdlet -eq 'New-ADOrganizationalUnit')
        $created.Count | Should -Be 2
        foreach ($call in $created) {
            $call.Path | Should -BeLike '*DC=bash,DC=local'
            $call.Path | Should -Not -BeLike '*DC=company*'
        }
        $created[0].Protected | Should -BeTrue
    }

    It 'creates parents before children when the CSV is shuffled' {
        $csv = New-TestCsv @(
            'Name,Path',
            'HR_Team,"OU=Human_Resources,OU=Corporate_HQ,DC=company,DC=local"',
            'Corporate_HQ,"DC=company,DC=local"',
            'IT_Department,"OU=Corporate_HQ,DC=company,DC=local"',
            'Human_Resources,"OU=Corporate_HQ,DC=company,DC=local"'
        )
        $script:AD.OUs.Clear()

        Invoke-AdScript 'Auto_OU.ps1' @{ CsvPath = $csv }

        $names = @($script:AD.Calls | Where-Object Cmdlet -eq 'New-ADOrganizationalUnit' |
                   ForEach-Object Name)
        $names.Count | Should -Be 4
        $names[0] | Should -Be 'Corporate_HQ'
        [array]::IndexOf($names, 'Corporate_HQ') | Should -BeLessThan ([array]::IndexOf($names, 'IT_Department'))
        [array]::IndexOf($names, 'Human_Resources') | Should -BeLessThan ([array]::IndexOf($names, 'HR_Team'))
    }

    It 'skips an OU that already exists' {
        $csv = New-TestCsv @(
            'Name,Path',
            'Corporate_HQ,"DC=company,DC=local"'
        )

        Invoke-AdScript 'Auto_OU.ps1' @{ CsvPath = $csv }

        @($script:AD.Calls | Where-Object Cmdlet -eq 'New-ADOrganizationalUnit').Count | Should -Be 0
    }

    It 'creates nothing with -WhatIf' {
        $csv = New-TestCsv @(
            'Name,Path',
            'Corporate_HQ,"DC=company,DC=local"'
        )

        Invoke-AdScript 'Auto_OU.ps1' @{ CsvPath = $csv; WhatIf = $true }

        @($script:AD.Calls | Where-Object Cmdlet -eq 'New-ADOrganizationalUnit').Count | Should -Be 0
    }

    It 'rejects <Case> and creates nothing' -TestCases @(
        @{ Case = 'an empty Name';          Lines = @('Name,Path', ',"DC=company,DC=local"') }
        @{ Case = 'a leftover placeholder'; Lines = @('Name,Path', 'Corporate_HQ,"DC=company, DC=local"') }
        @{ Case = 'a foreign domain';       Lines = @('Name,Path', 'Corporate_HQ,"DC=other,DC=local"') }
        @{ Case = 'an invalid Name';        Lines = @('Name,Path', '"Bad,Name","DC=company,DC=local"') }
        @{ Case = 'an empty Path';          Lines = @('Name,Path', 'Corporate_HQ,') }
    ) {
        param($Case, $Lines)
        $csv = New-TestCsv $Lines

        { Invoke-AdScript 'Auto_OU.ps1' @{ CsvPath = $csv } } | Should -Throw
        @($script:AD.Calls | Where-Object Cmdlet -eq 'New-ADOrganizationalUnit').Count | Should -Be 0
    }

    It 'rejects a CSV that is missing the Path column' {
        $csv = New-TestCsv @('Name', 'Corporate_HQ')

        { Invoke-AdScript 'Auto_OU.ps1' @{ CsvPath = $csv } } | Should -Throw '*missing the*Path*'
    }
}

Describe 'AddUser.ps1' {

    BeforeEach { Reset-FakeAD }

    It 'creates the numbered series with the right SAM, UPN and OU' {
        Invoke-AdScript 'AddUser.ps1' @{ StartAt = 140; Count = 3; OUName = 'IT_Department' }

        $script:AD.Users.ContainsKey('user140') | Should -BeTrue
        $script:AD.Users.ContainsKey('user142') | Should -BeTrue
        $script:AD.Users['user140'].UserPrincipalName | Should -Be 'user140@bash.local'
        $script:AD.Users['user140'].DistinguishedName | Should -BeLike 'CN=User 140,OU=IT_Department,OU=Corporate_HQ,DC=bash,DC=local'
        @($script:AD.Calls | Where-Object Cmdlet -eq 'New-ADUser').Count | Should -Be 3
    }

    It 'skips accounts that already exist' {
        $script:AD.Users['user140'] = [pscustomobject]@{ SamAccountName = 'user140' }

        Invoke-AdScript 'AddUser.ps1' @{ StartAt = 140; Count = 2; OUName = 'IT_Department' }

        @($script:AD.Calls | Where-Object Cmdlet -eq 'New-ADUser').Count | Should -Be 1
        $script:AD.Users.ContainsKey('user141') | Should -BeTrue
    }

    It 'does not prompt and creates nothing with -WhatIf' {
        Invoke-AdScript 'AddUser.ps1' @{ StartAt = 140; Count = 2; OUName = 'IT_Department'; WhatIf = $true }

        $script:AD.Prompts.Count | Should -Be 0
        @($script:AD.Calls | Where-Object Cmdlet -eq 'New-ADUser').Count | Should -Be 0
    }

    It 'throws when the target OU does not exist' {
        { Invoke-AdScript 'AddUser.ps1' @{ OUName = 'No_Such_OU' } } | Should -Throw '*was not found*'
    }
}

Describe 'AddUser_csv.ps1' {

    BeforeEach { Reset-FakeAD }

    It 'builds the SAM from firstname_lastname in lower case' {
        $csv = New-TestCsv @('Firstname,Lastname', 'Omar,Gabl')

        Invoke-AdScript 'AddUser_csv.ps1' @{ CsvPath = $csv; OUName = 'Sales_Marketing' }

        $script:AD.Users.ContainsKey('omar_gabl') | Should -BeTrue
        $script:AD.Users['omar_gabl'].UserPrincipalName | Should -Be 'omar_gabl@bash.local'
        @($script:AD.Calls | Where-Object Cmdlet -eq 'New-ADUser').Count | Should -Be 1
    }

    It 'rejects a CSV without the Lastname column' {
        $csv = New-TestCsv @('Firstname', 'Omar')

        { Invoke-AdScript 'AddUser_csv.ps1' @{ CsvPath = $csv } } | Should -Throw '*missing the*Lastname*'
    }
}

Describe 'Remove.ps1' {

    BeforeEach { Reset-FakeAD }

    It 'removes only the accounts that exist' {
        $script:AD.Users['user140'] = [pscustomobject]@{ SamAccountName = 'user140' }
        $script:AD.Users['user142'] = [pscustomobject]@{ SamAccountName = 'user142' }

        Invoke-AdScript 'Remove.ps1' @{ StartAt = 140; Count = 3 }

        @($script:AD.Calls | Where-Object Cmdlet -eq 'Remove-ADUser').Count | Should -Be 2
        $script:AD.Users.ContainsKey('user140') | Should -BeFalse
        $script:AD.Users.ContainsKey('user142') | Should -BeFalse
    }

    It 'does not remove anything with -WhatIf' {
        $script:AD.Users['user140'] = [pscustomobject]@{ SamAccountName = 'user140' }

        Invoke-AdScript 'Remove.ps1' @{ StartAt = 140; Count = 1; WhatIf = $true }

        @($script:AD.Calls | Where-Object Cmdlet -eq 'Remove-ADUser').Count | Should -Be 0
        $script:AD.Users.ContainsKey('user140') | Should -BeTrue
    }
}

Describe 'Remove_csv.ps1' {

    BeforeEach { Reset-FakeAD }

    It 'removes the account rebuilt from the CSV' {
        $csv = New-TestCsv @('Firstname,Lastname', 'Omar,Gabl')
        $script:AD.Users['omar_gabl'] = [pscustomobject]@{ SamAccountName = 'omar_gabl' }

        Invoke-AdScript 'Remove_csv.ps1' @{ CsvPath = $csv }

        $script:AD.Users.ContainsKey('omar_gabl') | Should -BeFalse
    }

    It 'does not remove anything with -WhatIf' {
        $csv = New-TestCsv @('Firstname,Lastname', 'Omar,Gabl')
        $script:AD.Users['omar_gabl'] = [pscustomobject]@{ SamAccountName = 'omar_gabl' }

        Invoke-AdScript 'Remove_csv.ps1' @{ CsvPath = $csv; WhatIf = $true }

        $script:AD.Users.ContainsKey('omar_gabl') | Should -BeTrue
    }
}

Describe 'ADComputer.ps1' {

    BeforeEach { Reset-FakeAD }

    It 'creates the computer protected from accidental deletion' {
        Invoke-AdScript 'ADComputer.ps1' @{ ComputerName = 'PC-IT-01'; OUName = 'IT_Department' }

        $call = $script:AD.Calls | Where-Object Cmdlet -eq 'New-ADComputer'
        $call.Name | Should -Be 'PC-IT-01'
        $call.Path | Should -Be 'OU=IT_Department,OU=Corporate_HQ,DC=bash,DC=local'
        $call.Protected | Should -BeTrue
    }

    It 'falls back to CN=Computers when the OU is missing' {
        Invoke-AdScript 'ADComputer.ps1' @{ ComputerName = 'PC-IT-02'; OUName = 'No_Such_OU' }

        $call = $script:AD.Calls | Where-Object Cmdlet -eq 'New-ADComputer'
        $call.Path | Should -Be 'CN=Computers,DC=bash,DC=local'
    }

    It 'creates nothing with -WhatIf' {
        Invoke-AdScript 'ADComputer.ps1' @{ ComputerName = 'PC-IT-03'; WhatIf = $true }

        @($script:AD.Calls | Where-Object Cmdlet -eq 'New-ADComputer').Count | Should -Be 0
    }
}

Describe 'Move_ADComputer.ps1' {

    BeforeEach { Reset-FakeAD }

    It 'moves the computer and re-enables protection' {
        Add-FakeComputer -Name 'PC-IT-01' -ParentDN 'OU=IT_Department,OU=Corporate_HQ,DC=bash,DC=local'

        Invoke-AdScript 'Move_ADComputer.ps1' @{
            ComputerName  = 'PC-IT-01'
            SourceOU      = 'IT_Department'
            DestinationOU = 'Sales_Marketing'
        }

        $script:AD.Computers['PC-IT-01'].DistinguishedName |
            Should -Be 'CN=PC-IT-01,OU=Sales_Marketing,OU=Corporate_HQ,DC=bash,DC=local'
        $script:AD.Computers['PC-IT-01'].ProtectedFromAccidentalDeletion | Should -BeTrue
        @($script:AD.Calls | Where-Object Cmdlet -eq 'Move-ADObject').Count | Should -Be 1
        @($script:AD.Calls | Where-Object { $_.Cmdlet -eq 'Set-ADObject' -and $_.Protected }).Count | Should -Be 1
    }

    It 'refuses when the computer is not inside the source OU' {
        Add-FakeComputer -Name 'PC-IT-01' -ParentDN 'OU=Sales_Marketing,OU=Corporate_HQ,DC=bash,DC=local'

        Invoke-AdScript 'Move_ADComputer.ps1' @{
            ComputerName  = 'PC-IT-01'
            SourceOU      = 'IT_Department'
            DestinationOU = 'Sales_Marketing'
        }

        @($script:AD.Calls | Where-Object Cmdlet -eq 'Move-ADObject').Count | Should -Be 0
        $script:AD.Computers['PC-IT-01'].DistinguishedName |
            Should -Be 'CN=PC-IT-01,OU=Sales_Marketing,OU=Corporate_HQ,DC=bash,DC=local'
    }

    It 'does not move anything with -WhatIf' {
        Add-FakeComputer -Name 'PC-IT-01' -ParentDN 'OU=IT_Department,OU=Corporate_HQ,DC=bash,DC=local'

        Invoke-AdScript 'Move_ADComputer.ps1' @{
            ComputerName  = 'PC-IT-01'
            SourceOU      = 'IT_Department'
            DestinationOU = 'Sales_Marketing'
            WhatIf        = $true
        }

        @($script:AD.Calls | Where-Object Cmdlet -eq 'Move-ADObject').Count | Should -Be 0
        $script:AD.Computers['PC-IT-01'].DistinguishedName |
            Should -Be 'CN=PC-IT-01,OU=IT_Department,OU=Corporate_HQ,DC=bash,DC=local'
    }
}

Describe 'Remove_Computer.ps1' {

    BeforeEach { Reset-FakeAD }

    It 'unlocks the object, deletes it and confirms first' {
        Add-FakeComputer -Name 'PC-DEMO-01' -ParentDN 'OU=IT_Department,OU=Corporate_HQ,DC=bash,DC=local'

        Invoke-AdScript 'Remove_Computer.ps1' @{ ComputerName = 'PC-DEMO-01' }

        $script:AD.Prompts.Count | Should -Be 1
        $script:AD.Computers.ContainsKey('PC-DEMO-01') | Should -BeFalse
        @($script:AD.Calls | Where-Object Cmdlet -eq 'Remove-ADComputer').Count | Should -Be 1
    }

    It 'deletes nothing when the answer is not Y' {
        Add-FakeComputer -Name 'PC-DEMO-01' -ParentDN 'OU=IT_Department,OU=Corporate_HQ,DC=bash,DC=local'
        $script:Answer = 'N'

        Invoke-AdScript 'Remove_Computer.ps1' @{ ComputerName = 'PC-DEMO-01' }

        $script:AD.Computers.ContainsKey('PC-DEMO-01') | Should -BeTrue
        @($script:AD.Calls | Where-Object Cmdlet -eq 'Remove-ADComputer').Count | Should -Be 0
    }

    It 'does not prompt and deletes nothing with -WhatIf' {
        Add-FakeComputer -Name 'PC-DEMO-01' -ParentDN 'OU=IT_Department,OU=Corporate_HQ,DC=bash,DC=local'

        Invoke-AdScript 'Remove_Computer.ps1' @{ ComputerName = 'PC-DEMO-01'; WhatIf = $true }

        $script:AD.Prompts.Count | Should -Be 0
        $script:AD.Computers.ContainsKey('PC-DEMO-01') | Should -BeTrue
        @($script:AD.Calls | Where-Object Cmdlet -eq 'Remove-ADComputer').Count | Should -Be 0
    }

    It 'does not prompt when -Force is used' {
        Add-FakeComputer -Name 'PC-DEMO-01' -ParentDN 'OU=IT_Department,OU=Corporate_HQ,DC=bash,DC=local'

        Invoke-AdScript 'Remove_Computer.ps1' @{ ComputerName = 'PC-DEMO-01'; Force = $true }

        $script:AD.Prompts.Count | Should -Be 0
        $script:AD.Computers.ContainsKey('PC-DEMO-01') | Should -BeFalse
    }

    It 'cancels when the computer name is blank' {
        $script:Answer = ''

        Invoke-AdScript 'Remove_Computer.ps1' @{}

        @($script:AD.Calls | Where-Object Cmdlet -eq 'Remove-ADComputer').Count | Should -Be 0
    }
}
