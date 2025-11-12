#!/usr/bin/env bash
set -euo pipefail

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
pass() { echo "[PASS] $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_ROOT"

if [[ -f .env ]]; then
  # shellcheck disable=SC2046
  export $(grep -v '^#' .env | xargs -d '\n') || true
fi

: "${ARO_RG?ARO_RG environment variable required}"
: "${CLUSTER_NAME?CLUSTER_NAME environment variable required}"

if ! command -v az >/dev/null 2>&1; then
  err "Azure CLI (az) not found"; exit 1
fi

log "Checking for existing ARO cluster '$CLUSTER_NAME'..."
if az aro show -g "$ARO_RG" -n "$CLUSTER_NAME" >/dev/null 2>&1; then
  log "Deleting ARO cluster (idempotent)..."
  az aro delete -g "$ARO_RG" -n "$CLUSTER_NAME" --yes --no-wait || true
  log "Cluster delete initiated (may take time)."
else
  log "Cluster not found; nothing to delete."
fi

log "Deleting resource group '$ARO_RG' (idempotent)..."
az group delete -n "$ARO_RG" --yes --no-wait || true

pass "Cleanup initiated. You can monitor with: az group show -n $ARO_RG or az aro show -g $ARO_RG -n $CLUSTER_NAME"
