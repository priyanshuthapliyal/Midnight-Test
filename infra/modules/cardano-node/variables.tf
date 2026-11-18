variable "container_name" {
  description = "Name of the cardano-node Docker container."
  type        = string
}

variable "image" {
  description = "Docker image reference for cardano-node."
  type        = string
}

variable "network" {
  description = "Cardano network name (preview, preprod, mainnet)."
  type        = string

  validation {
    condition     = contains(["preview", "preprod", "mainnet"], var.network)
    error_message = "network must be one of: preview, preprod, mainnet."
  }
}

variable "p2p_port" {
  description = "Host port mapped to Cardano node P2P port 3001."
  type        = number
  default     = 3001
}

variable "config_path" {
  description = "Path to config.json inside the cardano-node container."
  type        = string
}

variable "topology_path" {
  description = "Path to topology.json inside the cardano-node container."
  type        = string
}

variable "db_volume_name" {
  description = "Docker volume name for Cardano node blockchain database."
  type        = string
}

variable "ipc_volume_name" {
  description = "Docker volume name for shared node.socket."
  type        = string
}

variable "p2p_network_id" {
  description = "Docker network ID for Cardano P2P communication."
  type        = string
}

variable "memory_limit_mb" {
  description = "Optional container memory limit in MB (0 = unlimited)."
  type        = number
  default     = 0
}
