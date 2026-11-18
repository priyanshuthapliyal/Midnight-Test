terraform {
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
    "APP__APPLICATION__NETWORK_ID=${var.network_id}",
    "APP__INFRA__NODE__URL=${var.node_ws_url}",
    "APP__INFRA__SPO_NODE__URL=${var.node_ws_url}",
    "APP__INFRA__SPO_NODE__BLOCKFROST_ID=${var.blockfrost_api_key}",
    "APP__INFRA__SECRET_FILE=/run/secrets/app__infra__secret",
    "APP__INFRA__STORAGE__CNN_URL=/data/indexer.sqlite",
    "APP__INFRA__API__PORT=8088",
  ]

  upload {
    file        = "/run/secrets/app__infra__secret"
    content     = var.indexer_secret
    permissions = "0400"
  }

  ports {
    internal = 8088
    external = var.api_port
    ip       = var.api_bind_ip
    protocol = "tcp"
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/data"
  }

  networks_advanced {
    name    = var.indexer_network_id
    aliases = [var.container_name]
  }

  networks_advanced {
    name = var.api_network_id
  }

  healthcheck {
    test         = ["CMD-SHELL", "curl -sf http://127.0.0.1:8088/ready >/dev/null || exit 1"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 5
    start_period = "30s"
  }

  log_driver = "json-file"
  log_opts = {
    "max-size" = "50m"
    "max-file" = "5"
  }
}
