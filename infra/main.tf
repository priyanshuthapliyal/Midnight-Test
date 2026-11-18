# -----------------------------------------------------------------------------
# Docker Networks (Segmented by trust boundary)
# -----------------------------------------------------------------------------
resource "docker_network" "cardano_p2p" {
  name   = var.network_names.cardano_p2p
  driver = "bridge"
}

resource "docker_network" "db_internal" {
  name     = var.network_names.db_internal
  driver   = "bridge"
  internal = true
}

resource "docker_network" "midnight_p2p" {
  name   = var.network_names.midnight_p2p
  driver = "bridge"
}

resource "docker_network" "indexer_internal" {
  name     = var.network_names.indexer_internal
  driver   = "bridge"
  internal = true
}

resource "docker_network" "indexer_api" {
  name   = var.network_names.indexer_api
  driver = "bridge"
}

# -----------------------------------------------------------------------------
# Component Modules
# Dependency Sequence:
#   Cardano Node + PostgreSQL -> Cardano DB Sync -> Midnight Node -> Midnight Indexer
# -----------------------------------------------------------------------------
module "cardano_node" {
  source = "./modules/cardano-node"

  container_name  = var.container_names.cardano_node
  image           = var.cardano_node_image
  network         = var.environment
  p2p_port        = var.cardano_p2p_port
  config_path     = var.cardano_config_path
  topology_path   = var.cardano_topology_path
  db_volume_name  = var.volume_names.cardano_node_db
  ipc_volume_name = var.volume_names.cardano_ipc
  p2p_network_id  = docker_network.cardano_p2p.id
  memory_limit_mb = var.container_memory_limits_mb.cardano_node
}

module "postgres" {
  source = "./modules/postgres"

  container_name                   = var.container_names.postgres
  image                            = var.postgres_image
  db_name                          = var.postgres_db
  db_user                          = var.postgres_user
  db_password                      = var.postgres_password
  shared_buffers                   = var.postgres_shared_buffers
  maintenance_work_mem             = var.postgres_maintenance_work_mem
  max_parallel_maintenance_workers = var.postgres_max_parallel_maintenance_workers
  effective_cache_size             = var.postgres_effective_cache_size
  enable_tls                       = var.postgres_enable_tls
  tls_host_dir                     = var.postgres_tls_host_dir
  data_volume_name                 = var.volume_names.postgres_data
  db_network_id                    = docker_network.db_internal.id
  memory_limit_mb                  = var.container_memory_limits_mb.postgres
}

module "cardano_db_sync" {
  source = "./modules/cardano-db-sync"

  container_name    = var.container_names.cardano_db_sync
  image             = var.cardano_db_sync_image
  network           = var.environment
  config_path       = var.db_sync_config_path
  schema_dir        = var.db_sync_schema_dir
  db_host           = module.postgres.hostname
  db_name           = var.postgres_db
  db_user           = var.postgres_user
  db_password       = var.postgres_password
  ipc_volume_name   = module.cardano_node.ipc_volume_name
  state_volume_name = var.volume_names.cardano_db_sync_state
  db_network_id     = docker_network.db_internal.id
  memory_limit_mb   = var.container_memory_limits_mb.cardano_db_sync

  depends_on = [
    module.cardano_node,
    module.postgres,
  ]
}

module "midnight_node" {
  source = "./modules/midnight-node"

  container_name             = var.container_names.midnight_node
  image                      = var.midnight_node_image
  cfg_preset                 = var.environment
  cardano_security_parameter = var.cardano_security_parameter
  chain_spec_path            = var.midnight_chain_spec_path
  node_name                  = var.midnight_node_name
  bootnodes                  = var.midnight_bootnodes
  pruning_mode               = var.midnight_pruning_mode
  p2p_port                   = var.midnight_p2p_port
  db_host                    = module.postgres.hostname
  db_name                    = var.postgres_db
  db_user                    = var.postgres_user
  db_password                = var.postgres_password
  db_ssl_mode                = var.postgres_enable_tls ? "require" : "disable"
  data_volume_name           = var.volume_names.midnight_node_data
  db_network_id              = docker_network.db_internal.id
  p2p_network_id             = docker_network.midnight_p2p.id
  indexer_network_id         = docker_network.indexer_internal.id
  memory_limit_mb            = var.container_memory_limits_mb.midnight_node

  depends_on = [
    module.postgres,
    module.cardano_db_sync,
  ]
}

module "midnight_indexer" {
  source = "./modules/midnight-indexer"

  container_name     = var.container_names.midnight_indexer
  image              = var.midnight_indexer_image
  network_id         = var.environment
  node_ws_url        = module.midnight_node.ws_url
  indexer_secret     = var.indexer_secret
  blockfrost_api_key = var.blockfrost_api_key
  api_port           = var.indexer_api_port
  api_bind_ip        = var.indexer_api_bind_ip
  data_volume_name   = var.volume_names.midnight_indexer_data
  indexer_network_id = docker_network.indexer_internal.id
  api_network_id     = docker_network.indexer_api.id
  memory_limit_mb    = var.container_memory_limits_mb.midnight_indexer

  depends_on = [
    module.midnight_node,
  ]
}
