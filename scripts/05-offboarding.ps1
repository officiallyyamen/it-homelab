#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Offboarding: sperrt das Konto eines ausscheidenden Mitarbeiters und dokumentiert den Vorgang.
.DESCRIPTION
    - Konto deaktivieren und Passwort auf einen zufaelligen Wert setzen
    - alle Gruppenmitgliedschaften entfernen (vorher protokollieren)
    - Konto in die OU "Deaktiviert" verschieben, Austrittsdatum in die Beschreibung
    - Protokoll als CSV unter C:\IT\Offboarding
    Das Konto wird nicht geloescht, damit Daten und Postfach geordnet uebergeben werden koennen.
.EXAMPLE
    .\05-offboarding.ps1 -Benutzer lukas.huber2 -Ticket 1042 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string[]]$Benutzer,
    [string]$Ticket = '',
    [string]$OutputDir = 'C:\IT\Offboarding',
    [string]$Firma = 'Firma'
)

$ErrorActionPreference = 'Stop'
$domain = Get-ADDomain
$zielOu = "OU=Deaktiviert,OU=$Firma,$($domain.DistinguishedName)"
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
$protokoll = [Collections.Generic.List[object]]::new()

foreach ($sam in $Benutzer) {
    $user = Get-ADUser -Identity $sam -Properties MemberOf, Description, Department, Title
    $gruppen = $user.MemberOf | ForEach-Object { (Get-ADGroup $_).Name }

    if (-not $PSCmdlet.ShouldProcess($user.Name, 'Konto sperren, Gruppen entfernen, nach Deaktiviert verschieben')) { continue }

    Disable-ADAccount -Identity $user
    $bytes = [byte[]]::new(24)
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $zufall = [Convert]::ToBase64String($bytes)
    Set-ADAccountPassword -Identity $user -Reset -NewPassword (ConvertTo-SecureString "$zufall!a1" -AsPlainText -Force)
    foreach ($g in $user.MemberOf) { Remove-ADGroupMember -Identity $g -Members $user -Confirm:$false }
    $notiz = "Ausgetreten $(Get-Date -Format yyyy-MM-dd)" + $(if ($Ticket) { ", Ticket $Ticket" } else { '' })
    Set-ADUser -Identity $user -Description $notiz
    Move-ADObject -Identity $user.DistinguishedName -TargetPath $zielOu

    $protokoll.Add([pscustomobject]@{
        Datum            = Get-Date -Format 'yyyy-MM-dd HH:mm'
        Benutzer         = $sam
        Name             = $user.Name
        Abteilung        = $user.Department
        Funktion         = $user.Title
        EntfernteGruppen = ($gruppen -join ', ')
        Ticket           = $Ticket
        Durchgefuehrt    = $env:USERNAME
    })
    Write-Host "$($user.Name) offboarded" -ForegroundColor Green
}

if ($protokoll.Count) {
    $datei = Join-Path $OutputDir ("{0:yyyy-MM}-offboarding.csv" -f (Get-Date))
    $protokoll | Export-Csv -Path $datei -Delimiter ';' -NoTypeInformation -Encoding UTF8 -Append
    Write-Host "Protokoll: $datei" -ForegroundColor Yellow
    $protokoll | Format-List
}
