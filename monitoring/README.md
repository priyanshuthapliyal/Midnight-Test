# Midnight Preprod Node — Monitoring & Alerting Guide

This directory contains the observability stack configuration for a **Midnight Preprod Substrate validator/node**, covering Prometheus scraping, alert rules, Alertmanager routing, and a 14-panel Grafana dashboard.

---

## Files in This Directory

| File | Purpose |
| :--- | :--- |
| **[prometheus.yml](./prometheus.yml)** | Scrapes `midnight-node` (`127.0.0.1:9615`) and `node-exporter` (`127.0.0.1:9100`) every `15s`, evaluates `alerts.yml`, and forwards firing alerts to Alertmanager (`127.0.0.1:9093`). |
| **[alerts.yml](./alerts.yml)** | Defines the 5 Prometheus alert rules under the `midnight-node-alerts` group. |
| **[alertmanager.yml](./alertmanager.yml)** | Routes alerts to a Slack-compatible webhook (`group_wait: 30s`, `group_interval: 5m`, `repeat_interval: 4h`, `send_resolved: true`). |
| **[Midnight Preprod Node — Full Observability.json](./Midnight%20Preprod%20Node%20%E2%80%94%20Full%20Observability.json)** | Grafana dashboard (`v2` schema) with 14 panels covering node health, consensus, P2P networking, transaction pool, and host resources. |

---

## Understanding the Metrics (What They Show & Why We Need Them)

Whether you are new to Substrate/Midnight or operating a validator in production, each metric answers a specific operational question:

### 1. Availability & Consensus Health
| Dashboard Panel / Metric | What It Shows | Why We Need It |
| :--- | :--- | :--- |
| **Node Status** (`up{job="midnight-node"}`) | `1` if Prometheus can reach `:9615/metrics`, `0` if not. | Immediately tells you if `midnight-node` crashed, was stopped, or is unreachable. |
| **Best Block** (`substrate_block_height{status="best"}`) | Highest block number the node has imported/authored. | Confirms the node is actively tracking the head of the chain. |
| **Block Height (Best vs Finalized vs Target)** | Compares `best`, `finalized`, and `sync_target` heights together. | Shows at a glance if the node is synced (`best == sync_target`) and finalizing cleanly. |
| **Block Import Rate (blocks/min)** | Rate of new blocks entering the node per minute. | Drops to `0` if the node freezes, loses peers, or hits a database/disk bottleneck. |
| **Sync State** & **Blocks Behind Target** | Whether the node is still catching up and how many blocks behind `sync_target` it sits. | Tells you if a node is healthy at tip (`0` behind) vs. recovering from downtime. |
| **Finality Lag (Blocks)** (`best - finalized`) | Gap between the latest imported block and the latest GRANDPA-finalized block. | A small gap (1–3 blocks) is normal; a growing gap warns of consensus/peer trouble or potential forks. |

### 2. P2P Networking & Overlay Health
| Dashboard Panel / Metric | What It Shows | Why We Need It |
| :--- | :--- | :--- |
| **Connected Peers** / **P2P Peers Over Time** (`substrate_sub_libp2p_peers_count`) | Number of active libp2p peers connected to `midnight-node`. | On Preprod, validators peer over the WireGuard overlay. Too few peers risks isolation and missed blocks. |
| **Libp2p Network Traffic (B/s)** | Inbound and outbound P2P bytes per second. | Helps spot silent network stalls or bandwidth saturation even when peer count looks normal. |

### 3. Transaction Pool & Host Infrastructure
| Dashboard Panel / Metric | What It Shows | Why We Need It |
| :--- | :--- | :--- |
| **Transaction Pool (Ready Txs)** | Number of pending transactions waiting in the node's ready pool. | A sudden spike without draining can indicate stalled block authoring or network congestion. |
| **Host CPU & Memory Usage (%)** (`node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes`) | Host CPU load and percentage of RAM used. | `midnight-node`, `cardano-node`, `cardano-db-sync`, and PostgreSQL share host RAM; >90% risks an OOM kill. |
| **Disk Usage (%)** & **Disk I/O (Read vs Write)** | SSD capacity consumed and read/write throughput. | Full disks or saturated disk IOPS halt both PostgreSQL (`cexplorer`) and Substrate state writes. |

---

## Alert Design Choices

The rules in [alerts.yml](./alerts.yml) are designed around three principles:

