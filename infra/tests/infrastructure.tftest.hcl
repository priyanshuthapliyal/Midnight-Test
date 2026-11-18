# Terraform native tests for Cardano & Midnight Docker infrastructure.
# Uses mock_provider "docker" so plan/apply assertions run deterministically
# without requiring a live Docker daemon or pulling multi-GB images.

mock_provider "docker" {}

variables {
  postgres_password  = "test-only-dummy-password-not-real"
  indexer_secret     = "0000000000000000000000000000000000000000000000000000000000000000"
  blockfrost_api_key = "dummy-not-using-spo"
}

# -----------------------------------------------------------------------------
# 1. PostgreSQL Module Security & Storage Assertions
# -----------------------------------------------------------------------------
run "postgres_module_security_and_storage" {
  command = plan

  module {
    source = "./modules/postgres"
  }

  variables {
    container_name                   = "preview-postgres"
    image                            = "postgres:17"
    db_password                      = "test-only-dummy-password-not-real"
    shared_buffers                   = "2GB"
    maintenance_work_mem             = "1GB"
    max_parallel_maintenance_workers = 2
    effective_cache_size             = "6GB"
    data_volume_name                 = "preview_postgres_data"
    db_network_id                    = "preview-db-internal"
  }

  assert {
    condition     = length(docker_container.this.ports) == 0
    error_message = "PostgreSQL must not publish any ports (including 5432) to the host."
  }

  assert {
    condition     = length(docker_container.this.networks_advanced) == 1 && one(docker_container.this.networks_advanced).name == "preview-db-internal"
    error_message = "PostgreSQL must be attached only to the private db_internal network."
  }

  assert {
    condition     = docker_volume.data.name == "preview_postgres_data"
    error_message = "PostgreSQL must define persistent volume preview_postgres_data."
  }

  assert {
    condition     = contains(docker_container.this.security_opts, "no-new-privileges:true")
    error_message = "PostgreSQL container must enforce no-new-privileges:true."
  }
}

# -----------------------------------------------------------------------------
# 2. Midnight Node Module RPC Isolation & Storage Assertions
# -----------------------------------------------------------------------------
run "midnight_node_module_rpc_and_storage" {
  command = plan

  module {
    source = "./modules/midnight-node"
  }

  variables {
    container_name             = "preview-midnight-node"
    image                      = "midnightntwrk/midnight-node:2.1.101-rc.2"
    cfg_preset                 = "preview"
    cardano_security_parameter = 432
    chain_spec_path            = "/res/preview/chain-spec-raw.json"
    node_name                  = "midnight-preview-node"
    db_host                    = "preview-postgres"
    db_password                = "test-only-dummy-password-not-real"
    data_volume_name           = "preview_midnight_node_data"
    db_network_id              = "preview-db-internal"
    p2p_network_id             = "preview-midnight-p2p"
    indexer_network_id         = "preview-indexer-internal"
  }

  assert {
    condition     = length(docker_container.this.ports) == 1 && one(docker_container.this.ports).internal == 30333
    error_message = "Midnight Node must publish only P2P port 30333 and keep RPC 9944 private."
  }

  assert {
    condition     = docker_volume.data.name == "preview_midnight_node_data"
    error_message = "Midnight Node must define persistent chain-data volume preview_midnight_node_data."
  }
}

