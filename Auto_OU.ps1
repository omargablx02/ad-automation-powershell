<#
.SYNOPSIS
    Build an Organizational Unit tree from a CSV file.

.DESCRIPTION
    Reads Name,Path from a CSV, validates every row, replaces the placeholder
    domain with the domain of the current server, sorts parents before children
    (by OU depth, then path length), and creates every OU with
    accidental-deletion protection. Existing OUs are skipped.

    The script stops before creating anything if the CSV has invalid rows:
    empty Name/Path, a Name containing , = or +, a leftover "DC=company"
    placeholder, or a Path that does not end with the current domain DN.

    CSV format:
        Name,Path
        Corporate_HQ,"DC=company,DC=local"
        IT_Department,"OU=Corporate_HQ,DC=company,DC=local"

.PARAMETER CsvPath
    Path to the CSV. Defaults to OUs_To_Create.csv next to this script.

.EXAMPLE
    .\Auto_OU.ps1 -CsvPath .\OUs_To_Create.csv

.EXAMPLE
    .\Auto_OU.ps1 -WhatIf

.NOTES
    Requires RSAT-AD-PowerShell and an elevated session.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [ValidateNotNullOrEmpty()]
    [string]$CsvPath = (Join-Path $PSScriptRoot 'OUs_To_Create.csv')
)

Import-Module ActiveDirectory -ErrorAction Stop

if (-not (Test-Path -Path $CsvPath)) {
    throw "CSV not found: $CsvPath"
}

$rows = @(Import-Csv -Path $CsvPath)

if ($rows.Count -eq 0) {
    throw "CSV is empty: $CsvPath"
}

$columns = $rows[0].PSObject.Properties.Name
foreach ($required in 'Name', 'Path') {
    if ($columns -notcontains $required) {
        throw "CSV is missing the '$required' column. Expected: Name,Path"
    }
}

$DomainDN = (Get-ADDomain).DistinguishedName

Write-Host "[INFO] Detected domain DN: $DomainDN" -ForegroundColor Cyan
Write-Host "[INFO] CSV: $CsvPath ($($rows.Count) rows)" -ForegroundColor DarkGray
Write-Host ''

# Replace the placeholder domain, validate, then sort so parents come before children.
$Placeholder = 'DC=company,DC=local'
$OUs     = @()
$invalid = @()
$rowNo   = 0

foreach ($row in $rows) {
    $rowNo++
    $Name = "$($row.Name)".Trim()
    $Path = "$($row.Path)".Trim()

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $invalid += "row $rowNo : Name is empty"
        continue
    }
    if ($Name -match '[,=+]') {
        $invalid += "row $rowNo : Name '$Name' contains an invalid character (, = +)"
        continue
    }
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $invalid += "row $rowNo ($Name) : Path is empty"
        continue
    }

    $Path = $Path -replace [regex]::Escape($Placeholder), $DomainDN

    if ($DomainDN -notmatch 'DC=company' -and $Path -match 'DC=company') {
        $invalid += "row $rowNo ($Name) : placeholder domain was not fully replaced - check the Path"
        continue
    }
    if ($Path -ne $DomainDN -and $Path -notmatch '^OU=') {
        $invalid += "row $rowNo ($Name) : Path must be the domain DN or start with 'OU='"
        continue
    }
    if (-not $Path.EndsWith($DomainDN, [System.StringComparison]::OrdinalIgnoreCase)) {
        $invalid += "row $rowNo ($Name) : Path does not end with the domain DN ($DomainDN)"
        continue
    }

    $OUs += [pscustomobject]@{
        Name = $Name
        Path = $Path
    }
}

if ($invalid.Count -gt 0) {
    throw ("CSV has invalid rows - nothing was created:`n  " + ($invalid -join "`n  "))
}

# Deeper paths (more OU= segments) are children, so they must be created later.
$depth  = @{ Expression = { ([regex]::Matches($_.Path, 'OU=')).Count } }
$length = @{ Expression = { $_.Path.Length } }
$OUs = @($OUs | Sort-Object -Property $depth, $length)

$created = 0
$skipped = 0
$failed  = 0
$planned = 0

foreach ($OU in $OUs) {

    $TargetDN = "OU=$($OU.Name),$($OU.Path)"

    if (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$TargetDN'" -ErrorAction SilentlyContinue) {
        $skipped++
        Write-Host "[SKIP] $($OU.Name) (already exists)" -ForegroundColor Yellow
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($TargetDN, 'Create organizational unit')) {
        $planned++
        continue
    }

    try {
        New-ADOrganizationalUnit -Name $OU.Name `
                                 -Path $OU.Path `
                                 -ProtectedFromAccidentalDeletion $true `
                                 -ErrorAction Stop
        $created++
        Write-Host "[ OK ] $($OU.Name)" -ForegroundColor Green
    }
    catch {
        $failed++
        Write-Host "[FAIL] $($OU.Name) - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ''
$summary = "Created: $created   Skipped: $skipped   Failed: $failed"
if ($planned -gt 0) { $summary += "   Would create: $planned" }
Write-Host $summary -ForegroundColor Cyan
