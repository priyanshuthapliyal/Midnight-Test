# AI Usage Log (`AI_USAGE.md`)

---

## 1. Approach to Using AI

AI was used as an **engineering pair-programmer** across the Terraform IaC (`infra/`), observability (`monitoring/`), health-checking (`Automation/`), security design (`Security/`), and documentation (`README.md`, `Node Setup/README.md`) portions of this assignment. The VM-based node setup and live troubleshooting on Azure (`cardano-node`, `cardano-db-sync`, PostgreSQL migration, `midnight-node`, `iostat`, and `mc_hash` debugging) were performed manually, and those real-world findings were fed back into AI prompts to keep configs and documentation accurate.

Every AI-generated configuration, script, and dashboard was **manually tested, debugged, and verified** against the live node, Terraform tooling, or local test harnesses.

---

## 2. Prompts Used & Outputs Received (By Task)

### 1. Terraform & Docker Infrastructure (`infra/` — Separate Chat Session)
- **Iterative Prompting & Context Grounding:**
  > First walked AI through the Midnight architecture documentation (`cardano-node` → `cardano-db-sync` → PostgreSQL `cexplorer` → `midnight-node` → `midnight-indexer`) so it understood the component dependencies, socket/TLS requirements, and network boundaries before prompting across multiple iterations for modular Terraform (`kreuzwerker/docker`) code, environment profiles, security hardening, and validation tests.
- **Summary of Output Generated:**
  - Created [`infra/main.tf`](./infra/main.tf), [`infra/variables.tf`](./infra/variables.tf), [`infra/outputs.tf`](./infra/outputs.tf), and 5 component modules under [`infra/modules/`](./infra/modules/) segmented across 5 Docker networks (`cardano_p2p`, `db_internal`, `midnight_p2p`, `indexer_internal`, `indexer_api`).
  - Added environment configs ([`infra/environments/`](./infra/environments/) for `preprod`, `preview`, `mainnet`), helper scripts ([`infra/scripts/`](./infra/scripts/): `bootstrap.sh`, `health-check.sh`, `test.sh`), [`infra/.tflint.hcl`](./infra/.tflint.hcl), and [`infra/tests/infrastructure.tftest.hcl`](./infra/tests/infrastructure.tftest.hcl).
- **Verification & Fixes Applied:**
  - Validated with `terraform plan` (saved [`infra/preview.tfplan`](./infra/preview.tfplan)), `tflint`, and `terraform test` (`infrastructure.tftest.hcl`), and documented `terraform.tfstate` sensitivity caveats in [`infra/README.md`](./infra/README.md).

---

### 2. Monitoring & Alerting (`monitoring/`)
- **Prompts Used (Iterative):**
  > Asked for a Prometheus + Alertmanager + Node Exporter + Grafana setup with meaningful alerts and a rich dashboard without exposing internal ports publicly, followed by a plain-language `monitoring/README.md` explaining what each metric shows, alert design choices, and operational runbooks for the top 3 alerts.
- **Summary of Output Generated:**
  - Generated [`monitoring/prometheus.yml`](./monitoring/prometheus.yml) (15s scrape of `:9615` and `:9100`), [`monitoring/alerts.yml`](./monitoring/alerts.yml) (5 rules with `1m`–`5m` `for:` hysteresis windows), [`monitoring/alertmanager.yml`](./monitoring/alertmanager.yml) (webhook routing), [`monitoring/Midnight Preprod Node — Full Observability.json`](./monitoring/Midnight%20Preprod%20Node%20%E2%80%94%20Full%20Observability.json) (14-panel Grafana dashboard), and [`monitoring/README.md`](./monitoring/README.md).
- **Verification & Iterative Fixes:**
  - Accessed Prometheus and Grafana securely via SSH port-forwarding (`ssh -L`) rather than opening public firewall ports.
  - Resolved Grafana v13 `v2`-schema import validation issues using Classic JSON Import.
  - Caught and fixed PromQL vector-matching `No data` issues on `Blocks Behind Target` and `Finality Lag` by adding `ignoring(status)` in both the dashboard and [`monitoring/alerts.yml`](./monitoring/alerts.yml).

---

