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

resource "docker_volume" "data" {
  name = var.data_volume_name
}

resource "docker_container" "this" {
  name          = var.container_name
  image         = docker_image.this.image_id
  restart       = "unless-stopped"
  memory        = var.memory_limit_mb > 0 ? var.memory_limit_mb : null
  security_opts = ["no-new-privileges:true"]

  env = [
    "CFG_PRESET=${var.cfg_preset}",
    "CARDANO_SECURITY_PARAMETER=${var.cardano_security_parameter}",
    "POSTGRES_HOST=${var.db_host}",
    "POSTGRES_DB=${var.db_name}",
    "POSTGRES_PORT=5432",
    "POSTGRES_USER=${var.db_user}",
    "POSTGRES_PASSWORD=${var.db_password}",
    "DB_SYNC_POSTGRES_CONNECTION_STRING=postgresql://${var.db_user}:${var.db_password}@${var.db_host}:5432/${var.db_name}?sslmode=${var.db_ssl_mode}",
    "NODE_NAME=${var.node_name}",
  ]

  command = concat(
    [
      "--chain", var.chain_spec_path,
      "--base-path", "/data",
      "--pool-limit", tostring(var.pool_limit),
      "--name", var.node_name,
      "--no-private-ip",
    ],
    flatten([for b in var.bootnodes : ["--bootnodes", b]]),
    var.pruning_mode == "archive" ? [
      "--state-pruning", "archive",
      "--blocks-pruning", "archive",
    ] : [],
    var.rpc_external_flags,
  )

  # Publish only P2P port; WebSocket RPC 9944 stays restricted to indexer_internal network.
  ports {
    internal = 30333
    external = var.p2p_port
    protocol = "tcp"
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/data"
  }

  networks_advanced {
    name = var.db_network_id
  }

  networks_advanced {
    name    = var.p2p_network_id
    aliases = [var.container_name]
  }

  networks_advanced {
    name    = var.indexer_network_id
    aliases = [var.container_name, "midnight-node"]
  }

  healthcheck {
    test         = ["CMD-SHELL", "curl -sf http://127.0.0.1:9944/health >/dev/null || exit 1"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 5
    start_period = "60s"
  }

  log_driver = "json-file"
  log_opts = {
    "max-size" = "50m"
    "max-file" = "5"
  }
}
