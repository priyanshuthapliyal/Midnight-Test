environment = "preview"

# Docker Images
cardano_node_image     = "ghcr.io/intersectmbo/cardano-node:11.1.3-amd64"
cardano_db_sync_image  = "ghcr.io/intersectmbo/cardano-db-sync:13.7.1.0"
postgres_image         = "postgres:17"
midnight_node_image    = "midnightntwrk/midnight-node:2.1.101-rc.2"
midnight_indexer_image = "midnightntwrk/indexer-standalone:latest"

# Container Names
container_names = {
  cardano_node     = "preview-cardano-node"
  postgres         = "preview-postgres"
  cardano_db_sync  = "preview-cardano-db-sync"
  midnight_node    = "preview-midnight-node"
  midnight_indexer = "preview-midnight-indexer"
}

# Network Names
network_names = {
  cardano_p2p      = "preview-cardano-p2p"
  db_internal      = "preview-db-internal"
  midnight_p2p     = "preview-midnight-p2p"
  indexer_internal = "preview-indexer-internal"
  indexer_api      = "preview-indexer-api"
}

# Persistent Volume Names
volume_names = {
  cardano_node_db       = "preview_cardano_node_db"
  cardano_ipc           = "preview_cardano_ipc"
  postgres_data         = "preview_postgres_data"
  cardano_db_sync_state = "preview_cardano_db_sync_state"
  midnight_node_data    = "preview_midnight_node_data"
  midnight_indexer_data = "preview_midnight_indexer_data"
}

# Resource Limits (MB, 0 = unlimited)
container_memory_limits_mb = {
  cardano_node     = 8192
  postgres         = 8192
  cardano_db_sync  = 8192
  midnight_node    = 8192
  midnight_indexer = 2048
}

# Ports
cardano_p2p_port    = 3001
midnight_p2p_port   = 30333
indexer_api_port    = 8088
indexer_api_bind_ip = "127.0.0.1"

# Cardano Node & DB Sync (Preview)
cardano_config_path   = "/opt/cardano/cnode/files/config.json"
cardano_topology_path = "/opt/cardano/cnode/files/topology.json"
db_sync_config_path   = "/config/db-sync-config.json"

# PostgreSQL (Preview)
postgres_shared_buffers                   = "2GB"
postgres_maintenance_work_mem             = "1GB"
postgres_max_parallel_maintenance_workers = 2
postgres_effective_cache_size             = "6GB"
postgres_enable_tls                       = true

# Midnight Node (Preview: security parameter = 432)
cardano_security_parameter = 432
midnight_chain_spec_path   = "/res/preview/chain-spec-raw.json"
midnight_node_name         = "midnight-preview-node"
midnight_pruning_mode      = "full"
midnight_bootnodes = [
  "/dns/bootnode-1.preview.midnight.network/tcp/30333/ws/p2p/12D3KooWK66i7dtGVNSwDh9tTeqov1q6LSdWsRLJvTyzTCaywYgK",
  "/dns/bootnode-2.preview.midnight.network/tcp/30333/ws/p2p/12D3KooWHqFfXFwb7WW4jwR8pr4BEf562v5M6c8K3CXAJq4Wx6ym",
]
