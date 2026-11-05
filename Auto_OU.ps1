<#
.SYNOPSIS
    Build an Organizational Unit tree from a CSV file.

.DESCRIPTION
    Reads Name,Path from a CSV, replaces the placeholder domain with the domain of
    the current server, sorts parents before children, and creates every OU with
    accidental-deletion protection. Existing OUs are skipped.

    CSV format:
        Name,Path
        Corporate_HQ,"DC=company,DC=local"
        IT_Department,"OU=Corporate_HQ,DC=company,DC=local"

.PARAMETER CsvPath
    Path to the CSV. Defaults to OUs_To_Create.csv next to this script.

.EXAMPLE
    .\Auto_OU.ps1 -CsvPath .\OUs_To_Create.csv
#>
#Requires -RunAsAdministrator

param(
    [string]$CsvPath = (Join-Path $PSScriptRoot 'OUs_To_Create.csv')
)

Import-Module ActiveDirectory -ErrorAction Stop

if (-not (Test-Path -Path $CsvPath)) {
    throw "CSV not found: $CsvPath"
}

$DomainDN = (Get-ADDomain).DistinguishedName

Write-Host "[INFO] Detected domain DN: $DomainDN" -ForegroundColor Cyan
Write-Host "[INFO] CSV: $CsvPath" -ForegroundColor DarkGray
Write-Host ''

# Replace the placeholder domain, then sort so parents are created before children.
$OUs = Import-Csv -Path $CsvPath | ForEach-Object {
    [pscustomobject]@{
        Name = $_.Name
        Path = $_.Path -replace 'DC=company,DC=local', $DomainDN
    }
} | Sort-Object { $_.Path.Length }

$created = 0
$skipped = 0
$failed  = 0

foreach ($OU in $OUs) {

    $TargetDN = "OU=$($OU.Name),$($OU.Path)"

    if (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$TargetDN'" -ErrorAction SilentlyContinue) {
        $skipped++
        Write-Host "[SKIP] $($OU.Name) (already exists)" -ForegroundColor Yellow
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
Write-Host "Created: $created   Skipped: $skipped   Failed: $failed" -ForegroundColor Cyan
