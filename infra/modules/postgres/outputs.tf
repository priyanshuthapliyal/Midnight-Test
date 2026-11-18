output "container_id" {
  description = "ID of the PostgreSQL container."
  value       = docker_container.this.id
}

output "container_name" {
  description = "Name of the PostgreSQL container."
  value       = docker_container.this.name
}

output "hostname" {
  description = "Internal DNS hostname of the PostgreSQL container on db_internal."
  value       = docker_container.this.name
}

output "data_volume_name" {
  description = "Persistent Docker volume name for PostgreSQL data."
  value       = docker_volume.data.name
}
