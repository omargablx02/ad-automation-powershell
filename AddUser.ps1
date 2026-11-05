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

.EXAMPLE
    .\AddUser.ps1 -StartAt 200 -Count 5 -WhatIf

.NOTES
    Requires RSAT-AD-PowerShell and an elevated session.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [ValidateRange(1, 99999)]
    [int]$StartAt = 1,

    [ValidateRange(1, 5000)]
    [int]$Count = 50,

    [ValidateNotNullOrEmpty()]
    [string]$OUName = 'Sales_Marketing'
)

Import-Module ActiveDirectory -ErrorAction Stop

$Domain = Get-ADDomain
$Suffix = $Domain.DNSRoot

$TargetOU = (Get-ADOrganizationalUnit -Filter "Name -eq '$OUName'" -ErrorAction SilentlyContinue |
             Select-Object -First 1).DistinguishedName

if (-not $TargetOU) {
    throw "OU '$OUName' was not found in $Suffix. Create it first (see Auto_OU.ps1)."
}

$Password = $null
if (-not $WhatIfPreference) {
    $Password = Read-Host -Prompt 'Password for the new users' -AsSecureString
}

Write-Host "Domain    : $Suffix" -ForegroundColor DarkGray
Write-Host "Target OU : $TargetOU" -ForegroundColor Cyan
Write-Host ''

$created = 0
$skipped = 0
$failed  = 0
$planned = 0

for ($i = $StartAt; $i -lt ($StartAt + $Count); $i++) {

    $Number      = '{0:00}' -f $i
    $Sam         = "User$Number"
    $DisplayName = "User $Number"

    if (Get-ADUser -Filter "SamAccountName -eq '$Sam'" -ErrorAction SilentlyContinue) {
        $skipped++
        Write-Host "[SKIP] $Sam already exists." -ForegroundColor Yellow
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($Sam, 'Create Active Directory user')) {
        $planned++
        continue
    }

    try {
        New-ADUser -Name $DisplayName `
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
$summary = "Created: $created   Skipped: $skipped   Failed: $failed"
if ($planned -gt 0) { $summary += "   Would create: $planned" }
Write-Host $summary -ForegroundColor Cyan
