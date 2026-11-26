#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Legt die OU-Struktur, Abteilungsgruppen und Freigabegruppen der Firma an.
.DESCRIPTION
    Idempotent: kann beliebig oft ausgefuehrt werden, vorhandene Objekte bleiben unveraendert.
    Gruppenmodell AGDLP: Benutzer -> globale Abteilungsgruppe (GG_) -> domaenenlokale Berechtigungsgruppe (DL_) -> Freigabe.
#>
[CmdletBinding()]
param(
    [string]$Firma = 'Firma',
    [string[]]$Abteilungen = @('Geschaeftsfuehrung', 'IT', 'Vertrieb', 'Buchhaltung', 'Technik')
)

$ErrorActionPreference = 'Stop'
$domain = (Get-ADDomain).DistinguishedName

function New-OuIfMissing {
    param([string]$Name, [string]$Path)
    $dn = "OU=$Name,$Path"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $true
        Write-Host "OU angelegt: $dn" -ForegroundColor Green
    }
    $dn
}

function New-GroupIfMissing {
    param([string]$Name, [string]$Path, [string]$Scope, [string]$Description)
    if (-not (Get-ADGroup -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $Name -Path $Path -GroupScope $Scope -GroupCategory Security -Description $Description
        Write-Host "Gruppe angelegt: $Name ($Scope)" -ForegroundColor Green
    }
}

$firmaOu    = New-OuIfMissing -Name $Firma -Path $domain
$benutzerOu = New-OuIfMissing -Name 'Benutzer' -Path $firmaOu
$computerOu = New-OuIfMissing -Name 'Computer' -Path $firmaOu
$gruppenOu  = New-OuIfMissing -Name 'Gruppen' -Path $firmaOu
New-OuIfMissing -Name 'Server' -Path $firmaOu | Out-Null
New-OuIfMissing -Name 'Deaktiviert' -Path $firmaOu | Out-Null

foreach ($abt in $Abteilungen) {
    New-OuIfMissing -Name $abt -Path $benutzerOu | Out-Null
    New-GroupIfMissing -Name "GG_$abt" -Path $gruppenOu -Scope Global -Description "Alle Mitarbeitenden der Abteilung $abt"
    New-GroupIfMissing -Name "DL_Share_${abt}_RW" -Path $gruppenOu -Scope DomainLocal -Description "Lesen/Schreiben auf Abteilungsfreigabe $abt"
    New-GroupIfMissing -Name "DL_Share_${abt}_R" -Path $gruppenOu -Scope DomainLocal -Description "Nur Lesen auf Abteilungsfreigabe $abt"
    if (-not (Get-ADGroupMember "DL_Share_${abt}_RW" | Where-Object Name -eq "GG_$abt")) {
        Add-ADGroupMember -Identity "DL_Share_${abt}_RW" -Members "GG_$abt"
    }
}

New-GroupIfMissing -Name 'GG_Alle_Mitarbeitenden' -Path $gruppenOu -Scope Global -Description 'Alle aktiven Mitarbeitenden'
foreach ($abt in $Abteilungen) {
    if (-not (Get-ADGroupMember 'GG_Alle_Mitarbeitenden' | Where-Object Name -eq "GG_$abt")) {
        Add-ADGroupMember -Identity 'GG_Alle_Mitarbeitenden' -Members "GG_$abt"
    }
}

redircmp $computerOu | Out-Null
Write-Host "Neue Computer landen ab jetzt in: $computerOu" -ForegroundColor Cyan

Get-ADOrganizationalUnit -SearchBase $firmaOu -Filter * |
    Sort-Object DistinguishedName |
    Select-Object Name, DistinguishedName |
    Format-Table -AutoSize
