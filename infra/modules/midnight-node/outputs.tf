output "container_id" {
  description = "ID of the midnight-node container."
  value       = docker_container.this.id
}

output "container_name" {
  description = "Name of the midnight-node container."
  value       = docker_container.this.name
}

output "data_volume_name" {
  description = "Persistent Docker volume name for Midnight blockchain data."
  value       = docker_volume.data.name
}

output "ws_url" {
  description = "Internal WebSocket RPC URL for the Midnight Indexer."
  value       = "ws://${docker_container.this.name}:9944"
}
