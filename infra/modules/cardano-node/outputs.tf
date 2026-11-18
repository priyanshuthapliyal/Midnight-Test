output "container_id" {
  description = "ID of the cardano-node container."
  value       = docker_container.this.id
}

output "container_name" {
  description = "Name of the cardano-node container."
  value       = docker_container.this.name
}

output "db_volume_name" {
  description = "Persistent Docker volume name for Cardano blockchain data."
  value       = docker_volume.db.name
}

output "ipc_volume_name" {
  description = "Shared Docker volume name for node.socket."
  value       = docker_volume.ipc.name
}

output "socket_path" {
  description = "Container path to the Cardano node Unix socket."
  value       = "/ipc/node.socket"
}
