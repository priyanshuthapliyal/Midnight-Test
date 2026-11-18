#!/usr/bin/env bash
set -euo pipefail

# Initialize Terraform, select workspace, and optionally wait for staged container readiness.
# Usage:
#   ./scripts/bootstrap.sh <preview|preprod|mainnet>
#   ./scripts/bootstrap.sh <preview|preprod|mainnet> --wait

ENV="${1:-preview}"
MODE="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

case "${ENV}" in
  preview|preprod|mainnet) ;;
  *)
    echo "Error: environment must be preview, preprod, or mainnet." >&2
    exit 1
    ;;
esac

cd "${INFRA_DIR}"
terraform init -input=false
terraform workspace select -or-create "${ENV}"
echo "Initialized Terraform workspace: ${ENV}"

if [[ "${MODE}" == "--wait" ]]; then
  echo "Waiting for staged container readiness in dependency order..."
  "${SCRIPT_DIR}/health-check.sh" "${ENV}" --wait
fi
