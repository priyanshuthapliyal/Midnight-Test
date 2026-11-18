# Running a Midnight Validator Node (Preprod)

> **Setup Order — Step 4 of 4** | [← Step 3: WireGuard Overlay](./wireguard.md) · [Overview](./README.md)  
> **Document Scope:** Midnight Network — Federated Node Operator (FNO) Validator Launch (Preprod)  


This guide walks you through configuring environment variables, running an interactive test launch, and deploying `midnight-node` as a `systemd` service in **validator (block-producing) mode** on **Preprod**.

> [!NOTE]
> **New to Midnight? Here is how the pieces fit together:**
> - `midnight-node` is a Substrate-based blockchain node that reads Cardano state from your local **PostgreSQL (`cexplorer`)** database (populated by `cardano-db-sync`).
> - On **Preprod**, validators communicate over the **WireGuard trusted overlay** rather than the open internet, using `--reserved-only` and a fixed `--reserved-nodes` peer list.
> - Your node does **not** start producing blocks immediately after launch — it activates automatically after the **n+2 epoch transition** (explained in [4.2 Understand the n+2 Epoch Rule](#42-understand-the-n2-epoch-rule)).


## Prerequisites Checklist

Before starting, confirm all three setup guides are complete:

1. **Cardano Availability Layer:** Fully synced `cardano-node`, PostgreSQL `cexplorer` database, and `cardano-db-sync` ([running-cardano-node.md](./running-cardano-node.md)).
2. **Midnight Binary & Keys:** `midnight-node` installed, validator keys generated, and `partner-chains-public-keys.json` submitted to the Midnight Foundation ([Validator key genration.md](./Validator%20key%20genration.md)).
3. **WireGuard Overlay:** Joined the WireGuard trusted overlay (`wg0`) and verified active handshakes with peers ([wireguard.md](./wireguard.md)).


## Startup & Dependency Overview

```mermaid
flowchart LR
    PG[(PostgreSQL\ncexplorer)] -->|SQL Queries| MN["midnight-node\n(--validator)"]
    KEYS["Keys & Seeds\n(~/.env + secret_ed25519)"] --> MN
    MN <-->|"P2P Port 30333\n(--reserved-only)"| WG["WireGuard Overlay\n(wg0)"]
    MN -->|Metrics| TEL["Telemetry\n(telemetry.shielded.tools)"]
```

---

## 1. Prepare the Environment Configuration

> [!NOTE]
> This guide uses a `~/.env` file for demonstration. For production environments, use a dedicated secrets manager such as **HashiCorp Vault**, **AWS Secrets Manager**, or **Azure Key Vault**.

### 1.1 Verify Database Connection Variables

1. Retrieve your PostgreSQL password from `~/.pgpass`:

   ```bash
   export POSTGRES_PASSWORD=$(cut -d: -f5 ~/.pgpass)
   echo $POSTGRES_PASSWORD
   ```

2. Verify database connectivity:

   ```bash
   psql -h localhost -p 5432 -U midnight -d cexplorer -c "SELECT 'PostgreSQL Connection Verified' AS status;"
   ```

   If successful, the command returns a table showing `PostgreSQL Connection Verified`.

### 1.2 Create the `~/.env` File

Create `/home/midnight/.env` (`nano ~/.env`) with the following configuration, replacing `YOUR_POSTGRES_PASSWORD`, `YOUR_NODE_NAME`, and the key/seed file paths with your actual values:

```bash
# PostgreSQL connection
POSTGRES_HOST='localhost'
POSTGRES_DB='cexplorer'
POSTGRES_PORT=5432
POSTGRES_USER='midnight'
POSTGRES_PASSWORD='YOUR_POSTGRES_PASSWORD'
DB_SYNC_POSTGRES_CONNECTION_STRING=postgresql://midnight:YOUR_POSTGRES_PASSWORD@localhost:5432/cexplorer

# Cardano Preprod params
CARDANO_SECURITY_PARAMETER='432'
BLOCK_STABILITY_MARGIN=30

# Push to public telemetry
PROMETHEUS_PUSH_ENDPOINT='https://telemetry.shielded.tools/api/v1/receive'

# Midnight node settings
CFG_PRESET=preprod
NODE_NAME='YOUR_NODE_NAME'

# Absolute path to network and keystore files
NODE_KEY_FILE='/home/midnight/data/chains/midnight_preprod/network/secret_ed25519'
AURA_SEED_FILE='/home/midnight/keystore/61757261...'
GRANDPA_SEED_FILE='/home/midnight/keystore/6265656...'
CROSS_CHAIN_SEED_FILE='/home/midnight/keystore/6772616...'
```

Restrict permissions on `~/.env` because it contains your database password in plaintext:

```bash
chmod 600 ~/.env
```

> [!NOTE]
> **Separate Database Host:** The values above assume a single-host setup where PostgreSQL runs locally. If `cardano-db-sync` and PostgreSQL run on a separate host, set `POSTGRES_HOST` and `DB_SYNC_POSTGRES_CONNECTION_STRING` to that host's private IP instead of `localhost`.

---

## 2. Perform an Interactive Test Launch

Run `midnight-node` in the foreground once to verify database connectivity, peer connections, and chain sync before creating the `systemd` service.

### 2.1 Load Variables and Start the Node

1. Load the environment variables from `~/.env`:

   ```bash
   source ~/.env
   ```

2. Define the Preprod `--reserved-nodes` array from `configs/nodes/preprod/p2p-peers.md` in `midnight-network-ops` (dropping your own node's entry — you do not peer with yourself) and launch the node:

   ```bash
   # Populate from configs/nodes/preprod/p2p-peers.md in midnight-network-ops.
   # One line per peer; drop your own node's entry.
   RESERVED_NODES=(
     # --reserved-nodes /ip4/<overlay-ip>/tcp/30333/p2p/<peer-id>
   )

   midnight-node \
       --chain /home/midnight/res/preprod/chain-spec-raw.json \
       --base-path /home/midnight/data \
       --telemetry-url 'wss://telemetry.shielded.tools./submit 1' \
       --validator \
       --pool-limit 35 \
       --name ${NODE_NAME} \
       --rpc-port 9933 \
       --reserved-only \
       "${RESERVED_NODES[@]}"
   ```

### 2.2 Verify Node Output

Monitor the terminal output for the following indicators:

- **Postgres connection established:** Confirms database credentials and connectivity are working.
- **Peers:** Should be greater than `0`. If it remains at `0`, verify your WireGuard tunnel (`sudo wg show`) and check that port **30333/tcp** is open on your firewall.
- **Syncing:** The `Best: #...` block height should increment as the node pulls blocks from the network.

Once verified, press `Ctrl + C` to stop the interactive test before setting up `systemd`.

---

## 3. Deploy as a Systemd Service

1. Create `/etc/systemd/system/midnight-node.service`:

   ```bash
   sudo nano /etc/systemd/system/midnight-node.service
   ```

2. Paste the following configuration, appending one `--reserved-nodes` line per peer from `configs/nodes/preprod/p2p-peers.md` (excluding your own node). Ensure `ExecStart` points to your binary location (typically `/home/midnight/.local/bin/midnight-node`):

   ```ini
   [Unit]
   Description=Midnight Protocol Node (Preprod FNO)
   After=network.target postgresql.service
   Wants=postgresql.service

   [Service]
   User=midnight
   Group=midnight
   Type=simple
   WorkingDirectory=/home/midnight
   EnvironmentFile=/home/midnight/.env

   # systemd does not allow inline comments in ExecStart. Append one
   # --reserved-nodes line per peer from configs/nodes/preprod/p2p-peers.md,
   # dropping the entry matching your own node.
   ExecStart=/home/midnight/.local/bin/midnight-node \
       --chain /home/midnight/res/preprod/chain-spec-raw.json \
       --base-path /home/midnight/data \
       --telemetry-url 'wss://telemetry.shielded.tools./submit 1' \
       --validator \
       --pool-limit 35 \
       --name ${NODE_NAME} \
       --rpc-port 9933 \
       --reserved-only \
       --reserved-nodes ... \
       --reserved-nodes ...

   Restart=on-failure
   RestartSec=10
   LimitNOFILE=65535

   [Install]
   WantedBy=multi-user.target
   ```

3. Enable and start the service:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable midnight-node
   sudo systemctl start midnight-node
   ```

---

## 4. Verify Block Production

### 4.1 Check Session Keys

Tail the service logs:

```bash
journalctl -u midnight-node -f
```

Look for these log entries at node startup:

- `AURA pubkey: ...`
- `GRANDPA pubkey: ...`
- `CROSS_CHAIN pubkey: ...`

> [!WARNING]
> If these lines are missing, your node has no session keys loaded and **cannot participate in block validation**. Double-check your keystore (`~/data/chains/midnight_preprod/keystore`) and seed file paths in `~/.env`.

### 4.2 Understand the `n+2` Epoch Rule

Validator nodes do not produce blocks immediately upon launch. Midnight follows an **`n+2` epoch transition cycle**:

1. **Epoch `n`:** Your public keys are added to the validator whitelist. Your node remains passive.
2. **Epoch `n+1`:** Your node is queued for the next session. Still passive.
3. **Epoch `n+2`:** Your node joins the active validator set and begins block production.

### 4.3 Confirm Block Authoring

Once your node enters the active set, you will see log lines similar to:

```text
✨ Imported #12345 (0xabc1…def2)

🏆 Prepared block for proposing at #12346

🔖 Pre-sealed block for proposal at #12346

✨ Successfully proposed block #12346 (0xdef3…ghi4)
```

Seeing **`Successfully proposed block`** confirms your node is actively contributing to Preprod network consensus.

---

## Quick Operations Reference

```bash
# Check service status
sudo systemctl status midnight-node

# Stream live logs
journalctl -u midnight-node -f --no-pager -n 100

# Restart after editing ~/.env or the service file
sudo systemctl daemon-reload && sudo systemctl restart midnight-node
```

---

**Navigation:** [← Step 3: WireGuard Overlay](./wireguard.md) · [Overview](./README.md)
