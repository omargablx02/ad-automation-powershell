<#
.SYNOPSIS
    Move a computer object between OUs while keeping accidental-deletion protection on.

.DESCRIPTION
    Takes the source OU, the destination OU and the computer name, validates all
    three, temporarily removes accidental-deletion protection, moves the object and
    re-enables protection on the target. Moving a protected object fails with
    "Access is denied" unless protection is lifted first.

    Any parameter that is not supplied is asked for interactively, so the script runs
    the same way by hand or from another script.

.PARAMETER ComputerName
    Name of the computer account to move.

.PARAMETER SourceOU
    Display name of the OU the object is currently in.

.PARAMETER DestinationOU
    Display name of the OU the object should end up in.

.EXAMPLE
    .\Move_ADComputer.ps1 -ComputerName PC-IT-01 -SourceOU IT_Department -DestinationOU Sales_Marketing

.EXAMPLE
    .\Move_ADComputer.ps1 -ComputerName PC-IT-01 -SourceOU IT_Department -DestinationOU Sales_Marketing -WhatIf

.EXAMPLE
    .\Move_ADComputer.ps1

.NOTES
    Requires RSAT-AD-PowerShell and an elevated session.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$ComputerName,
    [string]$SourceOU,
    [string]$DestinationOU
)

Import-Module ActiveDirectory -ErrorAction Stop

function Resolve-OU {
    param([string]$Name)
    (Get-ADOrganizationalUnit -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue |
     Select-Object -First 1).DistinguishedName
}

if ([string]::IsNullOrWhiteSpace($SourceOU)) {
    $SourceOU = Read-Host -Prompt 'Enter SOURCE OU name (e.g., Human_Resources)'
}

if ([string]::IsNullOrWhiteSpace($DestinationOU)) {
    $DestinationOU = Read-Host -Prompt 'Enter DESTINATION OU name (e.g., IT_Department)'
}

if ([string]::IsNullOrWhiteSpace($ComputerName)) {
    $ComputerName = Read-Host -Prompt 'Enter the computer name to migrate'
}

if ([string]::IsNullOrWhiteSpace($ComputerName)) {
    Write-Warning 'Operation cancelled: computer name cannot be empty.'
    return
}

$SourceDN = Resolve-OU -Name $SourceOU
$DestDN   = Resolve-OU -Name $DestinationOU

Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ' AD asset migration                          ' -ForegroundColor Cyan
Write-Host '=============================================' -ForegroundColor Cyan

try {
    if (-not $SourceDN) { throw "Source OU '$SourceOU' does not exist." }
    if (-not $DestDN)   { throw "Destination OU '$DestinationOU' does not exist." }

    $Computer = Get-ADComputer -Identity $ComputerName -ErrorAction Stop

    if ($Computer.DistinguishedName -notlike "*,$SourceDN") {
        throw "'$ComputerName' is not inside '$SourceOU'."
    }

    if ($Computer.DistinguishedName -like "*,$DestDN") {
        Write-Host "[SKIP] $ComputerName is already in '$DestinationOU'." -ForegroundColor Yellow
        return
    }

    Write-Host "[ OK ] Source OU      : $SourceDN" -ForegroundColor Green
    Write-Host "[ OK ] Destination OU : $DestDN" -ForegroundColor Green
    Write-Host "[ OK ] Object         : $($Computer.DistinguishedName)" -ForegroundColor Green

    if (-not $PSCmdlet.ShouldProcess($ComputerName, "Move to $DestinationOU")) {
        return
    }

    $protected = (Get-ADObject -Identity $Computer.DistinguishedName -Properties ProtectedFromAccidentalDeletion).ProtectedFromAccidentalDeletion
    if ($protected) {
        Set-ADObject -Identity $Computer.DistinguishedName -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
        Write-Host '[INFO] Protection temporarily removed.' -ForegroundColor Yellow
    }

    $Computer | Move-ADObject -TargetPath $DestDN -ErrorAction Stop

    $newDN = (Get-ADComputer -Identity $ComputerName).DistinguishedName
    Set-ADObject -Identity $newDN -ProtectedFromAccidentalDeletion $true -ErrorAction Stop

    Write-Host "[ OK ] $ComputerName moved to '$DestinationOU'." -ForegroundColor Green
    Write-Host '[INFO] Protection re-enabled on the object.' -ForegroundColor Green
}
catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    Write-Host "[FAIL] Computer '$ComputerName' was not found." -ForegroundColor Red
}
catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
}
