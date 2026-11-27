# Nimmt einen Windows-Client offline in die Domäne lab.local auf.
# Vorher auf DC01:  djoin /provision /domain lab.local /machine CL01 /savefile cl01.djoin
# Dann auf dem Client als lokaler Admin:  .\10-client-beitritt.ps1 -Datei C:\cl01.djoin
param([Parameter(Mandatory)][string]$Datei)

$adapter = Get-NetAdapter | Where-Object Status -eq Up | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses 10.10.10.10

djoin /requestodj /loadfile $Datei /windowspath $env:SystemRoot /localos
if ($LASTEXITCODE -ne 0) { throw "djoin fehlgeschlagen ($LASTEXITCODE)" }
Remove-Item $Datei -Force
"Beitritt vorbereitet, wird beim Neustart abgeschlossen"
Restart-Computer -Force
