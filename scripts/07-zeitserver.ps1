# Macht DC01 zur Zeitquelle der Domäne (Kerberos erlaubt höchstens 5 Minuten Abweichung)
# Aufruf auf DC01 als Domänen-Admin: .\07-zeitserver.ps1

w32tm /config /manualpeerlist:"0.at.pool.ntp.org,0x8 time.windows.com,0x8" /syncfromflags:manual /reliable:yes /update
Restart-Service w32time
w32tm /resync /force

Get-NetFirewallRule -DisplayGroup "Active Directory Domain Services" |
    Where-Object DisplayName -like "*NTP*" |
    Enable-NetFirewallRule

Start-Sleep 5
w32tm /query /status | Select-String "Source|Last Successful"
