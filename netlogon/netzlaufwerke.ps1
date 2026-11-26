# Anmeldeskript: verbindet P: mit der Freigabe der eigenen Abteilung auf LNX01
$server = 'lnx01.lab.local'
$abteilungen = 'Geschaeftsfuehrung', 'IT', 'Vertrieb', 'Buchhaltung', 'Technik'
$gruppen = [Security.Principal.WindowsIdentity]::GetCurrent().Groups |
    ForEach-Object { try { $_.Translate([Security.Principal.NTAccount]).Value } catch { } }

foreach ($abt in $abteilungen) {
    if ($gruppen -contains "LAB\GG_$abt") {
        $ziel = "\\$server\$abt"
        if (Get-PSDrive -Name P -ErrorAction SilentlyContinue) { net use P: /delete /y | Out-Null }
        net use P: $ziel /persistent:no | Out-Null
        (New-Object -ComObject Shell.Application).NameSpace('P:\').Self.Name = "Abteilung $abt"
        break
    }
}
