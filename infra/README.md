# Cardano & Midnight Infrastructure (Terraform + Docker)

Terraform configuration for running the 5-component Cardano + Midnight stack on a local Docker host:

1. `cardano-node` (`ghcr.io/intersectmbo/cardano-node:11.1.3-amd64`)
2. `postgres` (`postgres:17`)
3. `cardano-db-sync` (`ghcr.io/intersectmbo/cardano-db-sync:13.7.1.0`)
4. `midnight-node` (`midnightntwrk/midnight-node:2.1.101-rc.2`)
5. `midnight-indexer` (`midnightntwrk/indexer-standalone:latest`)

---

## Quick Start

```bash
cd infra
cp .env.example .env
# Edit .env with your local secrets (never commit .env)
set -a; source .env; set +a

./scripts/bootstrap.sh preview
terraform plan -var-file="environments/preview.tfvars"
```

---

## 1. Docker Network Architecture

Five isolated Docker bridge networks (`<env>-*`) segment traffic by trust boundary, using Docker's embedded DNS (never fixed IP addresses):

| Network | `internal` | Attached Containers | Purpose |
|---|---|---|---|
| `<env>-cardano-p2p` | `false` | `cardano-node` | Cardano P2P (`3001/tcp`) |
| `<env>-db-internal` | `true` | `postgres`, `cardano-db-sync`, `midnight-node` | Isolated PostgreSQL TLS traffic (`5432/tcp`); no internet routing |
| `<env>-midnight-p2p` | `false` | `midnight-node` | Midnight P2P (`30333/tcp`) |
| `<env>-indexer-internal` | `true` | `midnight-node`, `midnight-indexer` | Internal WebSocket RPC (`ws://<midnight-node>:9944`) |
| `<env>-indexer-api` | `false` | `midnight-indexer` | Host-published GraphQL API (`127.0.0.1:8088`) |

- **Cardano Node ↔ Cardano DB Sync:** Communicates over the shared Unix domain socket (`/ipc/node.socket`) volume rather than TCP.
- **Midnight Node ↔ PostgreSQL:** `midnight-node` 2.1.101 requires TLS access to `cexplorer` (`DB_SYNC_POSTGRES_CONNECTION_STRING`), so it is attached to `<env>-db-internal`.

## 2. PostgreSQL Security

- Port `5432` is **not** published to the Docker host.
- Only `cardano-db-sync` and `midnight-node` share `<env>-db-internal` with `postgres`.
- Password is injected via `POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password` (`0400`) and `PGPASSFILE=/run/secrets/pgpass` (`0600`), never hard-coded in Terraform.
- TLS is enabled (`ssl=on`) when `postgres_enable_tls = true` and `postgres_tls_host_dir` provides `server.crt` and `server.key`.

## 3. RPC and P2P Exposure

- **Publicly published P2P ports:** Only `3001/tcp` (`cardano-node`) and `30333/tcp` (`midnight-node`).
- **Restricted RPC:** `midnight-node` WebSocket RPC (`9944/tcp`) is **not** published to the host; it is reachable only by `midnight-indexer` over `<env>-indexer-internal`.
- **Indexer API:** `midnight-indexer` (`8088/tcp`) is bound to `127.0.0.1` by default (`indexer_api_bind_ip = "127.0.0.1"`).
- **Container hardening:** All 5 containers set `security_opts = ["no-new-privileges:true"]` and bounded `json-file` log rotation.

## 4. Secrets Injection & Terraform State Security

- Copy `.env.example` to `.env` (or `terraform.tfvars.example` to `terraform.tfvars`). Both `.env` and `terraform.tfvars` are excluded by `.gitignore`.
- `postgres_password`, `indexer_secret`, and `blockfrost_api_key` are marked `sensitive = true` in `variables.tf` and are never exposed in `outputs.tf`.
- **Important limitation:** Marking a Terraform variable `sensitive = true` hides it from CLI plan/apply output, **not** from `terraform.tfstate` (nor from `docker inspect` for env vars such as `DB_SYNC_POSTGRES_CONNECTION_STRING`). Protect local state files with strict filesystem permissions (`chmod 600`) and never commit `*.tfstate*`.
- Local `.env` / `upload` secret files do **not** provide the same security guarantees as a production secret manager (e.g., Vault, KMS, or hardware-backed secrets).

## 5. Persistent Storage Protection

Six named Docker volumes (`<env>_*`) store blockchain and database state outside container filesystems:
- `<env>_cardano_node_db`, `<env>_cardano_ipc`, `<env>_postgres_data`, `<env>_cardano_db_sync_state`, `<env>_midnight_node_data`, `<env>_midnight_indexer_data`.

