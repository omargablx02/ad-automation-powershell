<#
.SYNOPSIS
    Bulk-remove numbered users (User01, User02 ...) from Active Directory.

.DESCRIPTION
    Deletes the numbered series created by AddUser.ps1.
    Accounts that do not exist are reported and skipped, never treated as an error.
    Supports -WhatIf so the selection can be checked before anything is deleted.

.PARAMETER StartAt
    First number in the series. Default 1.

.PARAMETER Count
    How many numbers to check. Default 20.

.EXAMPLE
    .\Remove.ps1 -StartAt 140 -Count 11

.EXAMPLE
    .\Remove.ps1 -StartAt 140 -Count 11 -WhatIf

.NOTES
    Requires RSAT-AD-PowerShell and an elevated session.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateRange(1, 99999)]
    [int]$StartAt = 1,

    [ValidateRange(1, 5000)]
    [int]$Count = 20
)

Import-Module ActiveDirectory -ErrorAction Stop

$deleted = 0
$missing = 0
$failed  = 0
$planned = 0

for ($i = $StartAt; $i -lt ($StartAt + $Count); $i++) {

    $Number = '{0:00}' -f $i
    $Sam    = "User$Number"

    if (-not (Get-ADUser -Filter "SamAccountName -eq '$Sam'" -ErrorAction SilentlyContinue)) {
        $missing++
        Write-Host "[ -- ] $Sam not found" -ForegroundColor DarkGray
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($Sam, 'Remove Active Directory user')) {
        $planned++
        continue
    }

    try {
        Remove-ADUser -Identity $Sam -Confirm:$false -ErrorAction Stop
        $deleted++
        Write-Host "[DEL ] $Sam" -ForegroundColor Yellow
    }
    catch {
        $failed++
        Write-Host "[FAIL] $Sam - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ''
$summary = "Deleted: $deleted   Not found: $missing   Failed: $failed"
if ($planned -gt 0) { $summary += "   Would delete: $planned" }
Write-Host $summary -ForegroundColor Cyan
