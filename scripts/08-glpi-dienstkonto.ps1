# Legt das Dienstkonto an, mit dem GLPI Benutzer aus dem AD liest (nur Leserechte, kein Admin)
# Aufruf auf DC01: .\08-glpi-dienstkonto.ps1 -Ausgabe C:\IT\glpi-dienstkonto.txt
param([string]$Ausgabe = 'C:\IT\glpi-dienstkonto.txt')

Import-Module ActiveDirectory
$basis = (Get-ADDomain).DistinguishedName
$ou = "OU=Dienstkonten,OU=Firma,$basis"
if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ou'")) {
    New-ADOrganizationalUnit -Name Dienstkonten -Path "OU=Firma,$basis" -ProtectedFromAccidentalDeletion $true
}

$zeichen = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
$bytes = New-Object byte[] 24
(New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
$passwort = 'Gl!' + (-join ($bytes | ForEach-Object { $zeichen[$_ % $zeichen.Length] }))
$sicher = ConvertTo-SecureString $passwort -AsPlainText -Force

if (Get-ADUser -Filter "SamAccountName -eq 'svc-glpi'") {
    Set-ADAccountPassword svc-glpi -Reset -NewPassword $sicher
} else {
    New-ADUser -Name 'svc-glpi' -SamAccountName 'svc-glpi' -UserPrincipalName 'svc-glpi@lab.local' `
        -Path $ou -AccountPassword $sicher -Enabled $true -PasswordNeverExpires $true `
        -CannotChangePassword $true -Description 'GLPI: liest Benutzer aus dem AD'
}

if (-not (Test-Path (Split-Path $Ausgabe))) { New-Item -ItemType Directory (Split-Path $Ausgabe) | Out-Null }
[IO.File]::WriteAllText($Ausgabe, $passwort)
"svc-glpi bereit, Passwort liegt in $Ausgabe"
