# Midnight Preprod Node Health Checker

A zero-dependency Python 3 health-checking and regression-detection utility for a **Midnight Preprod Substrate node** (`Automation/node_health_check.py`).

---

## Practical Operational Utility (When & Why to Use This)

**Would you actually use this in production? 


Honestly: for 24/7 continuous alerting, Prometheus + Alertmanager + Grafana already cover it better (15s scrapes, for: hysteresis windows, deduplication, and alert routing). Running the Python script as a second 24/7 alerter would mostly be redundant.

However, it is genuinely useful in few specific situations where Prometheus/Grafana fall short:
Before/after upgrades & config changes (regression gate):

When upgrading midnight-node, editing .env, or changing WireGuard/firewall rules, running --once before and after gives an instant pass/fail and regression diff (previous.json → latest.json) in your terminal—much faster than hunting through Grafana panels.

Testing JSON-RPC (:9933), not just /metrics (:9615):
Prometheus only scrapes :9615/metrics. The script verifies that the node's JSON-RPC server (system_health, system_syncState, chain_getHeader) is actually responsive and returning valid chain state.

Out-of-band fallback when Docker/monitoring is down:
If Docker, Prometheus, or Grafana crashes (or during a VM incident), a zero-dependency Python script still runs cleanly from the CLI or cron to tell you what the node is doing.

Automation & incident snapshots:
Its exit codes (0 healthy, 1 degraded/regression, 2 unreachable) make it usable as a CI/CD or Ansible post-deploy check, and latest.json gives you a clean, self-contained JSON snapshot you can attach directly to an incident ticket.

### How It Complements `monitoring/` (Prometheus + Grafana)

| Capability | `Automation/node_health_check.py` | `monitoring/` (Prometheus + Grafana) |
| :--- | :--- | :--- |
| **Best used for** | On-demand CLI checks, pre/post-upgrade gates, lightweight cron canaries | 24/7 time-series graphing, multi-minute `for:` alerting, Slack/webhook routing |
| **Dependencies** | Python 3 stdlib only (runs anywhere in seconds) | Prometheus, Alertmanager, Grafana, `node_exporter` |
| **History** | Discrete JSON snapshots (`latest.json`, `previous.json`, `report_*.json`) | Continuous time-series retention & trend dashboards |

> [!TIP]
> **Operational Housekeeping:** In continuous polling mode (`--interval 60`), a new `report_*.json` file is written every minute (~1,440 files/day). Add a periodic cleanup (e.g., `find /var/lib/midnight-health -name 'report_*.json' -mtime +7 -delete`) if running long-term.

---

## Usage Instructions

### Prerequisites

- **Python 3.8+** (uses the Python standard library only — no `pip install` or virtual environment required).
- Network access to the target Midnight Substrate node's:
  - **JSON-RPC HTTP endpoint** (default: `http://127.0.0.1:9933`)
  - **Prometheus metrics endpoint** (default: `http://127.0.0.1:9615/metrics`)
- Optional: Read access to the local node data directory (default: `/data`) for disk space monitoring. If the directory is not present locally (e.g., when monitoring a remote node), the disk check is skipped gracefully.

### Configuration (CLI Flags & Environment Variables)

CLI flags take precedence over environment variables, which take precedence over built-in defaults.

| CLI Flag | Environment Variable | Default | Description |
|---|---|---|---|
| `--rpc-url` | `MIDNIGHT_RPC_URL` | `http://127.0.0.1:9933` | Substrate JSON-RPC HTTP URL |
| `--metrics-url` | `MIDNIGHT_METRICS_URL` | `http://127.0.0.1:9615/metrics` | Prometheus `/metrics` endpoint URL |
| `--output-dir` | `HEALTH_OUTPUT_DIR` | `./health-reports` | Directory for timestamped JSON reports |
| `--interval` | `POLL_INTERVAL` | `60` | Poll interval in seconds (continuous mode) |
| `--once` | — | `false` | Run a single check and exit immediately |
| `--timeout` | `REQUEST_TIMEOUT` | `5.0` | HTTP request timeout in seconds |
| `--min-peers` | `MIN_PEERS` | `3` | Minimum healthy connected peer count |
| `--max-sync-lag` | `MAX_SYNC_LAG` | `50` | Maximum acceptable blocks behind sync target |
| `--max-finality-lag` | `MAX_FINALITY_LAG` | `10` | Maximum acceptable `best_block - finalized_block` lag |
| `--min-block-time` | `MIN_BLOCK_TIME` | `12` | Minimum elapsed seconds before unchanged `best_block` is flagged |
| `--max-stall-seconds` | `MAX_STALL_SECONDS` | `120` | Elapsed seconds without a new block before failing |
| `--data-dir` | `DATA_DIR` | `/data` | Local node data directory for disk space check |
| `--min-disk-free-pct` | `MIN_DISK_FREE_PCT` | `15.0` | Minimum free disk percentage threshold |
| `--skip-disk-check` | — | `false` | Explicitly skip the local disk space check |
| `--json` | — | `false` | Print machine-readable JSON report to stdout |

### Running Once vs. Continuous Polling

**Single check (ideal for cron, CI, or manual verification):**

```bash
python3 scripts/node_health_check.py --once
```

With custom endpoints and JSON stdout:

