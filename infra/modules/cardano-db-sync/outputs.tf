output "container_id" {
  description = "ID of the cardano-db-sync container."
  value       = docker_container.this.id
}

output "container_name" {
  description = "Name of the cardano-db-sync container."
  value       = docker_container.this.name
}

output "state_volume_name" {
  description = "Persistent Docker volume name for cardano-db-sync state."
  value       = docker_volume.state.name
}
