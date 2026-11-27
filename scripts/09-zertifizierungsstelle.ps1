# Richtet eine Unternehmens-Zertifizierungsstelle auf DC01 ein. Danach holt sich der DC automatisch
# ein Zertifikat und spricht LDAPS (Port 636). Andere Dienste (z. B. GLPI) vertrauen der Stamm-CA.
# Aufruf auf DC01: .\09-zertifizierungsstelle.ps1 -Export C:\IT\lab-root-ca.cer
param([string]$Export = 'C:\IT\lab-root-ca.cer')

if (-not (Get-WindowsFeature ADCS-Cert-Authority).Installed) {
    Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools | Out-Null
}
if (-not (Get-Service CertSvc -ErrorAction SilentlyContinue | Where-Object Status -eq Running)) {
    Install-AdcsCertificationAuthority -CAType EnterpriseRootCA -CACommonName 'LAB Root CA' `
        -KeyLength 4096 -HashAlgorithmName SHA256 -ValidityPeriod Years -ValidityPeriodUnits 10 -Force | Out-Null
}

certutil -pulse | Out-Null
$frist = (Get-Date).AddMinutes(3)
do {
    Start-Sleep 10
    $dcZert = Get-ChildItem Cert:\LocalMachine\My |
        Where-Object { $_.EnhancedKeyUsageList.FriendlyName -contains 'Server Authentication' -and $_.Issuer -like '*LAB Root CA*' }
} until ($dcZert -or (Get-Date) -gt $frist)

$ca = Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -like '*LAB Root CA*' | Select-Object -First 1
if (-not (Test-Path (Split-Path $Export))) { New-Item -ItemType Directory (Split-Path $Export) | Out-Null }
[IO.File]::WriteAllBytes((Join-Path $env:TEMP 'ca.der'), $ca.RawData)
certutil -f -encode (Join-Path $env:TEMP 'ca.der') $Export | Out-Null

if ($dcZert) { "DC-Zertifikat: $($dcZert[0].Subject), gültig bis $($dcZert[0].NotAfter.ToString('d'))" } else { 'DC-Zertifikat noch nicht ausgestellt' }
"Stamm-CA exportiert nach $Export"
