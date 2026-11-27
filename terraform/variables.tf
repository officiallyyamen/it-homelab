variable "docker_host" {
  description = "Docker-Daemon, auf dem das Monitoring läuft"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "gatus_version" {
  type    = string
  default = "v5.17.0"
}

variable "port" {
  description = "Port der Statusseite auf LNX01"
  type        = number
  default     = 8081
}

variable "dns_server" {
  description = "DC01, damit Namen wie dc01.lab.local aufgelöst werden"
  type        = string
  default     = "10.10.10.10"
}

variable "checks" {
  description = "Was geprüft wird: Name, Gruppe und Ziel (tcp://, icmp://, https:// oder dns)"
  type = list(object({
    name  = string
    group = string
    url   = string
  }))
  default = [
    { name = "DNS",                 group = "DC01",  url = "tcp://dc01.lab.local:53" },
    { name = "Kerberos",            group = "DC01",  url = "tcp://dc01.lab.local:88" },
    { name = "LDAPS",               group = "DC01",  url = "tcp://dc01.lab.local:636" },
    { name = "Dateifreigaben (SMB)", group = "LNX01", url = "tcp://lnx01.lab.local:445" },
    { name = "GLPI Helpdesk",       group = "LNX01", url = "http://lnx01.lab.local:8080/" },
  ]
}
