#!/usr/bin/env bash
set -euo pipefail

# Health-check and staged readiness verification for the 5-container Docker stack.
# Usage:
#   ./scripts/health-check.sh <preview|preprod|mainnet>          # one-shot status report
#   ./scripts/health-check.sh <preview|preprod|mainnet> --wait   # wait in dependency order

ENV="${1:-preview}"
MODE="${2:-}"
INDEXER_PORT="${INDEXER_PORT:-8088}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-36}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"

wait_for_healthy() {
  local container="$1"
  local attempt=1

  while (( attempt <= MAX_ATTEMPTS )); do
    local state
    state="$(docker inspect --format '{{.State.Status}}:{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${container}" 2>/dev/null || echo 'missing:none')"
    if [[ "${state}" == "running:healthy" ]]; then
      echo "[OK] ${container} is running and healthy"
      return 0
    fi
    if (( attempt == MAX_ATTEMPTS )); then
      echo "[FAIL] ${container} did not become healthy (last state: ${state})" >&2
      return 1
    fi
    sleep "${POLL_INTERVAL}"
    ((attempt++))
  done
}

if [[ "${MODE}" == "--wait" ]]; then
  # Dependency sequence:
  #   1. Cardano Node + PostgreSQL -> 2. Cardano DB Sync -> 3. Midnight Node -> 4. Midnight Indexer
  wait_for_healthy "${ENV}-cardano-node"
  wait_for_healthy "${ENV}-postgres"
  wait_for_healthy "${ENV}-cardano-db-sync"
  wait_for_healthy "${ENV}-midnight-node"
  wait_for_healthy "${ENV}-midnight-indexer"
fi

CONTAINERS=(
  "${ENV}-cardano-node"
  "${ENV}-postgres"
  "${ENV}-cardano-db-sync"
  "${ENV}-midnight-node"
  "${ENV}-midnight-indexer"
)

echo "=== Container Health Status (${ENV}) ==="
for c in "${CONTAINERS[@]}"; do
  status="$(docker inspect --format '{{.State.Status}} / {{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$c" 2>/dev/null || echo 'not-found')"
  printf "%-30s %s\n" "$c" "$status"
done

echo ""
echo "=== Midnight Indexer Endpoints ==="
curl -sf "http://127.0.0.1:${INDEXER_PORT}/live" && echo " (/live OK)" || echo "/live not ready"
curl -sf "http://127.0.0.1:${INDEXER_PORT}/ready" && echo " (/ready OK)" || echo "/ready not ready"
