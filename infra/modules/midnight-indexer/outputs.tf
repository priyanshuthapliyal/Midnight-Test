output "container_id" {
  description = "ID of the midnight-indexer container."
  value       = docker_container.this.id
}

output "container_name" {
  description = "Name of the midnight-indexer container."
  value       = docker_container.this.name
}

output "data_volume_name" {
  description = "Persistent Docker volume name for indexer SQLite data."
  value       = docker_volume.data.name
}

output "graphql_url" {
  description = "Local GraphQL API endpoint."
  value       = "http://${var.api_bind_ip}:${var.api_port}/api/v4/graphql"
}