1. **Signal over noise (`for` windows):** Every rule requires the condition to persist (`1m` to `5m`) before firing. This filters out brief `15s` scrape hiccups, service restarts, and transient 1–2 block finality bumps.
2. **Clear severity split (`critical` vs `warning`):**
   - `critical` is reserved for conditions where the node is **down** or **not progressing** (`MidnightNodeDown`, `MidnightBlockImportStalled`).
   - `warning` catches **early degradation** (`MidnightLowPeers`, `MidnightFinalityLag`, `HostHighMemoryUsage`) so operators can intervene *before* the node goes down.
3. **Full-stack coverage (Substrate + Host):** Monitoring only `midnight-node` misses host-level failures like PostgreSQL or `midnight-node` getting OOM-killed, which is why `node-exporter` memory alerting is paired with Substrate metrics.

### All Configured Rules (`alerts.yml`)
- **`MidnightNodeDown`** (`critical`, `1m`) — Scrape target `:9615` unreachable.
- **`MidnightBlockImportStalled`** (`critical`, `2m`) — `best` block height unchanged over `5m`.
- **`MidnightLowPeers`** (`warning`, `3m`) — `substrate_sub_libp2p_peers_count < 3`.
- **`MidnightFinalityLag`** (`warning`, `5m`) — `best - finalized > 10` blocks.
- **`HostHighMemoryUsage`** (`warning`, `5m`) — Host memory usage `> 90%`.

---

## Top 3 Most Important Alerts & Operational Response

### 1. `MidnightNodeDown` (Critical)
- **Condition:** `up{job="midnight-node"} == 0` for `1m`
- **Why it matters:** The node process is unreachable on `:9615`. A validator in this state is completely offline, cannot import or author blocks, and is missing consensus duties.
- **Operational Response:**
  1. Check service status and recent logs:
     ```bash
     sudo systemctl status midnight-node
     journalctl -u midnight-node -n 100 --no-pager
     ```
  2. Check kernel logs for an Out-Of-Memory (OOM) kill:
     ```bash
     dmesg -T | grep -i -E "oom|killed process"
     ```
  3. Verify dependencies are running (`postgresql`, `cardano-node`, `cardano-db-sync`, and `wg-quick@wg0`).
  4. Fix the underlying cause (config, DB connection, or memory pressure) and restart:
     ```bash
     sudo systemctl restart midnight-node
     ```

### 2. `MidnightBlockImportStalled` (Critical)
- **Condition:** `increase(substrate_block_height{status="best"}[5m]) == 0` for `2m`
- **Why it matters:** The process is still alive (so `MidnightNodeDown` won't fire), but the chain has stopped advancing on this node. Common causes on Midnight Preprod are WireGuard tunnel drops, PostgreSQL/`cardano-db-sync` stalls, or disk exhaustion.
- **Operational Response:**
  1. Inspect `midnight-node` logs for database, RPC, or block-import errors:
     ```bash
     journalctl -u midnight-node -f --no-pager -n 100
     ```
  2. Verify the WireGuard overlay has active peer handshakes:
     ```bash
     sudo wg show
     ```
  3. Check `cardano-db-sync` and PostgreSQL health (a stalled `cexplorer` DB blocks Midnight's Cardano availability layer) and check free disk space (`df -h`).
  4. If peers are `0` or WireGuard handshakes are stale, restart `wg-quick@wg0` or check firewall/network rules on port `30333` and the WireGuard UDP port.

### 3. `MidnightFinalityLag` (Warning)
- **Condition:** `(substrate_block_height{status="best"} - ignoring(status) substrate_block_height{status="finalized"}) > 10` for `5m`
- **Why it matters:** Blocks are being imported, but GRANDPA finality is falling behind. If left unresolved, the node risks following a minority fork or failing to finalize blocks it authored.
- **Operational Response:**
  1. Check connected peer count and WireGuard overlay connectivity (`wg show` and the **Connected Peers** Grafana panel) — GRANDPA requires healthy communication with the validator set.
  2. Check host CPU, memory, and disk I/O in Grafana to ensure resource contention isn't delaying finality votes.
  3. Inspect `midnight-node` logs for GRANDPA or keystore/session-key errors (`journalctl -u midnight-node -n 100`).
  4. If the issue is isolated to your node (while other Preprod validators are finalizing normally), restart `midnight-node` after confirming your keystore and `~/.env` configuration are intact.
