# Installiert den GLPI-Agent als Dienst. Er meldet Hardware und Software stündlich an GLPI.
# Aufruf auf dem Client als Admin:  .\11-glpi-agent.ps1 -Msi .\GLPI-Agent-1.21-x64.msi
param(
    [Parameter(Mandatory)][string]$Msi,
    [string]$Server = 'http://lnx01.lab.local:8080/'
)

$argumente = @('/i', (Resolve-Path $Msi), '/quiet', '/norestart',
    "SERVER=$Server", 'EXECMODE=1', 'RUNNOW=1', 'ADD_FIREWALL_EXCEPTION=1', 'TAG=Arbeitsplatz')
$p = Start-Process msiexec.exe -ArgumentList $argumente -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "Installation fehlgeschlagen ($($p.ExitCode))" }
Get-Service glpi-agent | Select-Object Name, Status
