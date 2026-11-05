<#
.SYNOPSIS
    Bulk-remove Active Directory users listed in a CSV file.

.DESCRIPTION
    Reads Firstname,Lastname from a CSV, rebuilds the SAM, and removes the account.
    Missing accounts are reported and skipped, never treated as an error.

.PARAMETER CsvPath
    Path to the CSV. Defaults to users.csv next to this script.

.EXAMPLE
    .\Remove_csv.ps1 -CsvPath .\users.csv
#>
#Requires -RunAsAdministrator

param(
    [string]$CsvPath = (Join-Path $PSScriptRoot 'users.csv')
)

Import-Module ActiveDirectory -ErrorAction Stop

if (-not (Test-Path -Path $CsvPath)) {
    throw "CSV not found: $CsvPath"
}

$Users = Import-Csv -Path $CsvPath

$deleted = 0
$missing = 0
$failed  = 0

foreach ($User in $Users) {

    $Sam        = ($User.Firstname + '_' + $User.Lastname).ToLower()
    $DisplayNam = $User.Firstname + ' ' + $User.Lastname

    if ([string]::IsNullOrWhiteSpace($Sam)) { continue }

    if (-not (Get-ADUser -Filter "SamAccountName -eq '$Sam'" -ErrorAction SilentlyContinue)) {
        $missing++
        Write-Host "[ -- ] $DisplayNam ($Sam) not found" -ForegroundColor DarkGray
        continue
    }

    try {
        Remove-ADUser -Identity $Sam -Confirm:$false -ErrorAction Stop
        $deleted++
        Write-Host "[DEL ] $DisplayNam ($Sam)" -ForegroundColor Yellow
    }
    catch {
        $failed++
        Write-Host "[FAIL] $DisplayNam - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ''
Write-Host "Deleted: $deleted   Not found: $missing   Failed: $failed" -ForegroundColor Cyan
