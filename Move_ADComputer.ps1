<#
.SYNOPSIS
    Move a computer object between OUs while keeping accidental-deletion protection on.

.DESCRIPTION
    Asks for the source OU, the destination OU and the computer name, validates all
    three, temporarily removes accidental-deletion protection, moves the object and
    re-enables protection on the target. Moving a protected object fails with
    "Access is denied" unless protection is lifted first.

.EXAMPLE
    .\Move_ADComputer.ps1
#>
#Requires -RunAsAdministrator

Import-Module ActiveDirectory -ErrorAction Stop

$DomainDN = (Get-ADDomain).DistinguishedName

function Resolve-OU {
    param([string]$Name)
    (Get-ADOrganizationalUnit -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue |
     Select-Object -First 1).DistinguishedName
}

$SourceOUName = Read-Host -Prompt 'Enter SOURCE OU name (e.g., Human_Resources)'
$DestOUName   = Read-Host -Prompt 'Enter DESTINATION OU name (e.g., IT_Department)'
$ComputerName = Read-Host -Prompt 'Enter the computer name to migrate'

if ([string]::IsNullOrWhiteSpace($ComputerName)) {
    Write-Warning 'Operation cancelled: computer name cannot be empty.'
    return
}

$SourceOU = Resolve-OU -Name $SourceOUName
$DestOU   = Resolve-OU -Name $DestOUName

Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ' AD asset migration                          ' -ForegroundColor Cyan
Write-Host '=============================================' -ForegroundColor Cyan

try {
    if (-not $SourceOU) { throw "Source OU '$SourceOUName' does not exist." }
    if (-not $DestOU)   { throw "Destination OU '$DestOUName' does not exist." }

    $Computer = Get-ADComputer -Identity $ComputerName -ErrorAction Stop

    if ($Computer.DistinguishedName -notlike "*,$SourceOU") {
        throw "'$ComputerName' is not inside '$SourceOUName'."
    }

    if ($Computer.DistinguishedName -like "*,$DestOU") {
        Write-Host "[SKIP] $ComputerName is already in '$DestOUName'." -ForegroundColor Yellow
        return
    }

    Write-Host "[ OK ] Source OU      : $SourceOU" -ForegroundColor Green
    Write-Host "[ OK ] Destination OU : $DestOU" -ForegroundColor Green
    Write-Host "[ OK ] Object         : $($Computer.DistinguishedName)" -ForegroundColor Green

    $protected = (Get-ADObject -Identity $Computer.DistinguishedName -Properties ProtectedFromAccidentalDeletion).ProtectedFromAccidentalDeletion
    if ($protected) {
        Set-ADObject -Identity $Computer.DistinguishedName -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
        Write-Host '[INFO] Protection temporarily removed.' -ForegroundColor Yellow
    }

    $Computer | Move-ADObject -TargetPath $DestOU -ErrorAction Stop

    $newDN = (Get-ADComputer -Identity $ComputerName).DistinguishedName
    Set-ADObject -Identity $newDN -ProtectedFromAccidentalDeletion $true -ErrorAction Stop

    Write-Host "[ OK ] $ComputerName moved to '$DestOUName'." -ForegroundColor Green
    Write-Host '[INFO] Protection re-enabled on the object.' -ForegroundColor Green
}
catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    Write-Host "[FAIL] Computer '$ComputerName' was not found." -ForegroundColor Red
}
catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
}