- **Container removal vs. volume deletion:** Recreating or removing a `docker_container` (e.g., during image or flag updates) preserves named volumes. Running `terraform destroy`, however, **deletes** the `docker_volume` resources and their data.
- `prevent_destroy` is intentionally omitted so `preview`/`preprod` environments can be torn down cleanly; for production `mainnet`, add `lifecycle { prevent_destroy = true }` to database/chain volumes or back them up externally before any destroy operation.

## 6. Environment & Workspace Isolation

Each environment (`environments/preview.tfvars`, `preprod.tfvars`, `mainnet.tfvars`) uses distinct container names, network names, and volume names prefixed by `<env>`.

Select a dedicated Terraform workspace per environment:

```bash
terraform workspace select -or-create preview
terraform workspace select -or-create preprod
terraform workspace select -or-create mainnet
```

- **State & locking limitations:** Workspaces create separate state files (`terraform.tfstate.d/<env>/terraform.tfstate`) sharing the `local` backend. The `local` backend uses OS advisory file locks (`flock`), which only protect against concurrent runs on the **same host filesystem**. If multiple engineers need concurrent `apply` access, migrate to a shared remote state backend with distributed locking.

## 7. Startup Dependencies & Health Checks

- **Terraform `depends_on` limitation:** `depends_on` orders `docker_container` creation (`cardano-node` + `postgres` → `cardano-db-sync` → `midnight-node` → `midnight-indexer`), but does **not** wait for in-container application readiness.
- **Docker Health Checks:**
  - `cardano-node`: `test -S /ipc/node.socket` (`30s` interval, `10s` timeout, `10` retries, `120s` start period)
  - `postgres`: `pg_isready -U midnight -d cexplorer` (`15s` interval, `5s` timeout, `5` retries, `30s` start period)
  - `cardano-db-sync`: `test -S /ipc/node.socket && pgrep -f cardano-db-sync` (`30s` interval, `10s` timeout, `5` retries, `120s` start period)
  - `midnight-node`: `curl -sf http://127.0.0.1:9944/health` (`30s` interval, `10s` timeout, `5` retries, `60s` start period; verify `curl` availability in image)
  - `midnight-indexer`: `curl -sf http://127.0.0.1:8088/ready` (`30s` interval, `10s` timeout, `5` retries, `30s` start period)
- Use `./scripts/health-check.sh <env> --wait` to verify staged container health in dependency order without sleeping arbitrarily or blocking on full chain sync.

## 8. DB Sync Recovery Strategy (Production Rebuilds)

Full `cardano-db-sync` synchronization from genesis can take days on Mainnet. For production recovery:

1. **Cardano Chain-Data Snapshots (Mithril):** Bootstrap `cardano-node` into `<env>_cardano_node_db` using `mithril-client cardano-db download --include-ancillary` before starting `cardano-node` (reduces node sync from days to ~20 minutes).
2. **PostgreSQL & DB Sync State Snapshots:** Periodically snapshot both the PostgreSQL `cexplorer` database (`pg_dump -Fc` or `pg_basebackup` while `cardano-db-sync` is stopped cleanly with `SIGINT`) and the matching `<env>_cardano_db_sync_state` ledger state directory.
3. **Version Compatibility:** Always match snapshots to the exact `cardano-node` (`11.1.3`) and `cardano-db-sync` (`13.7.1.0`) schema/era versions; as noted in `running-db-sync.md`, major upgrades (e.g., Van Rossem) may require replaying rather than swapping binaries.
4. **Restore & Validation Procedure:**
   - Restore `<env>_cardano_node_db`, `<env>_postgres_data`, and `<env>_cardano_db_sync_state` **before** starting `cardano-db-sync`.
   - Start `cardano-node` and `postgres` first, verify `pg_isready` and `SELECT block_no, slot_no FROM block ORDER BY id DESC LIMIT 1;`, then start `cardano-db-sync` and wait for ≥99% sync before `midnight-node` verifies blocks.

## 9. Local Docker Security Limitations vs. Production

| Area | Implemented in Local Docker | Production Recommendation |
|---|---|---|
| Host Exposure | Bridge networks + `127.0.0.1:8088` bind | Host firewall (`ufw`/`nftables`), TLS-terminating reverse proxy |
| Secrets | `.env` / `upload` secret files (`0400`/`0600`) | External secret manager (HashiCorp Vault, KMS) + encrypted state |
| State & Locking | `local` backend (`flock`, single-host) | Encrypted remote state backend with distributed locking |
| Container Runtime | `no-new-privileges:true`, memory limits | Read-only rootfs where supported, non-root UIDs, image digest pinning |