### 3. Node Health Checker (`Automation/node_health_check.py`)
- **Prompts Used:**
  > Create a production-quality Node Health Checker script using Python 3 (standard library only — no external pip dependencies) for a Midnight Preprod Substrate node. Evaluate endpoint reachability (`system_health`, `system_syncState`, `chain_getHeader`, `chain_getFinalizedHead`, `/metrics`), peer count, sync lag, finality lag, block progression, and local disk space. Write timestamped JSON reports (`latest.json`/`previous.json`), diff regressions against `previous.json`, support `--once` / `--interval` / `--json`, and use exit codes `0`/`1`/`2`. Follow-up prompts also challenged whether the script adds real value alongside Prometheus/Grafana and documented its role in CI/upgrade gating.
- **Summary of Output Generated:**
  - Created [`Automation/node_health_check.py`](./Automation/node_health_check.py) (stdlib-only Python 3) and [`Automation/README.md`](./Automation/README.md) with CLI flags, env var overrides, atomic file/symlink rotation, regression detection, `cron`/`systemd` examples, and a comparison against Prometheus/Grafana.
- **Verification & Fixes Applied:**
  - Verified against a local mock JSON-RPC + Prometheus HTTP test server covering `HEALTHY` (`0`), `>= 50%` peer drop and block stall (`1`), finality lag exceeded (`1`), and malformed/unreachable RPC (`2`).
  - Tested via SSH-forwarded ports (`-L 9933:127.0.0.1:9933 -L 9615:127.0.0.1:9615`) and adjusted `--output-dir` / `--data-dir` (plus `--skip-disk-check` for remote runs).

---

### 4. Documentation & Security Design (`README.md`, `Node Setup/README.md`, `Security/SECURITY.md`)
- **Prompts Used:**
  > Iteratively prompted AI to organize [`Node Setup/`](./Node%20Setup/README.md) into a clear 4-step sequence (`cardano-node` → `FNOSetup` → `wireguard` → `running validator`) with hardware requirements (`8 vCPU`, `16–32 GB RAM`, `500 GB+ SSD`), draft [`Security/SECURITY.md`](./Security/SECURITY.md) (cloud key storage tradeoffs, `n+2` key rotation, incident response), and write a repo-scoped [`README.md`](./README.md) reflecting only files and configurations actually present in the repository.
- **Summary of Output Generated:**
  - Generated [`Node Setup/README.md`](./Node%20Setup/README.md) (plus step navigation headers/footers), [`Security/SECURITY.md`](./Security/SECURITY.md), and [`README.md`](./README.md) documenting architecture, assumptions, and real blockers encountered on the VM.
- **Verification & Fixes Applied:**
  - Cross-checked every file path and directory name against the repository tree and corrected disk-size details (30 GB root disk, 220 GB attached SSD `/data`) and the `CARDANO_SECURITY_PARAMETER` (`432` vs. `2160`) `mc_hash` finding from manual VM debugging.

---

## 3. Key Takeaways (Human-in-the-Loop Engineering)

- **Grounding AI in Architecture First:** Teaching AI the Midnight + Cardano dependency chain (`cardano-node` → `cardano-db-sync` → PostgreSQL → `midnight-node` → `midnight-indexer`) before generating Terraform prevented generic single-container templates and produced properly segmented Docker networks and secrets handling.
- **Feeding Real VM Findings Back into Docs:** Manual `iostat` diagnosis on the 30 GB root disk, observing the 220 GB `/data` SSD fill up during `midnight-node` sync, and debugging `CARDANO_SECURITY_PARAMETER=2160` (`mc_hash`) were essential to grounding the hardware requirements and blocker analysis.
- **Catching Subtle Observability Bugs:** Caught PromQL `ignoring(status)` label-matching failures and Grafana v13 schema differences during live dashboard testing—issues that static config generation alone does not surface.
- **Evaluating Tooling Fit Honestly:** Critically assessed where [`Automation/node_health_check.py`](./Automation/node_health_check.py) adds genuine operational value alongside Prometheus/Grafana (JSON-RPC `:9933` verification, synchronous CI/upgrade exit codes, and out-of-band SSH triage) rather than treating it as a duplicate alerting daemon.
