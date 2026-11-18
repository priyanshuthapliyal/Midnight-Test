terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.9.0"
    }
  }
}

resource "docker_image" "this" {
  name         = var.image
  keep_locally = true
}

resource "docker_volume" "db" {
  name = var.db_volume_name
}

resource "docker_volume" "ipc" {
  name = var.ipc_volume_name
}

resource "docker_container" "this" {
  name          = var.container_name
  image         = docker_image.this.image_id
  restart       = "unless-stopped"
  memory        = var.memory_limit_mb > 0 ? var.memory_limit_mb : null
  security_opts = ["no-new-privileges:true"]

  env = [
    "NETWORK=${var.network}",
    "CARDANO_NODE_SOCKET_PATH=/ipc/node.socket",
  ]

  # Reuses Section 1 cardano-node run flags; paths inside image are configurable via variables.
  command = [
    "run",
    "--topology", var.topology_path,
    "--database-path", "/data/db",
    "--socket-path", "/ipc/node.socket",
    "--host-addr", "0.0.0.0",
    "--port", "3001",
    "--config", var.config_path,
  ]

  ports {
    internal = 3001
    external = var.p2p_port
    protocol = "tcp"
  }

  volumes {
    volume_name    = docker_volume.db.name
    container_path = "/data/db"
  }

  volumes {
    volume_name    = docker_volume.ipc.name
    container_path = "/ipc"
  }

  networks_advanced {
    name    = var.p2p_network_id
    aliases = [var.container_name]
  }

  healthcheck {
    test         = ["CMD-SHELL", "test -S /ipc/node.socket"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 10
    start_period = "120s"
  }

  log_driver = "json-file"
  log_opts = {
    "max-size" = "50m"
    "max-file" = "5"
  }
}
