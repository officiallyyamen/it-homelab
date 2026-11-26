#Requires -RunAsAdministrator
<#
.SYNOPSIS
    DNS-Weiterleitung und DHCP fuer das Firmennetz auf DC01.
.DESCRIPTION
    - DNS: Anfragen fuer Internetnamen an 1.1.1.1 / 9.9.9.9 weiterleiten
    - DHCP: Bereich 10.10.10.100-200, Gateway, DNS und Domaenensuffix fuer neue Arbeitsplaetze
    - DHCP-Server im Active Directory autorisieren
    Idempotent.
#>
[CmdletBinding()]
param(
    [string]$Netz = '10.10.10.0',
    [string]$Start = '10.10.10.100',
    [string]$Ende = '10.10.10.200',
    [string]$Gateway = '10.10.10.1'
)

$ErrorActionPreference = 'Stop'
$domain = (Get-ADDomain).DNSRoot
$dcIp = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias Ethernet).IPAddress
$fqdn = "$env:COMPUTERNAME.$domain"

$vorhanden = (Get-DnsServerForwarder).IPAddress.IPAddressToString
foreach ($ip in '1.1.1.1', '9.9.9.9') {
    if ($ip -notin $vorhanden) { Add-DnsServerForwarder -IPAddress $ip }
}
Set-DnsClientServerAddress -InterfaceAlias Ethernet -ServerAddresses 127.0.0.1
Write-Host 'DNS-Weiterleitung gesetzt' -ForegroundColor Green

if (-not (Get-WindowsFeature DHCP).Installed) {
    Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
    Write-Host 'DHCP-Rolle installiert' -ForegroundColor Green
}
if (-not (Get-DhcpServerInDC | Where-Object DnsName -eq $fqdn)) {
    Add-DhcpServerInDC -DnsName $fqdn -IPAddress $dcIp
    Write-Host 'DHCP-Server im AD autorisiert' -ForegroundColor Green
}
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12' -Name ConfigurationState -Value 2 -ErrorAction SilentlyContinue

if (-not (Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object ScopeId -eq $Netz)) {
    Add-DhcpServerv4Scope -Name 'Arbeitsplaetze' -StartRange $Start -EndRange $Ende -SubnetMask 255.255.255.0 -LeaseDuration (New-TimeSpan -Days 8) -State Active
    Write-Host "DHCP-Bereich $Start - $Ende angelegt" -ForegroundColor Green
}
Set-DhcpServerv4OptionValue -ScopeId $Netz -Router $Gateway -DnsServer $dcIp -DnsDomain $domain
Restart-Service DHCPServer

Get-DnsServerForwarder | Select-Object IPAddress | Format-Table -AutoSize
Get-DhcpServerv4Scope | Select-Object Name, ScopeId, StartRange, EndRange, State | Format-Table -AutoSize
Get-DhcpServerv4OptionValue -ScopeId $Netz | Select-Object OptionId, Name, Value | Format-Table -AutoSize
Resolve-DnsName google.com -Type A | Select-Object -First 1 Name, IPAddress
