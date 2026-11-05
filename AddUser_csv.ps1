<#
.SYNOPSIS
    Bulk-create Active Directory users from a CSV file.

.DESCRIPTION
    Reads Firstname,Lastname from a CSV, builds SAM and UPN, and creates the accounts
    in a chosen OU with a forced password change. Existing accounts are skipped.

.PARAMETER CsvPath
    Path to the CSV. Defaults to users.csv next to this script.

.PARAMETER OUName
    Display name of the target OU. Default Sales_Marketing.

.EXAMPLE
    .\AddUser_csv.ps1 -CsvPath .\users.csv -OUName Sales_Marketing
#>
#Requires -RunAsAdministrator

param(
    [string]$CsvPath = (Join-Path $PSScriptRoot 'users.csv'),
    [string]$OUName = 'Sales_Marketing'
)

Import-Module ActiveDirectory -ErrorAction Stop

if (-not (Test-Path -Path $CsvPath)) {
    throw "CSV not found: $CsvPath"
}

$Domain = Get-ADDomain
$Suffix = $Domain.DNSRoot

$TargetOU = (Get-ADOrganizationalUnit -Filter "Name -eq '$OUName'" -ErrorAction SilentlyContinue |
             Select-Object -First 1).DistinguishedName

if (-not $TargetOU) {
    throw "OU '$OUName' was not found in $Suffix. Create it first (see Auto_OU.ps1)."
}

$Users = Import-Csv -Path $CsvPath

Write-Host "Domain    : $Suffix" -ForegroundColor DarkGray
Write-Host "Target OU : $TargetOU" -ForegroundColor Cyan
Write-Host "CSV       : $CsvPath ($($Users.Count) rows)" -ForegroundColor DarkGray
Write-Host ''

$Password = Read-Host -Prompt 'Password for the new users' -AsSecureString

$created = 0
$skipped = 0
$failed  = 0

foreach ($User in $Users) {

    $Sam         = ($User.Firstname + '_' + $User.Lastname).ToLower()
    $DisplayNam  = $User.Firstname + ' ' + $User.Lastname

    if ([string]::IsNullOrWhiteSpace($Sam)) { continue }

    if (Get-ADUser -Filter "SamAccountName -eq '$Sam'" -ErrorAction SilentlyContinue) {
        $skipped++
        Write-Host "[SKIP] $DisplayNam ($Sam already exists)" -ForegroundColor Yellow
        continue
    }

    try {
        New-ADUser -Name $DisplayNam `
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
        Write-Host "[ OK ] $DisplayNam  ->  $Sam" -ForegroundColor Green
    }
    catch {
        $failed++
        Write-Host "[FAIL] $DisplayNam - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ''
Write-Host "Created: $created   Skipped: $skipped   Failed: $failed" -ForegroundColor Cyan
