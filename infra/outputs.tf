output "environment" {
  description = "Active target environment."
  value       = var.environment
}

output "containers" {
  description = "Managed container IDs and names for each stack component."
  value = {
    cardano_node = {
      id   = module.cardano_node.container_id
      name = module.cardano_node.container_name
    }
    postgres = {
      id   = module.postgres.container_id
      name = module.postgres.container_name
    }
    cardano_db_sync = {
      id   = module.cardano_db_sync.container_id
      name = module.cardano_db_sync.container_name
    }
    midnight_node = {
      id   = module.midnight_node.container_id
      name = module.midnight_node.container_name
    }
    midnight_indexer = {
      id   = module.midnight_indexer.container_id
      name = module.midnight_indexer.container_name
    }
  }
}

output "networks" {
  description = "Managed Docker networks."
  value = {
    cardano_p2p      = docker_network.cardano_p2p.name
    db_internal      = docker_network.db_internal.name
    midnight_p2p     = docker_network.midnight_p2p.name
    indexer_internal = docker_network.indexer_internal.name
    indexer_api      = docker_network.indexer_api.name
  }
}

output "volumes" {
  description = "Managed persistent Docker volumes."
  value = {
    cardano_node_db       = module.cardano_node.db_volume_name
    cardano_ipc           = module.cardano_node.ipc_volume_name
    postgres_data         = module.postgres.data_volume_name
    cardano_db_sync_state = module.cardano_db_sync.state_volume_name
    midnight_node_data    = module.midnight_node.data_volume_name
    midnight_indexer_data = module.midnight_indexer.data_volume_name
  }
}

output "indexer_graphql_url" {
  description = "Local GraphQL API endpoint for Midnight Indexer."
  value       = module.midnight_indexer.graphql_url
}
