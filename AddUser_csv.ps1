<#
.SYNOPSIS
    Bulk-create Active Directory users from a CSV file.

.DESCRIPTION
    Reads Firstname,Lastname from a CSV, builds the SAM and UPN, and creates the
    accounts in a chosen OU with a forced password change. Existing accounts are
    skipped. The CSV must contain both columns; anything else fails before a single
    account is touched.

.PARAMETER CsvPath
    Path to the CSV. Defaults to users.csv next to this script.

.PARAMETER OUName
    Display name of the target OU. Default Sales_Marketing.

.EXAMPLE
    .\AddUser_csv.ps1 -CsvPath .\users.csv -OUName Sales_Marketing

.EXAMPLE
    .\AddUser_csv.ps1 -WhatIf

.NOTES
    Requires RSAT-AD-PowerShell and an elevated session.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [ValidateNotNullOrEmpty()]
    [string]$CsvPath = (Join-Path $PSScriptRoot 'users.csv'),

    [ValidateNotNullOrEmpty()]
    [string]$OUName = 'Sales_Marketing'
)

Import-Module ActiveDirectory -ErrorAction Stop

if (-not (Test-Path -Path $CsvPath)) {
    throw "CSV not found: $CsvPath"
}

$Users = @(Import-Csv -Path $CsvPath)

if ($Users.Count -eq 0) {
    throw "CSV is empty: $CsvPath"
}

$columns = $Users[0].PSObject.Properties.Name
foreach ($required in 'Firstname', 'Lastname') {
    if ($columns -notcontains $required) {
        throw "CSV is missing the '$required' column. Expected: Firstname,Lastname"
    }
}

$Domain = Get-ADDomain
$Suffix = $Domain.DNSRoot

$TargetOU = (Get-ADOrganizationalUnit -Filter "Name -eq '$OUName'" -ErrorAction SilentlyContinue |
             Select-Object -First 1).DistinguishedName

if (-not $TargetOU) {
    throw "OU '$OUName' was not found in $Suffix. Create it first (see Auto_OU.ps1)."
}

Write-Host "Domain    : $Suffix" -ForegroundColor DarkGray
Write-Host "Target OU : $TargetOU" -ForegroundColor Cyan
Write-Host "CSV       : $CsvPath ($($Users.Count) rows)" -ForegroundColor DarkGray
Write-Host ''

$Password = $null
if (-not $WhatIfPreference) {
    $Password = Read-Host -Prompt 'Password for the new users' -AsSecureString
}

$created = 0
$skipped = 0
$failed  = 0
$planned = 0

foreach ($User in $Users) {

    $Sam         = ($User.Firstname + '_' + $User.Lastname).ToLower()
    $DisplayName = $User.Firstname + ' ' + $User.Lastname

    if ([string]::IsNullOrWhiteSpace($Sam) -or $Sam -eq '_') { continue }

    if (Get-ADUser -Filter "SamAccountName -eq '$Sam'" -ErrorAction SilentlyContinue) {
        $skipped++
        Write-Host "[SKIP] $DisplayName ($Sam already exists)" -ForegroundColor Yellow
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
                   -GivenName $User.Firstname `
                   -Surname $User.Lastname `
                   -Path $TargetOU `
                   -AccountPassword $Password `
                   -Enabled $true `
                   -ChangePasswordAtLogon $true `
                   -ErrorAction Stop

        $created++
        Write-Host "[ OK ] $DisplayName  ->  $Sam" -ForegroundColor Green
    }
    catch {
        $failed++
        Write-Host "[FAIL] $DisplayName - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ''
$summary = "Created: $created   Skipped: $skipped   Failed: $failed"
if ($planned -gt 0) { $summary += "   Would create: $planned" }
Write-Host $summary -ForegroundColor Cyan
