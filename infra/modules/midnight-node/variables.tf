variable "container_name" {
  description = "Name of the midnight-node Docker container."
  type        = string
}

variable "image" {
  description = "Docker image reference for midnight-node."
  type        = string
}

variable "cfg_preset" {
  description = "Midnight CFG_PRESET (preview, preprod, mainnet)."
  type        = string

  validation {
    condition     = contains(["preview", "preprod", "mainnet"], var.cfg_preset)
    error_message = "cfg_preset must be one of: preview, preprod, mainnet."
  }
}

variable "cardano_security_parameter" {
  description = "Cardano security parameter (432 for preview, 2160 for preprod/mainnet)."
  type        = number
}

variable "chain_spec_path" {
  description = "Path to chain-spec-raw.json inside the midnight-node container."
  type        = string
}

variable "node_name" {
  description = "Human-readable Midnight node name (--name)."
  type        = string
}

variable "pool_limit" {
  description = "Transaction pool limit."
  type        = number
  default     = 35
}

variable "bootnodes" {
  description = "List of Midnight bootnode multiaddrs."
  type        = list(string)
  default     = []
}

variable "pruning_mode" {
  description = "Node pruning mode: 'full' or 'archive'."
  type        = string
  default     = "full"

  validation {
    condition     = contains(["full", "archive"], var.pruning_mode)
    error_message = "pruning_mode must be 'full' or 'archive'."
  }
}

variable "p2p_port" {
  description = "Host port mapped to Midnight node P2P port 30333."
  type        = number
  default     = 30333
}

variable "db_host" {
  description = "PostgreSQL hostname on db_internal network."
  type        = string
}

variable "db_name" {
  description = "PostgreSQL database name."
  type        = string
  default     = "cexplorer"
}

variable "db_user" {
  description = "PostgreSQL username."
  type        = string
  default     = "midnight"
}

variable "db_password" {
  description = "PostgreSQL password."
  type        = string
  sensitive   = true
}

variable "db_ssl_mode" {
  description = "PostgreSQL SSL mode (midnight-node 2.1.101 requires TLS)."
  type        = string
  default     = "require"
}

variable "data_volume_name" {
  description = "Docker volume name for Midnight node base-path."
  type        = string
}

variable "db_network_id" {
  description = "Internal Docker network ID for PostgreSQL communication."
  type        = string
}

variable "p2p_network_id" {
  description = "Docker network ID for Midnight P2P communication."
  type        = string
}

variable "indexer_network_id" {
  description = "Internal Docker network ID for Midnight Indexer to Midnight Node RPC."
  type        = string
}

variable "memory_limit_mb" {
  description = "Optional container memory limit in MB (0 = unlimited)."
  type        = number
  default     = 0
}

variable "rpc_external_flags" {
  description = "Flags to bind Midnight node WebSocket RPC on 0.0.0.0:9944 for indexer_internal."
  type        = list(string)
  default     = ["--rpc-external"]
}