---

## Automated Testing and Validation

### Prerequisites & Installation

- **Terraform** (`>= 1.6.0, < 2.0.0`)
- **TFLint** (for HCL linting): `curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash`
- **Checkov** (for static security scanning): `pip install checkov`
- **Docker daemon** (only required for `terraform plan` against live Docker; `fmt`, `validate`, `tflint`, `checkov`, and mocked `terraform test` run without a running Docker daemon).

### `terraform init` vs `terraform init -backend=false`

- Use **`terraform init -backend=false`** in CI linting/validation or offline/read-only checks where you only need provider/module resolution for `terraform validate` and `terraform test` without touching local state or backend configuration.
- Use **`terraform init`** (with backend enabled) when selecting workspaces (`terraform workspace select`) and running `terraform plan` or `terraform apply` against your local state file.

### Individual Test Commands

```bash
# 1. Formatting
cd infra && terraform fmt -check -recursive

# 2. Initialization & Validation (no Docker daemon required)
cd infra && terraform init -backend=false -input=false
cd infra && terraform validate

# 3. TFLint
cd infra && tflint --init && tflint --recursive

# 4. Checkov Security Scan (from repository root)
checkov -d infra --framework terraform

# 5. Terraform Native Functional Tests (mocked Docker provider)
cd infra && terraform test

# 6. Environment Plans (requires Docker daemon & TF_VAR_* secrets)
cd infra
terraform plan -var-file="environments/preview.tfvars"
terraform plan -var-file="environments/preprod.tfvars"
terraform plan -var-file="environments/mainnet.tfvars"
```

### Complete Test Automation Script

```bash
./infra/scripts/test.sh
```

The script runs all 7 stages in sequence, stops immediately on failure with a non-zero exit code, avoids printing secrets, and never runs `terraform apply` or `terraform destroy`.

### What Each Check Verifies & Known Limitations

- **`terraform fmt` / `validate`:** Enforces canonical HCL formatting and static syntax/type correctness across root and all 5 modules.
- **`tflint`:** Enforces `snake_case` naming, variable/output documentation, typed variables, and unused declaration checks via `.tflint.hcl`.
- **`checkov`:** Audits Terraform HCL for insecure container/network patterns and hard-coded secrets. Note that some Checkov Docker rules assume multi-tenant or host-hardened production environments and must be evaluated in context rather than blindly suppressed.
- **`terraform test` (`tests/infrastructure.tftest.hcl`):** Uses `mock_provider "docker"` to verify planned resource attributes across `preview`, `preprod`, and `mainnet` (PostgreSQL has zero published ports and only `db_internal`; `db_internal` and `indexer_internal` have `internal = true`; `midnight-node` publishes only `30333`; all 6 persistent volumes are environment-scoped; invalid `indexer_secret` fails validation; outputs never leak credentials). **Limitation:** Mocked `terraform test` validates planned HCL/resource configuration, not live container runtime startup or blockchain synchronization.

### Expected Passing Results

- `terraform fmt -check -recursive`: exit `0`, no output.
- `terraform validate`: `Success! The configuration is valid.`
- `tflint --recursive`: exit `0`, 0 issues.
- `checkov -d infra --framework terraform`: exit `0` (or documented non-applicable local Docker findings).
- `terraform test`: `Success! 4 passed, 0 failed.`
- `terraform plan` (`preview`, `preprod`, `mainnet`): exit `0`, `Plan: 21 to add, 0 to change, 0 to destroy.`

---

## CI/CD Architecture (GitHub Actions)

The workflow at [`.github/workflows/terraform.yml`](../.github/workflows/terraform.yml) automates validation, security scanning, testing, planning, and gated deployment for `preview`, `preprod`, and `mainnet` using **Docker only**.

### 1. Workflow Triggers & Job Flow

- **Pull Requests (`main`):**
  - Runs `validate` (`terraform fmt -check -recursive`, `terraform init -backend=false`, `terraform validate`, `tflint`, `checkov`, `terraform test`).
  - Runs `plan` matrix for `preview`, `preprod`, and `mainnet`, publishing the last 60 lines to `$GITHUB_STEP_SUMMARY` and uploading sanitized plan text (`terraform-plan-<env>`) as a 7-day artifact.
  - **Never runs `terraform apply` or `terraform destroy` on pull requests.**
