variable "container_name" {
  description = "Name of the PostgreSQL Docker container."
  type        = string
}

variable "image" {
  description = "Docker image reference for PostgreSQL."
  type        = string
}

variable "db_name" {
  description = "PostgreSQL database name."
  type        = string
  default     = "cexplorer"
}

variable "db_user" {
  description = "PostgreSQL superuser name."
  type        = string
  default     = "midnight"
}

variable "db_password" {
  description = "PostgreSQL password for db_user."
  type        = string
  sensitive   = true
}

variable "shared_buffers" {
  description = "PostgreSQL shared_buffers setting."
  type        = string
}

variable "maintenance_work_mem" {
  description = "PostgreSQL maintenance_work_mem setting."
  type        = string
}

variable "max_parallel_maintenance_workers" {
  description = "PostgreSQL max_parallel_maintenance_workers setting."
  type        = number
}

variable "effective_cache_size" {
  description = "PostgreSQL effective_cache_size setting."
  type        = string
}

variable "enable_tls" {
  description = "Enable PostgreSQL TLS (required by midnight-node 2.1.101)."
  type        = bool
  default     = true
}

variable "tls_host_dir" {
  description = "Host directory containing server.crt and server.key for PostgreSQL TLS."
  type        = string
  default     = ""
}

variable "data_volume_name" {
  description = "Docker volume name for PostgreSQL data."
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
