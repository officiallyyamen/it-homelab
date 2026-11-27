# Monitoring für das Lab: Gatus prüft im Minutentakt, ob die Dienste der Firma erreichbar sind.
# Läuft auf LNX01 im Docker. Aufruf auf LNX01:  terraform init && terraform apply

terraform {
  required_version = ">= 1.6"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.6"
    }
  }
}

provider "docker" {
  host = var.docker_host
}

resource "docker_image" "gatus" {
  name         = "twinproduction/gatus:${var.gatus_version}"
  keep_locally = true
}

resource "docker_container" "gatus" {
  name    = "monitoring"
  image   = docker_image.gatus.image_id
  restart = "unless-stopped"

  ports {
    internal = 8080
    external = var.port
  }

  upload {
    file    = "/config/config.yaml"
    content = templatefile("${path.module}/gatus.yaml.tftpl", { checks = var.checks })
  }

  dns        = [var.dns_server]
  dns_search = ["lab.local"]
}
