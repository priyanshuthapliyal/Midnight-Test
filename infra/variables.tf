variable "docker_host" {
  description = "Docker daemon socket or TCP endpoint."
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "environment" {
  description = "Target network environment (preview, preprod, mainnet)."
  type        = string

  validation {
    condition     = contains(["preview", "preprod", "mainnet"], var.environment)
    error_message = "environment must be one of: preview, preprod, mainnet."
  }
}

# -----------------------------------------------------------------------------
# Docker Image References
# -----------------------------------------------------------------------------
variable "cardano_node_image" {
  description = "Docker image reference for cardano-node."
  type        = string
  default     = "ghcr.io/intersectmbo/cardano-node:11.1.3-amd64"
}

variable "cardano_db_sync_image" {
  description = "Docker image reference for cardano-db-sync."
  type        = string
  default     = "ghcr.io/intersectmbo/cardano-db-sync:13.7.1.0"
}

variable "postgres_image" {
  description = "Docker image reference for PostgreSQL."
  type        = string
  default     = "postgres:17"
}

variable "midnight_node_image" {
  description = "Docker image reference for midnight-node."
  type        = string
  default     = "midnightntwrk/midnight-node:2.1.101-rc.2"
}

variable "midnight_indexer_image" {
  description = "Docker image reference for midnight-indexer."
  type        = string
  default     = "midnightntwrk/indexer-standalone:latest"
}

# -----------------------------------------------------------------------------
# Naming: Containers, Networks, Persistent Volumes
# -----------------------------------------------------------------------------
variable "container_names" {
  description = "Docker container names for each component."
  type = object({
    cardano_node     = string
    postgres         = string
    cardano_db_sync  = string
    midnight_node    = string
    midnight_indexer = string
  })
}

variable "network_names" {
  description = "Docker network names for traffic isolation."
  type = object({
    cardano_p2p      = string
    db_internal      = string
    midnight_p2p     = string
    indexer_internal = string
    indexer_api      = string
  })
}

variable "volume_names" {
  description = "Persistent Docker volume names for blockchain and database data."
  type = object({
    cardano_node_db       = string
    cardano_ipc           = string
    postgres_data         = string
    cardano_db_sync_state = string
    midnight_node_data    = string
    midnight_indexer_data = string
  })
}

# -----------------------------------------------------------------------------
# Resource Settings
# -----------------------------------------------------------------------------
variable "container_memory_limits_mb" {
  description = "Optional memory limits in MB per container (0 = unlimited)."
  type = object({
    cardano_node     = number
    postgres         = number
    cardano_db_sync  = number
    midnight_node    = number
    midnight_indexer = number
  })
  default = {
    cardano_node     = 0
    postgres         = 0
    cardano_db_sync  = 0
    midnight_node    = 0
    midnight_indexer = 0
  }
}

# -----------------------------------------------------------------------------
# Port Mappings
# -----------------------------------------------------------------------------
variable "cardano_p2p_port" {
  description = "Host port mapped to Cardano node P2P port 3001."
  type        = number
  default     = 3001
}

variable "midnight_p2p_port" {
  description = "Host port mapped to Midnight node P2P port 30333."
  type        = number
  default     = 30333
}

variable "indexer_api_port" {
  description = "Host port mapped to Midnight Indexer GraphQL API port 8088."
  type        = number
  default     = 8088
}

variable "indexer_api_bind_ip" {
  description = "Host IP address to bind the Midnight Indexer GraphQL API."
  type        = string
  default     = "127.0.0.1"
}

# -----------------------------------------------------------------------------
# Blockchain Network Configuration
# -----------------------------------------------------------------------------
variable "cardano_config_path" {
  description = "Path to config.json inside the cardano-node container."
  type        = string
}

variable "cardano_topology_path" {
  description = "Path to topology.json inside the cardano-node container."
  type        = string
}

variable "db_sync_config_path" {
  description = "Path to db-sync-config.json inside the cardano-db-sync container."
  type        = string
}

variable "db_sync_schema_dir" {
  description = "Path to cardano-db-sync SQL schema directory inside the container."
  type        = string
  default     = "/nix/store/schema"
}

variable "cardano_security_parameter" {
  description = "Cardano security parameter (432 for preview, 2160 for preprod/mainnet)."
  type        = number
}

variable "midnight_chain_spec_path" {
  description = "Path to chain-spec-raw.json inside the midnight-node container."
  type        = string
}

variable "midnight_node_name" {
  description = "Human-readable Midnight node name."
  type        = string
}

variable "midnight_bootnodes" {
  description = "List of Midnight bootnode multiaddrs."
  type        = list(string)
  default     = []
}

variable "midnight_pruning_mode" {
  description = "Midnight node storage pruning mode ('full' or 'archive')."
  type        = string
  default     = "full"

  validation {
    condition     = contains(["full", "archive"], var.midnight_pruning_mode)
    error_message = "midnight_pruning_mode must be 'full' or 'archive'."
  }
}

# -----------------------------------------------------------------------------
# Database Configuration & Secrets
# -----------------------------------------------------------------------------
variable "postgres_db" {
  description = "PostgreSQL database name."
  type        = string
  default     = "cexplorer"
}

variable "postgres_user" {
  description = "PostgreSQL superuser name."
  type        = string
  default     = "midnight"
}

variable "postgres_password" {
  description = "PostgreSQL password (inject via TF_VAR_postgres_password or gitignored terraform.tfvars)."
  type        = string
  sensitive   = true
}

variable "postgres_shared_buffers" {
  description = "PostgreSQL shared_buffers setting."
  type        = string
}

variable "postgres_maintenance_work_mem" {
  description = "PostgreSQL maintenance_work_mem setting."
  type        = string
}

variable "postgres_max_parallel_maintenance_workers" {
  description = "PostgreSQL max_parallel_maintenance_workers setting."
  type        = number
}

variable "postgres_effective_cache_size" {
  description = "PostgreSQL effective_cache_size setting."
  type        = string
}

variable "postgres_enable_tls" {
  description = "Enable PostgreSQL TLS (required by midnight-node 2.1.101)."
  type        = bool
  default     = true
}

variable "postgres_tls_host_dir" {
  description = "Host directory containing server.crt and server.key for PostgreSQL TLS."
  type        = string
  default     = ""
}

variable "indexer_secret" {
  description = "64-hex-char secret for midnight-indexer (inject via TF_VAR_indexer_secret)."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9a-fA-F]{64}$", var.indexer_secret))
    error_message = "indexer_secret must be a 64-character hex string (32 bytes)."
  }
}

variable "blockfrost_api_key" {
  description = "Blockfrost API key or non-empty placeholder when not using SPO stake data."
  type        = string
  sensitive   = true
  default     = "dummy-not-using-spo"
}
