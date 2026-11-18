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
    "POSTGRES_DB=${var.db_name}",
    "POSTGRES_USER=${var.db_user}",
    "POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password",
  ]

  upload {
    file        = "/run/secrets/postgres_password"
    content     = var.db_password
    permissions = "0400"
  }

  # Tuning parameters from running-db-sync.md; TLS flags enabled for midnight-node 2.1.101
  command = concat(
    [
      "postgres",
      "-c", "shared_buffers=${var.shared_buffers}",
      "-c", "maintenance_work_mem=${var.maintenance_work_mem}",
      "-c", "max_parallel_maintenance_workers=${var.max_parallel_maintenance_workers}",
      "-c", "effective_cache_size=${var.effective_cache_size}",
    ],
    var.enable_tls && var.tls_host_dir != "" ? [
      "-c", "ssl=on",
      "-c", "ssl_cert_file=/etc/postgresql/certs/server.crt",
      "-c", "ssl_key_file=/etc/postgresql/certs/server.key",
    ] : []
  )

  dynamic "mounts" {
    for_each = var.enable_tls && var.tls_host_dir != "" ? [1] : []
    content {
      target    = "/etc/postgresql/certs"
      source    = var.tls_host_dir
      type      = "bind"
      read_only = true
    }
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/var/lib/postgresql/data"
  }

  networks_advanced {
    name    = var.db_network_id
    aliases = [var.container_name, "postgres"]
  }

  healthcheck {
    test         = ["CMD-SHELL", "pg_isready -U ${var.db_user} -d ${var.db_name}"]
    interval     = "15s"
    timeout      = "5s"
    retries      = 5
    start_period = "30s"
  }

  log_driver = "json-file"
  log_opts = {
    "max-size" = "50m"
    "max-file" = "5"
  }
}
