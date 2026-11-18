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

resource "docker_volume" "state" {
  name = var.state_volume_name
}

resource "docker_container" "this" {
  name          = var.container_name
  image         = docker_image.this.image_id
  restart       = "unless-stopped"
  memory        = var.memory_limit_mb > 0 ? var.memory_limit_mb : null
  security_opts = ["no-new-privileges:true"]

  env = [
    "NETWORK=${var.network}",
    "PGPASSFILE=/run/secrets/pgpass",
    "CARDANO_NODE_SOCKET_PATH=/ipc/node.socket",
  ]

  upload {
    file        = "/run/secrets/pgpass"
    content     = "${var.db_host}:5432:${var.db_name}:${var.db_user}:${var.db_password}\n"
    permissions = "0600"
  }

  # Reuses Section 1 cardano-db-sync flags; paths inside image are configurable via variables.
  command = [
    "--config", var.config_path,
    "--socket-path", "/ipc/node.socket",
    "--schema-dir", var.schema_dir,
    "--state-dir", "/var/lib/cardano-db-sync",
  ]

  volumes {
    volume_name    = var.ipc_volume_name
    container_path = "/ipc"
  }

  volumes {
    volume_name    = docker_volume.state.name
    container_path = "/var/lib/cardano-db-sync"
  }

  networks_advanced {
    name    = var.db_network_id
    aliases = [var.container_name]
  }

  healthcheck {
    test         = ["CMD-SHELL", "test -S /ipc/node.socket && pgrep -f cardano-db-sync >/dev/null"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 5
    start_period = "120s"
  }

  log_driver = "json-file"
  log_opts = {
    "max-size" = "50m"
    "max-file" = "5"
  }
}