# -----------------------------------------------------------------------------
# 3. Preview Root Stack: Networks, Volumes, Components & Output Security
# -----------------------------------------------------------------------------
run "preview_root_stack" {
  command = apply

  variables {
    environment = "preview"
    container_names = {
      cardano_node     = "preview-cardano-node"
      postgres         = "preview-postgres"
      cardano_db_sync  = "preview-cardano-db-sync"
      midnight_node    = "preview-midnight-node"
      midnight_indexer = "preview-midnight-indexer"
    }
    network_names = {
      cardano_p2p      = "preview-cardano-p2p"
      db_internal      = "preview-db-internal"
      midnight_p2p     = "preview-midnight-p2p"
      indexer_internal = "preview-indexer-internal"
      indexer_api      = "preview-indexer-api"
    }
    volume_names = {
      cardano_node_db       = "preview_cardano_node_db"
      cardano_ipc           = "preview_cardano_ipc"
      postgres_data         = "preview_postgres_data"
      cardano_db_sync_state = "preview_cardano_db_sync_state"
      midnight_node_data    = "preview_midnight_node_data"
      midnight_indexer_data = "preview_midnight_indexer_data"
    }
    cardano_config_path                       = "/opt/cardano/cnode/files/config.json"
    cardano_topology_path                     = "/opt/cardano/cnode/files/topology.json"
    db_sync_config_path                       = "/config/db-sync-config.json"
    postgres_shared_buffers                   = "2GB"
    postgres_maintenance_work_mem             = "1GB"
    postgres_max_parallel_maintenance_workers = 2
    postgres_effective_cache_size             = "6GB"
    cardano_security_parameter                = 432
    midnight_chain_spec_path                  = "/res/preview/chain-spec-raw.json"
    midnight_node_name                        = "midnight-preview-node"
    midnight_bootnodes = [
      "/dns/bootnode-1.preview.midnight.network/tcp/30333/ws/p2p/12D3KooWK66i7dtGVNSwDh9tTeqov1q6LSdWsRLJvTyzTCaywYgK",
    ]
  }

  assert {
    condition     = docker_network.db_internal.internal == true && docker_network.indexer_internal.internal == true
    error_message = "db_internal and indexer_internal networks must have internal = true."
  }

  assert {
    condition     = output.volumes.cardano_node_db == "preview_cardano_node_db" && output.volumes.postgres_data == "preview_postgres_data" && output.volumes.midnight_node_data == "preview_midnight_node_data" && output.volumes.midnight_indexer_data == "preview_midnight_indexer_data"
    error_message = "All required persistent volumes must be defined for preview."
  }

  assert {
    condition     = output.containers.cardano_node.name == "preview-cardano-node" && output.containers.postgres.name == "preview-postgres" && output.containers.cardano_db_sync.name == "preview-cardano-db-sync" && output.containers.midnight_node.name == "preview-midnight-node" && output.containers.midnight_indexer.name == "preview-midnight-indexer"
    error_message = "All five required containers must be represented."
  }

  assert {
    condition     = !strcontains(jsonencode(output.containers), "test-only-dummy-password-not-real") && !strcontains(jsonencode(output.indexer_graphql_url), "0000000000000000000000000000000000000000000000000000000000000000")
    error_message = "Outputs must never expose sensitive credentials."
  }
}

# -----------------------------------------------------------------------------
# 4. PreProd Environment Isolation
# -----------------------------------------------------------------------------
run "preprod_environment_isolation" {
  command = plan

  variables {
    environment = "preprod"
    container_names = {
      cardano_node     = "preprod-cardano-node"
      postgres         = "preprod-postgres"
      cardano_db_sync  = "preprod-cardano-db-sync"
      midnight_node    = "preprod-midnight-node"
      midnight_indexer = "preprod-midnight-indexer"
    }
    network_names = {
      cardano_p2p      = "preprod-cardano-p2p"
      db_internal      = "preprod-db-internal"
      midnight_p2p     = "preprod-midnight-p2p"
      indexer_internal = "preprod-indexer-internal"
      indexer_api      = "preprod-indexer-api"
    }
    volume_names = {
      cardano_node_db       = "preprod_cardano_node_db"
      cardano_ipc           = "preprod_cardano_ipc"
      postgres_data         = "preprod_postgres_data"
      cardano_db_sync_state = "preprod_cardano_db_sync_state"
      midnight_node_data    = "preprod_midnight_node_data"
      midnight_indexer_data = "preprod_midnight_indexer_data"
    }
    cardano_config_path                       = "/opt/cardano/cnode/files/config.json"
    cardano_topology_path                     = "/opt/cardano/cnode/files/topology.json"
    db_sync_config_path                       = "/config/db-sync-config.json"
    postgres_shared_buffers                   = "4GB"
    postgres_maintenance_work_mem             = "2GB"
    postgres_max_parallel_maintenance_workers = 2
    postgres_effective_cache_size             = "12GB"
    cardano_security_parameter                = 2160
    midnight_chain_spec_path                  = "/res/preprod/chain-spec-raw.json"
    midnight_node_name                        = "midnight-preprod-node"
  }

  assert {
    condition     = output.environment == "preprod" && output.volumes.postgres_data == "preprod_postgres_data" && docker_network.db_internal.name == "preprod-db-internal"
    error_message = "PreProd must use isolated container, network, and volume names."
  }
}

