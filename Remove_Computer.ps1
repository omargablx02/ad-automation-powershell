<#
.SYNOPSIS
    Delete a computer account safely: unlock protection, confirm, then remove.

.DESCRIPTION
    Looks the object up first, asks for an explicit confirmation, removes
    accidental-deletion protection and only then deletes the account.
    Nothing is deleted if the name is wrong or the admin answers N.

.PARAMETER ComputerName
    Name of the computer account. If omitted, the script asks for it.

.EXAMPLE
    .\Remove_Computer.ps1 -ComputerName PC-DEMO-01
#>
#Requires -RunAsAdministrator

param(
    [string]$ComputerName
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

    $answer = Read-Host 'Permanently delete this computer? (Y/N)'
    if ($answer -notin @('Y', 'y')) {
        Write-Host '[CANCELLED] Nothing was deleted.' -ForegroundColor Yellow
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
