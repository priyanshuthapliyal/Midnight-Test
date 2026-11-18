variable "container_name" {
  description = "Name of the midnight-indexer Docker container."
  type        = string
}

variable "image" {
  description = "Docker image reference for midnight-indexer."
  type        = string
}

variable "network_id" {
  description = "Midnight network ID (preview, preprod, mainnet, undeployed)."
  type        = string
}

variable "node_ws_url" {
  description = "WebSocket URL of the Midnight node."
  type        = string
}

variable "indexer_secret" {
  description = "32-byte hex-encoded secret (64 hex characters)."
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

variable "api_port" {
  description = "Host port mapped to GraphQL API port 8088."
  type        = number
  default     = 8088
}

variable "api_bind_ip" {
  description = "Host IP address to bind the GraphQL API port."
  type        = string
  default     = "127.0.0.1"
}

variable "data_volume_name" {
  description = "Docker volume name for indexer SQLite data (/data)."
  type        = string
}

variable "indexer_network_id" {
  description = "Internal Docker network ID for Indexer to Midnight Node RPC."
  type        = string
}

variable "api_network_id" {
  description = "Bridge Docker network ID allowing host port publishing for the GraphQL API."
  type        = string
}

variable "memory_limit_mb" {
  description = "Optional container memory limit in MB (0 = unlimited)."
  type        = number
  default     = 0
}
