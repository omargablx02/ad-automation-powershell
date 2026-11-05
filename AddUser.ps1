<#
.SYNOPSIS
    Bulk-create numbered Active Directory users in a chosen OU.

.DESCRIPTION
    Creates User01, User02 ... with a forced password change at first logon.
    The target OU is resolved by name at runtime, so nothing is tied to one domain.
    Existing accounts are skipped instead of throwing errors.

.PARAMETER StartAt
    First number in the series. Default 1.

.PARAMETER Count
    How many users to create. Default 50.

.PARAMETER OUName
    Display name of the target OU. Default Sales_Marketing.

.EXAMPLE
    .\AddUser.ps1 -StartAt 140 -Count 11 -OUName Sales_Marketing
#>
#Requires -RunAsAdministrator

param(
    [int]$StartAt = 1,
    [int]$Count = 50,
    [string]$OUName = 'Sales_Marketing'
)

Import-Module ActiveDirectory -ErrorAction Stop

$Domain   = Get-ADDomain
$Suffix   = $Domain.DNSRoot
$DomainDN = $Domain.DistinguishedName

$TargetOU = (Get-ADOrganizationalUnit -Filter "Name -eq '$OUName'" -ErrorAction SilentlyContinue |
             Select-Object -First 1).DistinguishedName

if (-not $TargetOU) {
    throw "OU '$OUName' was not found in $Suffix. Create it first (see Auto_OU.ps1)."
}

$Password = Read-Host -Prompt 'Password for the new users' -AsSecureString

Write-Host "Domain    : $Suffix" -ForegroundColor DarkGray
Write-Host "Target OU : $TargetOU" -ForegroundColor Cyan
Write-Host ''

$created = 0
$skipped = 0
$failed  = 0

for ($i = $StartAt; $i -lt ($StartAt + $Count); $i++) {

    $Number     = '{0:00}' -f $i
    $Sam        = "User$Number"
    $DisplayNam = "User $Number"

    if (Get-ADUser -Filter "SamAccountName -eq '$Sam'" -ErrorAction SilentlyContinue) {
        $skipped++
        Write-Host "[SKIP] $Sam already exists." -ForegroundColor Yellow
        continue
    }

    try {
        New-ADUser -Name $DisplayNam `
                   -SamAccountName $Sam `
                   -UserPrincipalName "$Sam@$Suffix" `
                   -GivenName 'User' `
                   -Surname $Number `
                   -Path $TargetOU `
                   -AccountPassword $Password `
                   -Enabled $true `
                   -ChangePasswordAtLogon $true `
                   -ErrorAction Stop

        $created++
        Write-Host "[ OK ] $Sam" -ForegroundColor Green
    }
    catch {
        $failed++
        Write-Host "[FAIL] $Sam - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ''
Write-Host "Created: $created   Skipped: $skipped   Failed: $failed" -ForegroundColor Cyan
