#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Legt neue Mitarbeitende aus einer CSV-Datei im Active Directory an.
.DESCRIPTION
    Pro Zeile: Benutzername vorname.nachname (Umlaute umgeschrieben, Duplikate nummeriert),
    Konto in der OU der Abteilung, Mitgliedschaft in GG_<Abteilung>, zufaelliges Startpasswort
    mit Pflicht zur Aenderung bei der ersten Anmeldung.
    Die Zugangsdaten werden nur lokal auf dem Server gespeichert, nie im Repository.
.EXAMPLE
    .\02-onboarding.ps1 -CsvPath S:\data\neue-mitarbeitende.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$CsvPath,
    [string]$OutputDir = 'C:\IT\Onboarding',
    [string]$Firma = 'Firma'
)

$ErrorActionPreference = 'Stop'
$domain = Get-ADDomain
$benutzerOu = "OU=Benutzer,OU=$Firma,$($domain.DistinguishedName)"

function ConvertTo-AsciiName {
    param([string]$Text)
    $Text = $Text.ToLower()
    $map = @{ 'ä' = 'ae'; 'ö' = 'oe'; 'ü' = 'ue'; 'ß' = 'ss'; 'ı' = 'i' }
    foreach ($k in $map.Keys) { $Text = $Text.Replace($k, $map[$k]) }
    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
    $clean = -join ($normalized.ToCharArray() | Where-Object {
        [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })
    ($clean.ToLower() -replace '[^a-z0-9-]', '')
}

function Get-FreeSamAccountName {
    param([string]$Vorname, [string]$Nachname)
    $base = "$(ConvertTo-AsciiName $Vorname).$(ConvertTo-AsciiName $Nachname)"
    if ($base.Length -gt 20) { $base = $base.Substring(0, 20) }
    $candidate = $base
    $i = 2
    while (Get-ADUser -Filter "SamAccountName -eq '$candidate'" -ErrorAction SilentlyContinue) {
        $suffix = "$i"
        $candidate = $base.Substring(0, [Math]::Min($base.Length, 20 - $suffix.Length)) + $suffix
        $i++
    }
    $candidate
}

function New-StartPassword {
    param([int]$Length = 14)
    $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '!$%&*+-=?')
    $all = -join $sets
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = [byte[]]::new($Length)
    $rng.GetBytes($bytes)
    $chars = for ($i = 0; $i -lt $Length; $i++) {
        $set = if ($i -lt $sets.Count) { $sets[$i] } else { $all }
        $set[$bytes[$i] % $set.Length]
    }
    -join ($chars | Sort-Object { Get-Random })
}

$rows = Import-Csv -Path $CsvPath -Delimiter ';' -Encoding UTF8
$required = 'Vorname', 'Nachname', 'Abteilung', 'Funktion'
$missing = $required | Where-Object { $_ -notin $rows[0].PSObject.Properties.Name }
if ($missing) { throw "CSV fehlt Spalte(n): $($missing -join ', ')" }

if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
$zugangsdaten = [Collections.Generic.List[object]]::new()
$ergebnis = [Collections.Generic.List[object]]::new()

foreach ($row in $rows) {
    $name = "$($row.Vorname) $($row.Nachname)"
    $ou = "OU=$($row.Abteilung),$benutzerOu"
    $gruppe = "GG_$($row.Abteilung)"

    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ou'" -ErrorAction SilentlyContinue)) {
        $ergebnis.Add([pscustomobject]@{ Name = $name; Benutzer = '-'; Status = "Fehler: Abteilung '$($row.Abteilung)' unbekannt" })
        continue
    }

    $sam = Get-FreeSamAccountName -Vorname $row.Vorname -Nachname $row.Nachname
    $upn = "$sam@$($domain.DNSRoot)"

    if ($PSCmdlet.ShouldProcess($name, "Benutzer $sam in $($row.Abteilung) anlegen")) {
        $passwort = New-StartPassword
        $params = @{
            Name                  = $name
            GivenName             = $row.Vorname
            Surname               = $row.Nachname
            DisplayName           = $name
            SamAccountName        = $sam
            UserPrincipalName     = $upn
            Path                  = $ou
            Department            = $row.Abteilung
            Title                 = $row.Funktion
            Company               = $Firma
            ScriptPath            = 'netzlaufwerke.cmd'
            AccountPassword       = (ConvertTo-SecureString $passwort -AsPlainText -Force)
            ChangePasswordAtLogon = $true
            Enabled               = $true
        }
        if ($row.PSObject.Properties.Name -contains 'Eintritt' -and $row.Eintritt) {
            $params.Description = "Eintritt $($row.Eintritt)"
        }
        New-ADUser @params
        Add-ADGroupMember -Identity $gruppe -Members $sam
        $zugangsdaten.Add([pscustomobject]@{ Name = $name; Benutzer = $sam; UPN = $upn; Startpasswort = $passwort })
        $ergebnis.Add([pscustomobject]@{ Name = $name; Benutzer = $sam; Status = "angelegt ($gruppe)" })
    }
    else {
        $ergebnis.Add([pscustomobject]@{ Name = $name; Benutzer = $sam; Status = 'WhatIf' })
    }
}

if ($zugangsdaten.Count) {
    $datei = Join-Path $OutputDir ("{0:yyyy-MM-dd_HHmm}-zugangsdaten.csv" -f (Get-Date))
    $zugangsdaten | Export-Csv -Path $datei -Delimiter ';' -NoTypeInformation -Encoding UTF8
    $acl = Get-Acl $datei
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($id in 'BUILTIN\Administrators', 'NT AUTHORITY\SYSTEM') {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($id, 'FullControl', 'Allow'))
    }
    Set-Acl -Path $datei -AclObject $acl
    Write-Host "Zugangsdaten gespeichert (nur Administratoren): $datei" -ForegroundColor Yellow
}

$ergebnis | Format-Table -AutoSize
