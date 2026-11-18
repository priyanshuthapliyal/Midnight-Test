# Midnight Preprod Node Deployment, Observability & Automation

An end-to-end **Midnight Preprod** node deployment, monitoring, security, and health-checking repository—covering bare-metal/VM `systemd` setup, containerized Terraform IaC, Prometheus + Grafana observability, and zero-dependency Python health automation.

---

## 1. Project Overview & Architecture (What Was Built)

This repository contains two complementary deployment paths alongside observability, security, and health-checking tooling:

- **VM / `systemd` Preprod Validator Runbooks ([`Node Setup/`](./Node%20Setup/README.md))**: Step-by-step guides for deploying `cardano-node`, PostgreSQL 17 (`cexplorer`), `cardano-db-sync`, `midnight-node` (with AURA/GRANDPA/Cross-Chain keys and Substrate keystore), WireGuard trusted overlay (`wg0`), and the `midnight-node.service` `systemd` unit, plus captured logs and screenshots in [`Node Setup/logs and screenshots/`](./Node%20Setup/logs%20and%20screenshots/).
- **Containerized IaC Stack ([`infra/`](./infra/README.md))**: Terraform (`kreuzwerker/docker`) configuration provisioning a 5-component stack (`cardano-node`, `postgres`, `cardano-db-sync`, `midnight-node`, `midnight-indexer`) across 5 trust-segmented Docker bridge networks, with environment profiles (`preprod`, `preview`, `mainnet`), helper scripts (`infra/scripts/`), and `terraform test` checks (`infra/tests/infrastructure.tftest.hcl`).
- **Monitoring & Alerting ([`monitoring/`](./monitoring/README.md))**: Prometheus scrape config, Alertmanager webhook routing, 5 alert rules (`alerts.yml`), and a 14-panel Grafana dashboard (`Midnight Preprod Node — Full Observability.json`).
- **Automated Health & Regression Checker ([`Automation/`](./Automation/README.md))**: Python 3 standard-library-only CLI (`Automation/node_health_check.py`) that probes JSON-RPC (`:9933`), Prometheus (`/metrics`), and local disk space, writes atomic timestamped JSON reports, and diffs against `previous.json`.
- **Security & Key Management ([`Security/SECURITY.md`](./Security/SECURITY.md))**: Cloud key storage architecture (Secrets Manager + KMS vs. HSM tradeoffs), zero-downtime `n+2` epoch key rotation, and incident response runbook.
- **AI Usage Log ([`AI_USAGE.md`](./AI_USAGE.md))**: Transparent log of AI prompts, generated outputs, and manual verification/debugging steps.

### Repository Structure

```text
.
├── README.md
├── AI_USAGE.md                       # AI prompts, outputs, and verification log
├── Automation/
│   ├── README.md
│   └── node_health_check.py          # Stdlib-only health checker & regression differ
├── Node Setup/
│   ├── README.md                     # 4-step Preprod setup index & system requirements
│   ├── running-cardano-node.md       # Step 1: cardano-node + PostgreSQL 17 + cardano-db-sync
│   ├── Validator key genration.md    # Step 2: midnight-node binary, session/network keys, keystore
│   ├── wireguard.md                  # Step 3: WireGuard v1.0.20250521 overlay setup
│   ├── running validator.md          # Step 4: ~/.env, systemd unit, n+2 epoch verification
│   └── logs and screenshots/
│       ├── cardano-node.log
│       ├── db-sync.log
│       └── midnite-node-logs.png
├── Security/
│   └── SECURITY.md                   # Cloud key storage, rotation & incident response
├── infra/
│   ├── README.md
│   ├── main.tf                       # Docker networks + 5 component modules
│   ├── providers.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   ├── .env.example
│   ├── .tflint.hcl
│   ├── terraform.tfvars.example
│   ├── environments/
│   │   ├── mainnet.tfvars
│   │   ├── preprod.tfvars
│   │   └── preview.tfvars
│   ├── modules/
│   │   ├── cardano-node/
│   │   ├── cardano-db-sync/
│   │   ├── postgres/
│   │   ├── midnight-node/
│   │   └── midnight-indexer/
│   ├── scripts/
│   │   ├── bootstrap.sh
│   │   ├── health-check.sh
│   │   └── test.sh
│   └── tests/
│       └── infrastructure.tftest.hcl
└── monitoring/
    ├── README.md
    ├── prometheus.yml                # Scrapes midnight-node (:9615) & node-exporter (:9100)
    ├── alerts.yml                    # 5 alert rules under midnight-node-alerts
    ├── alertmanager.yml              # Webhook routing (group_wait 30s, repeat 4h)
    ├── Midnight Preprod Node — Full Observability.json
    └── dashboard.png
```

---

## 2. Assumptions Made