# -----------------------------------------------------------------------------
# 5. Mainnet Environment Isolation
# -----------------------------------------------------------------------------
run "mainnet_environment_isolation" {
  command = plan

  variables {
    environment = "mainnet"
    container_names = {
      cardano_node     = "mainnet-cardano-node"
      postgres         = "mainnet-postgres"
      cardano_db_sync  = "mainnet-cardano-db-sync"
      midnight_node    = "mainnet-midnight-node"
      midnight_indexer = "mainnet-midnight-indexer"
    }
    network_names = {
      cardano_p2p      = "mainnet-cardano-p2p"
      db_internal      = "mainnet-db-internal"
      midnight_p2p     = "mainnet-midnight-p2p"
      indexer_internal = "mainnet-indexer-internal"
      indexer_api      = "mainnet-indexer-api"
    }
    volume_names = {
      cardano_node_db       = "mainnet_cardano_node_db"
      cardano_ipc           = "mainnet_cardano_ipc"
      postgres_data         = "mainnet_postgres_data"
      cardano_db_sync_state = "mainnet_cardano_db_sync_state"
      midnight_node_data    = "mainnet_midnight_node_data"
      midnight_indexer_data = "mainnet_midnight_indexer_data"
    }
    cardano_config_path                       = "/opt/cardano/cnode/files/config.json"
    cardano_topology_path                     = "/opt/cardano/cnode/files/topology.json"
    db_sync_config_path                       = "/config/db-sync-config.json"
    postgres_shared_buffers                   = "16GB"
    postgres_maintenance_work_mem             = "4GB"
    postgres_max_parallel_maintenance_workers = 4
    postgres_effective_cache_size             = "48GB"
    cardano_security_parameter                = 2160
    midnight_chain_spec_path                  = "/res/mainnet/chain-spec-raw.json"
    midnight_node_name                        = "midnight-mainnet-node"
  }

  assert {
    condition     = output.environment == "mainnet" && output.volumes.cardano_node_db == "mainnet_cardano_node_db" && docker_network.db_internal.name == "mainnet-db-internal"
    error_message = "Mainnet must use isolated container, network, and volume names."
  }
}

# -----------------------------------------------------------------------------
# 6. Input Validation: Reject Invalid Secrets
# -----------------------------------------------------------------------------
run "reject_invalid_indexer_secret" {
  command = plan

  variables {
    environment    = "preview"
    indexer_secret = "not-a-64-hex-char-secret"
    container_names = {
      cardano_node     = "preview-cardano-node"
      postgres         = "preview-postgres"
      cardano_db_sync  = "preview-cardano-db-sync"
      midnight_node    = "preview-midnight-node"
      midnight_indexer = "preview-midnight-indexer"
    }
    network_names = {
      cardano_p2p      = "preview-cardano-p2p"
      db_internal      = "preview-db-internal"
      midnight_p2p     = "preview-midnight-p2p"
      indexer_internal = "preview-indexer-internal"
      indexer_api      = "preview-indexer-api"
    }
    volume_names = {
      cardano_node_db       = "preview_cardano_node_db"
      cardano_ipc           = "preview_cardano_ipc"
      postgres_data         = "preview_postgres_data"
      cardano_db_sync_state = "preview_cardano_db_sync_state"
      midnight_node_data    = "preview_midnight_node_data"
      midnight_indexer_data = "preview_midnight_indexer_data"
    }
    cardano_config_path                       = "/opt/cardano/cnode/files/config.json"
    cardano_topology_path                     = "/opt/cardano/cnode/files/topology.json"
    db_sync_config_path                       = "/config/db-sync-config.json"
    postgres_shared_buffers                   = "2GB"
    postgres_maintenance_work_mem             = "1GB"
    postgres_max_parallel_maintenance_workers = 2
    postgres_effective_cache_size             = "6GB"
    cardano_security_parameter                = 432
    midnight_chain_spec_path                  = "/res/preview/chain-spec-raw.json"
    midnight_node_name                        = "midnight-preview-node"
  }

  expect_failures = [
    var.indexer_secret,
  ]
}
