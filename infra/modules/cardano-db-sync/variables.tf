variable "container_name" {
  description = "Name of the cardano-db-sync Docker container."
  type        = string
}

variable "image" {
  description = "Docker image reference for cardano-db-sync."
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

variable "config_path" {
  description = "Path to db-sync-config.json inside the container."
  type        = string
}

variable "schema_dir" {
  description = "Path to cardano-db-sync SQL schema directory inside the container."
  type        = string
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

variable "ipc_volume_name" {
  description = "Docker volume name for shared node.socket."
  type        = string
}

variable "state_volume_name" {
  description = "Docker volume name for cardano-db-sync state."
  type        = string
}

variable "db_network_id" {
  description = "Internal Docker network ID for database communication."
  type        = string
}

variable "memory_limit_mb" {
  description = "Optional container memory limit in MB (0 = unlimited)."
  type        = number
  default     = 0
}
