#!/usr/bin/env bash
set -euo pipefail

# Automated Terraform testing and validation script.
# Never runs `terraform apply` or `terraform destroy`.
# Never prints secret values.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${INFRA_DIR}/.." && pwd)"

# Use non-secret dummy values for plan/test only if not already set in environment
export TF_VAR_postgres_password="${TF_VAR_postgres_password:-test-only-dummy-password}"
export TF_VAR_indexer_secret="${TF_VAR_indexer_secret:-0000000000000000000000000000000000000000000000000000000000000000}"
export TF_VAR_blockfrost_api_key="${TF_VAR_blockfrost_api_key:-dummy-not-using-spo}"

step() {
  echo ""
  echo "==> $1"
}

fail() {
  echo "[FAIL] $1" >&2
  exit 1
}

cd "${INFRA_DIR}"

step "1. Terraform Formatting Check"
terraform fmt -check -recursive || fail "Terraform files are not formatted. Run: terraform fmt -recursive"

step "2. Terraform Initialization (backend=false)"
terraform init -backend=false -input=false || fail "Terraform init failed"

step "3. Terraform Validation"
terraform validate || fail "Terraform validate failed"

step "4. TFLint"
if command -v tflint >/dev/null 2>&1; then
  tflint --init || fail "tflint --init failed"
  tflint --recursive || fail "tflint --recursive found linting issues"
else
  fail "tflint is not installed. See infra/README.md for installation instructions."
fi

step "5. Checkov Security Scan"
if command -v checkov >/dev/null 2>&1; then
  (cd "${REPO_ROOT}" && checkov -d infra --framework terraform) || fail "Checkov reported security findings"
else
  fail "checkov is not installed. See infra/README.md for installation instructions."
fi

step "6. Terraform Native Functional Tests"
terraform test -no-color || fail "terraform test failed"

step "7. Terraform Plans (preview, preprod, mainnet)"
for env in preview preprod mainnet; do
  echo "--- Planning ${env} ---"
  terraform plan -input=false -no-color -var-file="environments/${env}.tfvars" >/dev/null || fail "terraform plan failed for ${env}"
  echo "[OK] ${env} plan succeeded"
done

echo ""
echo "[PASS] All Terraform automated checks succeeded."