- **Single-VM Azure Preprod Target**: Built for a single-VM deployment on Azure targeting Midnight **Preprod** (`CARDANO_SECURITY_PARAMETER=2160`).
- **Security-First Networking**: Only SSH (`22/tcp`) is exposed during setup (plus `51820/udp` for WireGuard when the overlay is active). JSON-RPC (`9933`), Prometheus (`9615`, `9090`), and Grafana (`3000`) remain bound to localhost and are accessed via SSH port-forwarding.
- **Substrate Keystore Over Plain-Text Seed Env Vars**: Validator signing keys (AURA, GRANDPA, Cross-Chain) are inserted into Substrate's keystore (`--base-path`) using `midnight-node key insert` (documented in [`Node Setup/Validator key genration.md`](./Node%20Setup/Validator%20key%20genration.md)) rather than passing plain-text `*_SEED_FILE` environment variables.

---

## 3. Blockers Faced & Root-Cause Lessons Learned

1. **Unclear Versioning in Upstream Docs**
   - *Blocker:* Upstream setup guides did not clearly specify exact compatible component versions.
   - *Resolution:* Verified compatible versions across the stack and explicitly pinned/documented them in the guides and IaC configs (e.g., `cardano-node` `11.1.3`, `cardano-db-sync` `13.7.1.0`, PostgreSQL `17`, `midnight-node` `2.1.101-rc.2`, WireGuard `v1.0.20250521`).
2. **Azure Free-Tier Credit Limit & Validator vs. Full Node**
   - *Blocker:* All validator preparation steps—key generation, keystore insertion, `systemd` service setup, monitoring, and health checks—were completed. However, Azure account credits ran out and no Static Public IP was available to submit to the Midnight Foundation for the WireGuard trusted overlay (`wg0`).
   - *Resolution:* Ran the node at the final stage as a **full (non-validator) syncing node** rather than an active registered validator.
