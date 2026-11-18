environment = "preprod"

# Docker Images
cardano_node_image     = "ghcr.io/intersectmbo/cardano-node:11.1.3-amd64"
cardano_db_sync_image  = "ghcr.io/intersectmbo/cardano-db-sync:13.7.1.0"
postgres_image         = "postgres:17"
midnight_node_image    = "midnightntwrk/midnight-node:2.1.101-rc.2"
midnight_indexer_image = "midnightntwrk/indexer-standalone:latest"

# Container Names
container_names = {
  cardano_node     = "preprod-cardano-node"
  postgres         = "preprod-postgres"
  cardano_db_sync  = "preprod-cardano-db-sync"
  midnight_node    = "preprod-midnight-node"
  midnight_indexer = "preprod-midnight-indexer"
}

# Network Names
network_names = {
  cardano_p2p      = "preprod-cardano-p2p"
  db_internal      = "preprod-db-internal"
  midnight_p2p     = "preprod-midnight-p2p"
  indexer_internal = "preprod-indexer-internal"
  indexer_api      = "preprod-indexer-api"
}

# Persistent Volume Names
volume_names = {
  cardano_node_db       = "preprod_cardano_node_db"
  cardano_ipc           = "preprod_cardano_ipc"
  postgres_data         = "preprod_postgres_data"
  cardano_db_sync_state = "preprod_cardano_db_sync_state"
  midnight_node_data    = "preprod_midnight_node_data"
  midnight_indexer_data = "preprod_midnight_indexer_data"
}

# Resource Limits (MB, 0 = unlimited)
container_memory_limits_mb = {
  cardano_node     = 16384
  postgres         = 16384
  cardano_db_sync  = 16384
  midnight_node    = 8192
  midnight_indexer = 4096
}

# Ports
cardano_p2p_port    = 3001
midnight_p2p_port   = 30333
indexer_api_port    = 8088
indexer_api_bind_ip = "127.0.0.1"

# Cardano Node & DB Sync (Preprod)
cardano_config_path   = "/opt/cardano/cnode/files/config.json"
cardano_topology_path = "/opt/cardano/cnode/files/topology.json"
db_sync_config_path   = "/config/db-sync-config.json"

# PostgreSQL (Preprod)
postgres_shared_buffers                   = "4GB"
postgres_maintenance_work_mem             = "2GB"
postgres_max_parallel_maintenance_workers = 2
postgres_effective_cache_size             = "12GB"
postgres_enable_tls                       = true

# Midnight Node (Preprod: security parameter = 2160)
cardano_security_parameter = 2160
midnight_chain_spec_path   = "/res/preprod/chain-spec-raw.json"
midnight_node_name         = "midnight-preprod-node"
midnight_pruning_mode      = "full"
midnight_bootnodes         = []