- **Push to `main`:**
  - Runs `validate` and `plan`, then queues `deploy_preview` and `deploy_preprod` (gated by GitHub Environment approvals).
  - **`deploy_mainnet` never runs automatically on push/merge to `main`.**
- **Manual Dispatch (`workflow_dispatch`):**
  - Requires selecting `environment` (`preview`, `preprod`, `mainnet`) and `action` (`plan` or `apply`). Mainnet deployment can **only** be triggered manually with `environment=mainnet` and `action=apply`, followed by GitHub Environment approval.

### 2. Environment Configurations & Supplied Docs Scope

| Environment | Source of Truth | Confirmed Configuration | Missing / Requires Setup Before Apply |
|---|---|---|---|
| **PreProd** | Supplied Section 1 docs (`running-cardano-node.md`, `running-db-sync.md`, `midight-node.md`, `running-with-docker.md`) | `NETWORK="preprod"`, `CARDANO_SECURITY_PARAMETER=2160`, `postgres:17` (`cexplorer`/`midnight`), `cardano-node:11.1.3-amd64`, `cardano-db-sync:13.7.1.0`, `midnight-node:2.1.101-rc.2`, `indexer-standalone:latest` | `midnight_bootnodes` (empty `[]` in `preprod.tfvars`), `postgres_tls_host_dir` certs, persistent runner/Docker host |
| **Preview** | `midight-node.md` + `environments/preview.tfvars` | `CARDANO_SECURITY_PARAMETER=432`, Preview bootnode multiaddrs | Host-appropriate Postgres tuning, `postgres_tls_host_dir` certs, persistent runner/Docker host |
| **Mainnet** | `running-db-sync.md` + `midight-node.md` + `environments/mainnet.tfvars` | `CARDANO_SECURITY_PARAMETER=2160`, Mainnet Postgres tuning (`shared_buffers=16GB`, `maintenance_work_mem=4GB`, `max_parallel_maintenance_workers=4`, `effective_cache_size=48GB`) | `midnight_bootnodes` (empty `[]`), `postgres_tls_host_dir` certs, Mainnet storage/host sizing, persistent runner |

### 3. Required GitHub Environments, Variables & Secrets

Create three separate GitHub Environments (`preview`, `preprod`, `mainnet`) under **Settings → Environments**:

- **Protection Rules:**
  - `preview`: Required reviewers (1+) before `apply`.
  - `preprod`: Required reviewers (1+), restrict deployment branch to `main`.
  - `mainnet`: Strongest protection — multiple required reviewers, wait timer (recommended), restrict deployment branch to `main`, manual `workflow_dispatch` only.
- **Environment Secrets (configured separately per environment, never shared):**
  - `POSTGRES_PASSWORD`
  - `INDEXER_SECRET` (64-hex-char secret)
  - `BLOCKFROST_API_KEY` (or non-empty placeholder)
- **Environment Variables:**
  - `ENABLE_PERSISTENT_APPLY`: Set to `"true"` **only** when a persistent Docker target is configured; otherwise deployment jobs safely run `terraform plan` only.
  - `RUNNER_LABEL`: e.g., `self-hosted` (defaults to `ubuntu-latest` for plan-only).
  - `DOCKER_HOST`: Target Docker socket/endpoint (defaults to `unix:///var/run/docker.sock`).

### 4. Docker Daemon, Runner & Local State Limitations in CI

- **GitHub-hosted (`ubuntu-latest`) runners are ephemeral:** They run their own isolated Docker daemon and discard all containers, volumes, and local `terraform.tfstate` files when the job ends. They **cannot** deploy to your persistent Docker host.
- **Persistent deployments require a self-hosted runner** (or explicitly reachable Docker host) with:
  - Persistent disk for Docker volumes and `infra/terraform.tfstate.d/<env>/terraform.tfstate`.
  - `concurrency:` groups per environment (`deploy-preview`, `deploy-preprod`, `deploy-mainnet` with `cancel-in-progress: false`) to prevent concurrent `apply` corruption on the `local` backend.
- **Current status:** Until `ENABLE_PERSISTENT_APPLY="true"` and a persistent self-hosted runner are configured in each GitHub Environment, all three environments operate in **safe plan-only mode** in GitHub Actions.

### 5. Reviewing Plans & Deployment Results

1. Open the GitHub Actions workflow run for your PR or push.
2. Review the **Summary** tab (`$GITHUB_STEP_SUMMARY`) for each environment's plan output, or download the `terraform-plan-<env>` artifact.
3. For `deploy_*` jobs, review the pending **Environment approval** prompt before approving `apply`.
