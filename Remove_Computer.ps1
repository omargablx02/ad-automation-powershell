<#
.SYNOPSIS
    Delete a computer account safely: unlock protection, confirm, then remove.

.DESCRIPTION
    Looks the object up first, asks for an explicit confirmation, removes
    accidental-deletion protection and only then deletes the account.
    Nothing is deleted if the name is wrong or the admin answers N.

.PARAMETER ComputerName
    Name of the computer account. If omitted, the script asks for it.

.PARAMETER Force
    Skip the Y/N prompt. Intended for unattended runs - use with care.

.EXAMPLE
    .\Remove_Computer.ps1 -ComputerName PC-DEMO-01

.EXAMPLE
    .\Remove_Computer.ps1 -ComputerName PC-DEMO-01 -WhatIf

.EXAMPLE
    .\Remove_Computer.ps1 -ComputerName PC-DEMO-01 -Force

.NOTES
    Requires RSAT-AD-PowerShell and an elevated session.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$ComputerName,

    [switch]$Force
)

Import-Module ActiveDirectory -ErrorAction Stop

if ([string]::IsNullOrWhiteSpace($ComputerName)) {
    $ComputerName = Read-Host -Prompt 'Enter computer name to remove'
}

if ([string]::IsNullOrWhiteSpace($ComputerName)) {
    Write-Warning 'Operation cancelled: computer name cannot be blank.'
    return
}

try {
    $Computer = Get-ADComputer -Identity $ComputerName -ErrorAction Stop
    Write-Host "[INFO] Found: $($Computer.DistinguishedName)" -ForegroundColor Cyan

    if (-not $Force) {
        $answer = Read-Host 'Permanently delete this computer? (Y/N)'
        if ($answer -notin @('Y', 'y')) {
            Write-Host '[CANCELLED] Nothing was deleted.' -ForegroundColor Yellow
            return
        }
    }

    if (-not $PSCmdlet.ShouldProcess($ComputerName, 'Remove Active Directory computer')) {
        return
    }

    Set-ADObject -Identity $Computer.DistinguishedName `
                 -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
    Write-Host '[INFO] Accidental deletion protection removed.' -ForegroundColor Yellow

    Remove-ADComputer -Identity $Computer.DistinguishedName -Confirm:$false -ErrorAction Stop
    Write-Host "[ OK ] $ComputerName removed from Active Directory." -ForegroundColor Green
}
catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    Write-Host "[FAIL] Computer '$ComputerName' does not exist." -ForegroundColor Red
}
catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
}