```bash
python3 scripts/node_health_check.py \
  --once \
  --rpc-url http://127.0.0.1:9933 \
  --metrics-url http://127.0.0.1:9615/metrics \
  --output-dir /var/log/midnight-health \
  --json
```

**Continuous polling (ideal for systemd or foreground monitoring):**

```bash
# Polls every 60 seconds by default; stops cleanly on SIGINT / SIGTERM
python3 scripts/node_health_check.py --interval 60
```

Using environment variables:

```bash
MIDNIGHT_RPC_URL=http://10.0.1.15:9933 \
MIDNIGHT_METRICS_URL=http://10.0.1.15:9615/metrics \
MIN_PEERS=5 \
python3 scripts/node_health_check.py --interval 30 --skip-disk-check
```

### Exit Codes

| Exit Code | Meaning |
|---|---|
| `0` | `HEALTHY` and no regressions detected |
| `1` | `DEGRADED` status **or** one or more regressions detected |
| `2` | `UNHEALTHY` status or node unreachable |

### Example Output

**Human-readable stdout (default):**

```text
=== Midnight Node Health Check [2026-11-17T19:55:00Z] ===
Overall Status : DEGRADED
Report File    : health-reports/report_20261117T195500Z.json

Metrics:
  best_block      : 104250
  finalized_block : 104235
  finality_lag    : 15
  peers           : 4
  is_syncing      : False
  blocks_behind   : 0
  disk_free_pct   : 62.4

Checks:
  [PASS] endpoint_reachability: JSON-RPC and Prometheus metrics endpoints are reachable
  [PASS] peer_count: Peer count healthy: 4 (>= 3)
  [PASS] sync_progress: Sync healthy (is_syncing=False, blocks_behind=0)
  [WARN] finality_lag: High finality lag: 15 blocks (> 10)
  [PASS] block_progression: Chain advanced by +8 blocks (104242 -> 104250)
  [PASS] disk_space: Disk space healthy on '/data': 62.4% free

Regressions Detected (2):
  - [WARNING] Overall status worsened: HEALTHY -> DEGRADED
  - [WARNING] Finality lag grew beyond threshold (10): 4 -> 15
```

**Machine-readable stdout (`--json`):**

```json
{
  "timestamp": "2026-11-17T19:55:00Z",
  "overall_status": "DEGRADED",
  "checks": {
    "endpoint_reachability": {
      "status": "pass",
      "observed": { "rpc": true, "metrics": true },
      "threshold": "rpc_and_metrics_reachable",
      "message": "JSON-RPC and Prometheus metrics endpoints are reachable"
    },
    "finality_lag": {
      "status": "warn",
      "observed": 15,
      "threshold": 10,
      "message": "High finality lag: 15 blocks (> 10)"
    }
  },
  "metrics": {
    "best_block": 104250,
    "finalized_block": 104235,
    "finality_lag": 15,
    "peers": 4,
    "is_syncing": false,
    "blocks_behind": 0,
    "disk_free_pct": 62.4
  },
  "regressions": [
    {
      "type": "status_worsened",
      "severity": "warning",
      "message": "Overall status worsened: HEALTHY -> DEGRADED",
      "previous": "HEALTHY",
      "current": "DEGRADED"
    }
  ]
}
```

### How Regression Diffing Works

Each execution writes an immutable, timestamped report to `<output_dir>/report_<YYYYMMDDTHHMMSSZ>.json` using atomic temp-file writes (`fsync` + `os.replace`) and rotates two symlinks:

1. Before writing, the script reads `<output_dir>/latest.json` (if it exists — skipped cleanly on the first baseline run).
2. After writing the new report, `previous.json` is atomically updated to point to the prior `latest.json` target, and `latest.json` is atomically updated to point to the new report.
3. The current metrics and status are diffed against the prior report to flag:
   - **Status worsened**: e.g., `HEALTHY` → `DEGRADED` or `UNHEALTHY`.
   - **Node became unreachable**: JSON-RPC was reachable in the previous run and is now unreachable.
   - **Peer count drop**: Peers dropped below `MIN_PEERS` or dropped by `>= 50%` compared to the previous poll.
   - **Best block stalled or decreased**: `best_block` did not advance (after `MIN_BLOCK_TIME` seconds) or decreased.
   - **Finality lag exceeded**: `finality_lag` crossed above `MAX_FINALITY_LAG`.

### Running via Cron or Systemd

#### Option A: Cron (periodic `--once` execution)

Run every minute and log output:

```cron
* * * * * /usr/bin/python3 /opt/midnight/scripts/node_health_check.py --once --output-dir /var/log/midnight-health >> /var/log/midnight-health/cron.log 2>&1
```

#### Option B: Systemd Service (continuous polling)

Create `/etc/systemd/system/midnight-health-check.service`:

```ini
[Unit]
Description=Midnight Preprod Node Health Checker
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=midnight
Group=midnight
Environment=MIDNIGHT_RPC_URL=http://127.0.0.1:9933
Environment=MIDNIGHT_METRICS_URL=http://127.0.0.1:9615/metrics
Environment=HEALTH_OUTPUT_DIR=/var/lib/midnight-health
Environment=POLL_INTERVAL=60
Environment=DATA_DIR=/data
ExecStart=/usr/bin/python3 /opt/midnight/scripts/node_health_check.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now midnight-health-check.service
sudo journalctl -u midnight-health-check.service -f
```
