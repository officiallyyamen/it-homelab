#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Verteilt das Anmeldeskript fuer Netzlaufwerke und traegt es bei allen Mitarbeitenden ein.
.DESCRIPTION
    Kopiert netzlaufwerke.cmd/.ps1 nach NETLOGON und setzt das AD-Attribut scriptPath
    fuer alle Konten unter OU=Benutzer. Beim Anmelden bekommt jede Person P: auf die
    Freigabe ihrer Abteilung auf LNX01.
#>
[CmdletBinding()]
param([string]$Firma = 'Firma')

$ErrorActionPreference = 'Stop'
$domain = Get-ADDomain
$quelle = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'netlogon'
$netlogon = "\\$($domain.DNSRoot)\NETLOGON"
Copy-Item -Path (Join-Path $quelle 'netzlaufwerke.*') -Destination $netlogon -Force

$ou = "OU=Benutzer,OU=$Firma,$($domain.DistinguishedName)"
$benutzer = Get-ADUser -SearchBase $ou -Filter * -Properties ScriptPath
foreach ($u in $benutzer) {
    if ($u.ScriptPath -ne 'netzlaufwerke.cmd') { Set-ADUser $u -ScriptPath 'netzlaufwerke.cmd' }
}
Write-Host "Anmeldeskript in $netlogon, eingetragen bei $($benutzer.Count) Konten" -ForegroundColor Green
Get-ChildItem $netlogon | Select-Object Name, Length | Format-Table -AutoSize