3. **30 GB Root Disk IOPS Bottleneck & 220 GB SSD Exhaustion**
   - *Blocker:* PostgreSQL (`cardano-db-sync`) initially wrote its database to the 30 GB root OS disk (which had much lower IOPS) instead of the attached 220 GB SSD (`/data`), causing severe disk I/O bottlenecks and slow `db-sync` indexing.
   - *Diagnosis & Mitigation:* Diagnosed the storage bottleneck using `iostat` and migrated the PostgreSQL data directory to `/data`, after which `cardano-db-sync` synced significantly faster. However, when running the `midnight-node` full node, it stalled because the entire **220 GB SSD** capacity was consumed after sometime.
   - *Lesson Learned:* Documented a strict **minimum 500 GB SSD** requirement in [`Node Setup/README.md`](./Node%20Setup/README.md#system-requirements) to prevent storage exhaustion across Cardano chain data, `cexplorer`, and Midnight state.
4. **Verification Failure (`CARDANO_SECURITY_PARAMETER` Mismatch)**
   - *Blocker:* `midnight-node` initially failed to start with `mc_hash` verification errors.
   - *Root Cause & Resolution:* Debugged the startup failure and found that `CARDANO_SECURITY_PARAMETER` was set to `432` (Preview) instead of `2160` (Preprod). Updating it to `2160` resolved the `mc_hash` mismatch. (Fixed in new docs)

---

## 4. Monitoring & Alerting (`monitoring/`)

The [`monitoring/`](./monitoring/) stack pairs **Prometheus** (`15s` scrape of `midnight-node` on `:9615` and `node-exporter` on `:9100`), **Alertmanager** (webhook routing with `send_resolved: true`), and a **14-panel Grafana dashboard** ([`Midnight Preprod Node — Full Observability.json`](./monitoring/Midnight%20Preprod%20Node%20%E2%80%94%20Full%20Observability.json)).

### Signal-Over-Noise Alert Design
- **Persistence (`for:`) Windows**: Every rule requires the condition to hold for `1m`–`5m` before firing, filtering out `15s` scrape blips, brief restarts, and normal 1–2 block finality variance.
- **Severity Split**: `critical` pages only when the node is unreachable or stopped importing blocks; `warning` surfaces early degradation (low peers, finality lag, high host memory) before a crash.
- **Full-Stack Coverage**: Pairs Substrate metrics with `node_exporter` memory metrics because OOM kills on PostgreSQL or `midnight-node` are a primary failure mode.

| Alert | Severity | Condition (`for:`) | Operational Response |
|---|---|---|---|
| `MidnightNodeDown` | `critical` | `up{job="midnight-node"} == 0` (`1m`) | Check `systemctl status midnight-node` & `journalctl`, check `dmesg` for OOM kills, verify PostgreSQL/`cardano-db-sync`/`wg0`, restart service. |
| `MidnightBlockImportStalled` | `critical` | `increase(substrate_block_height{status="best"}[5m]) == 0` (`2m`) | Inspect `midnight-node` logs for DB/RPC locks, verify `wg show` handshakes, check `cardano-db-sync` lag and `df -h`. |
| `MidnightLowPeers` | `warning` | `substrate_sub_libp2p_peers_count < 3` (`3m`) | Run `wg show` to verify WireGuard peers, check `30333/tcp` and WireGuard UDP firewall rules, inspect peer logs. |
| `MidnightFinalityLag` | `warning` | `(best - finalized) > 10` (`5m`) | Check peer count & WireGuard connectivity, check CPU/RAM/disk I/O contention in Grafana, inspect logs for GRANDPA/keystore errors. |
| `HostHighMemoryUsage` | `warning` | Memory used `> 90%` (`5m`) | Identify top RSS consumer (`midnight-node`, `postgres`, `cardano-db-sync`), tune PostgreSQL `shared_buffers`/`work_mem` or scale RAM. |

See [`monitoring/README.md`](./monitoring/README.md) for full metric explanations and runbooks.

---

## 5. Node Health Checker (`Automation/node_health_check.py`)

[`Automation/node_health_check.py`](./Automation/node_health_check.py) is a zero-dependency Python 3 script (standard library only) that evaluates 6 conditions: endpoint reachability (JSON-RPC + `/metrics`), peer count, sync progress/lag, finality lag, block progression, and local disk space.

### Usage

```bash
# Single check (ideal for cron, CI, or pre/post-upgrade gates)
python3 Automation/node_health_check.py --once

# Continuous polling (default: 60s) with custom thresholds & JSON stdout
python3 Automation/node_health_check.py \
  --rpc-url http://127.0.0.1:9933 \
  --metrics-url http://127.0.0.1:9615/metrics \
  --output-dir ./health-reports \
  --interval 60 \
  --min-peers 3 \
  --max-sync-lag 50 \
  --max-finality-lag 10 \
  --data-dir /data \
  --min-disk-free-pct 15 \
  --json
```

### Reports, Regression Diffing & Exit Codes
- **Atomic Reports**: Writes `<output_dir>/report_<YYYYMMDDTHHMMSSZ>.json` atomically (`fsync` + `os.replace`) and rotates `latest.json` and `previous.json` symlinks.
- **Regression Diffing**: Compares each run against the prior `latest.json` to flag `status_worsened`, `node_unreachable`, `peers_below_threshold` / `peers_sharp_drop` (`>= 50%`), `best_block_stalled` / `best_block_decreased`, and `finality_lag_exceeded`.
- **Exit Codes**: `0` = `HEALTHY` (no regressions), `1` = `DEGRADED` or regression detected, `2` = `UNHEALTHY` / unreachable.

### Practical Utility Alongside Prometheus/Grafana
Prometheus + Grafana handles 24/7 time-series graphing and Slack routing; `node_health_check.py` fills three specific operational gaps:
1. **Exercises JSON-RPC (`:9933`)**: `prometheus.yml` only scrapes `:9615/metrics` and `:9100`, so it won't catch a hung or malformed JSON-RPC server.
2. **Synchronous CI/CD & Upgrade Gates**: Deterministic exit codes (`0`/`1`/`2`) plug directly into upgrade scripts or Ansible to halt/roll back on regressions.
3. **Out-of-Band SSH Fallback**: Works locally in under a second over SSH even if Docker, Prometheus, or Grafana is down.

---

## 6. What I Would Do Differently With More Time

- **Decouple Infrastructure from Deployment (Terraform + Ansible / Kubernetes)**:
  - Use Terraform strictly for cloud infrastructure (VM, VNet, NSG, Static Public IP, attached NVMe/SSD disks) rather than OS/application lifecycle.
  - Move node and monitoring deployment to **Ansible** (for VM setups) or **Kubernetes** (e.g., AKS with `StatefulSet`s and high-IOPS `PersistentVolumeClaim`s) for idempotent configuration, cleaner upgrades, and repeatability.
- **Adequate Storage & Dedicated High-IOPS Disks**:
  - Provision a properly sized, high-IOPS SSD volume (500 GB+ instead of 220 GB) mounted at `/data` from day one, and ensure PostgreSQL, `cardano-node`, `cardano-db-sync`, and `midnight-node` all write exclusively to `/data`.
- **Enhanced Monitoring & Custom Exporters**:
  - Add a custom Prometheus exporter to monitor the **validator wallet/collateral balance** and alert before funds drop below the required threshold.
  - Add `postgres_exporter`, `cardano-db-sync` sync-lag metrics, and **disk IOPS/latency alerts** to catch storage bottlenecks before sync stalls.
  - Add WireGuard (`wg0`) handshake monitoring and an **external** dead-man's-switch / remote Prometheus probe so alerts still fire if the VM itself goes down.
