<#
.SYNOPSIS
    Create a computer object in a chosen OU, protected from accidental deletion.

.DESCRIPTION
    The domain is detected at runtime, so the same script works in any lab.
    If the OU is not found the object goes to the default Computers container.
    Existing objects are skipped instead of throwing errors.

.PARAMETER ComputerName
    Name of the computer account. Default PC-DEMO-01.

.PARAMETER OUName
    Display name of the target OU. Default IT_Department.

.PARAMETER Description
    Description stored on the object.

.EXAMPLE
    .\ADComputer.ps1 -ComputerName PC-IT-01 -OUName IT_Department
#>
#Requires -RunAsAdministrator

param(
    [string]$ComputerName = 'PC-DEMO-01',
    [string]$OUName = 'IT_Department',
    [string]$Description = 'Workstation created by ADComputer.ps1'
)

Import-Module ActiveDirectory -ErrorAction Stop

$DomainDN = (Get-ADDomain).DistinguishedName

$TargetOU = (Get-ADOrganizationalUnit -Filter "Name -eq '$OUName'" -ErrorAction SilentlyContinue |
             Select-Object -First 1).DistinguishedName

if (-not $TargetOU) {
    $TargetOU = "CN=Computers,$DomainDN"
    Write-Host "[WARN] OU '$OUName' not found - using CN=Computers." -ForegroundColor Yellow
}

Write-Host "Computer  : $ComputerName" -ForegroundColor Cyan
Write-Host "Target OU : $TargetOU" -ForegroundColor Cyan
Write-Host ''

try {
    if (Get-ADComputer -Filter "Name -eq '$ComputerName'" -ErrorAction SilentlyContinue) {
        Write-Host "[SKIP] $ComputerName already exists." -ForegroundColor Yellow
        return
    }

    New-ADComputer -Name $ComputerName `
                   -SamAccountName $ComputerName `
                   -Path $TargetOU `
                   -Description $Description `
                   -Enabled $true `
                   -ProtectedFromAccidentalDeletion $true `
                   -ErrorAction Stop

    Write-Host "[ OK ] $ComputerName created and protected from accidental deletion." -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
}
