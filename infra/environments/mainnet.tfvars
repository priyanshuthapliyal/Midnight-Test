environment = "mainnet"

# Docker Images
cardano_node_image     = "ghcr.io/intersectmbo/cardano-node:11.1.3-amd64"
cardano_db_sync_image  = "ghcr.io/intersectmbo/cardano-db-sync:13.7.1.0"
postgres_image         = "postgres:17"
midnight_node_image    = "midnightntwrk/midnight-node:2.1.101-rc.2"
midnight_indexer_image = "midnightntwrk/indexer-standalone:latest"

# Container Names
container_names = {
  cardano_node     = "mainnet-cardano-node"
  postgres         = "mainnet-postgres"
  cardano_db_sync  = "mainnet-cardano-db-sync"
  midnight_node    = "mainnet-midnight-node"
  midnight_indexer = "mainnet-midnight-indexer"
}

# Network Names
network_names = {
  cardano_p2p      = "mainnet-cardano-p2p"
  db_internal      = "mainnet-db-internal"
  midnight_p2p     = "mainnet-midnight-p2p"
  indexer_internal = "mainnet-indexer-internal"
  indexer_api      = "mainnet-indexer-api"
}

# Persistent Volume Names
volume_names = {
  cardano_node_db       = "mainnet_cardano_node_db"
  cardano_ipc           = "mainnet_cardano_ipc"
  postgres_data         = "mainnet_postgres_data"
  cardano_db_sync_state = "mainnet_cardano_db_sync_state"
  midnight_node_data    = "mainnet_midnight_node_data"
  midnight_indexer_data = "mainnet_midnight_indexer_data"
}

# Resource Limits (MB, 0 = unlimited)
container_memory_limits_mb = {
  cardano_node     = 32768
  postgres         = 65536
  cardano_db_sync  = 32768
  midnight_node    = 16384
  midnight_indexer = 8192
}

# Ports
cardano_p2p_port    = 3001
midnight_p2p_port   = 30333
indexer_api_port    = 8088
indexer_api_bind_ip = "127.0.0.1"

# Cardano Node & DB Sync (Mainnet)
cardano_config_path   = "/opt/cardano/cnode/files/config.json"
cardano_topology_path = "/opt/cardano/cnode/files/topology.json"
db_sync_config_path   = "/config/db-sync-config.json"

# PostgreSQL (Mainnet tuning from running-db-sync.md)
postgres_shared_buffers                   = "16GB"
postgres_maintenance_work_mem             = "4GB"
postgres_max_parallel_maintenance_workers = 4
postgres_effective_cache_size             = "48GB"
postgres_enable_tls                       = true

# Midnight Node (Mainnet: security parameter = 2160)
cardano_security_parameter = 2160
midnight_chain_spec_path   = "/res/mainnet/chain-spec-raw.json"
midnight_node_name         = "midnight-mainnet-node"
midnight_pruning_mode      = "full"
midnight_bootnodes         = []
