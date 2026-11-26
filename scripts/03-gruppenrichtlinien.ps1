#Requires -Modules ActiveDirectory, GroupPolicy
<#
.SYNOPSIS
    Passwortrichtlinie der Domaene und Gruppenrichtlinien fuer Benutzer und Computer.
.DESCRIPTION
    - Domaenen-Passwortrichtlinie: 12 Zeichen, Komplexitaet, Sperre nach 5 Fehlversuchen
    - GPO "U - Arbeitsplatz": Firmen-Hintergrundbild, Bildschirmsperre nach 10 Minuten
    - GPO "C - Sicherheit": Windows-Firewall in allen Profilen an, Windows Update automatisch 03:00
    Idempotent: vorhandene GPOs werden aktualisiert, nicht doppelt angelegt.
#>
[CmdletBinding()]
param(
    [string]$Firma = 'Firma',
    [string]$Hintergrundbild
)

$ErrorActionPreference = 'Stop'
if (-not $Hintergrundbild) {
    $Hintergrundbild = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'assets\hintergrund.jpg'
}
$domain = Get-ADDomain
$firmaOu = "OU=$Firma,$($domain.DistinguishedName)"

Set-ADDefaultDomainPasswordPolicy -Identity $domain.DNSRoot `
    -MinPasswordLength 12 -ComplexityEnabled $true -PasswordHistoryCount 10 `
    -MaxPasswordAge (New-TimeSpan -Days 180) -MinPasswordAge (New-TimeSpan -Days 1) `
    -LockoutThreshold 5 -LockoutDuration (New-TimeSpan -Minutes 15) -LockoutObservationWindow (New-TimeSpan -Minutes 15)
Write-Host 'Passwortrichtlinie gesetzt' -ForegroundColor Green

function Get-OrCreateGpo {
    param([string]$Name, [string]$Kommentar, [string]$LinkOu)
    $gpo = Get-GPO -Name $Name -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $Name -Comment $Kommentar
        Write-Host "GPO angelegt: $Name" -ForegroundColor Green
    }
    $links = (Get-GPInheritance -Target $LinkOu).GpoLinks.DisplayName
    if ($Name -notin $links) {
        New-GPLink -Name $Name -Target $LinkOu -LinkEnabled Yes | Out-Null
        Write-Host "  verknuepft mit $LinkOu" -ForegroundColor Green
    }
    $gpo
}

$netlogon = "\\$($domain.DNSRoot)\NETLOGON"
$bildZiel = Join-Path $netlogon 'hintergrund.jpg'
Copy-Item -Path $Hintergrundbild -Destination $bildZiel -Force

$user = Get-OrCreateGpo -Name 'U - Arbeitsplatz' -Kommentar 'Hintergrundbild und Bildschirmsperre fuer alle Mitarbeitenden' -LinkOu "OU=Benutzer,$firmaOu"
$desktop = 'HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop'
$system  = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System'
Set-GPRegistryValue -Guid $user.Id -Key $system  -ValueName 'Wallpaper'           -Type String -Value $bildZiel | Out-Null
Set-GPRegistryValue -Guid $user.Id -Key $system  -ValueName 'WallpaperStyle'      -Type String -Value '10' | Out-Null
Set-GPRegistryValue -Guid $user.Id -Key $desktop -ValueName 'ScreenSaveActive'    -Type String -Value '1' | Out-Null
Set-GPRegistryValue -Guid $user.Id -Key $desktop -ValueName 'ScreenSaverIsSecure' -Type String -Value '1' | Out-Null
Set-GPRegistryValue -Guid $user.Id -Key $desktop -ValueName 'ScreenSaveTimeOut'   -Type String -Value '600' | Out-Null
Set-GPRegistryValue -Guid $user.Id -Key $desktop -ValueName 'SCRNSAVE.EXE'        -Type String -Value 'scrnsave.scr' | Out-Null

$comp = Get-OrCreateGpo -Name 'C - Sicherheit' -Kommentar 'Firewall und Windows Update fuer alle Arbeitsplaetze' -LinkOu "OU=Computer,$firmaOu"
foreach ($profil in 'DomainProfile', 'PrivateProfile', 'PublicProfile') {
    Set-GPRegistryValue -Guid $comp.Id -Key "HKLM\Software\Policies\Microsoft\WindowsFirewall\$profil" -ValueName 'EnableFirewall' -Type DWord -Value 1 | Out-Null
}
$wu = 'HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU'
Set-GPRegistryValue -Guid $comp.Id -Key $wu -ValueName 'NoAutoUpdate'         -Type DWord -Value 0 | Out-Null
Set-GPRegistryValue -Guid $comp.Id -Key $wu -ValueName 'AUOptions'            -Type DWord -Value 4 | Out-Null
Set-GPRegistryValue -Guid $comp.Id -Key $wu -ValueName 'ScheduledInstallDay'  -Type DWord -Value 0 | Out-Null
Set-GPRegistryValue -Guid $comp.Id -Key $wu -ValueName 'ScheduledInstallTime' -Type DWord -Value 3 | Out-Null

Get-ADDefaultDomainPasswordPolicy | Select-Object MinPasswordLength, ComplexityEnabled, LockoutThreshold, LockoutDuration | Format-List
Get-GPO -All | Where-Object DisplayName -like '? - *' | Select-Object DisplayName, GpoStatus, ModificationTime | Format-Table -AutoSize
