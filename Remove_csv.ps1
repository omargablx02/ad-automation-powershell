<#
.SYNOPSIS
    Bulk-remove Active Directory users listed in a CSV file.

.DESCRIPTION
    Reads Firstname,Lastname from a CSV, rebuilds the SAM, and removes the account.
    Missing accounts are reported and skipped, never treated as an error.
    Supports -WhatIf so the selection can be checked before anything is deleted.

.PARAMETER CsvPath
    Path to the CSV. Defaults to users.csv next to this script.

.EXAMPLE
    .\Remove_csv.ps1 -CsvPath .\users.csv

.EXAMPLE
    .\Remove_csv.ps1 -CsvPath .\users.csv -WhatIf

.NOTES
    Requires RSAT-AD-PowerShell and an elevated session.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateNotNullOrEmpty()]
    [string]$CsvPath = (Join-Path $PSScriptRoot 'users.csv')
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

$deleted = 0
$missing = 0
$failed  = 0
$planned = 0

foreach ($User in $Users) {

    $Sam         = ($User.Firstname + '_' + $User.Lastname).ToLower()
    $DisplayName = $User.Firstname + ' ' + $User.Lastname

    if ([string]::IsNullOrWhiteSpace($Sam) -or $Sam -eq '_') { continue }

    if (-not (Get-ADUser -Filter "SamAccountName -eq '$Sam'" -ErrorAction SilentlyContinue)) {
        $missing++
        Write-Host "[ -- ] $DisplayName ($Sam) not found" -ForegroundColor DarkGray
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($Sam, 'Remove Active Directory user')) {
        $planned++
        continue
    }

    try {
        Remove-ADUser -Identity $Sam -Confirm:$false -ErrorAction Stop
        $deleted++
        Write-Host "[DEL ] $DisplayName ($Sam)" -ForegroundColor Yellow
    }
    catch {
        $failed++
        Write-Host "[FAIL] $DisplayName - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ''
$summary = "Deleted: $deleted   Not found: $missing   Failed: $failed"
if ($planned -gt 0) { $summary += "   Would delete: $planned" }
Write-Host $summary -ForegroundColor Cyan
