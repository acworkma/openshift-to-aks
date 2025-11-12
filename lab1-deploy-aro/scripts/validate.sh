#!/usr/bin/env bash
set -euo pipefail

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; exit 1; }

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
  fail "Azure CLI (az) not found"
fi

log "Validating ARO cluster existence..."
if ! az aro show -g "$ARO_RG" -n "$CLUSTER_NAME" >/dev/null 2>&1; then
  fail "ARO cluster '$CLUSTER_NAME' not found in resource group '$ARO_RG'"
fi

CONSOLE_URL=$(az aro show -g "$ARO_RG" -n "$CLUSTER_NAME" --query consoleProfile.url -o tsv || true)
API_URL=$(az aro show -g "$ARO_RG" -n "$CLUSTER_NAME" --query apiserverProfile.url -o tsv || true)

if [[ -z "$CONSOLE_URL" || -z "$API_URL" ]]; then
  fail "Cluster URLs not yet available (provisioning still in progress)"
fi
pass "Console URL reachable value: $CONSOLE_URL"
pass "API Server URL value: $API_URL"

# Optional deeper check if oc is available
if command -v oc >/dev/null 2>&1; then
  log "Attempting optional oc login (will skip if credentials unavailable)..."
  if KUBEADMIN_PASSWD=$(az aro list-credentials -g "$ARO_RG" -n "$CLUSTER_NAME" --query kubeadminPassword -o tsv 2>/dev/null); then
    if oc login "$API_URL" -u kubeadmin -p "$KUBEADMIN_PASSWD" --insecure-skip-tls-verify >/dev/null 2>&1; then
      NODE_COUNT=$(oc get nodes --no-headers 2>/dev/null | wc -l || echo 0)
      pass "oc login successful; nodes detected: $NODE_COUNT"
    else
      log "oc login attempt failed (cluster may still be provisioning)."
    fi
  else
    log "Could not retrieve kubeadmin credentials yet. Skipping oc checks."
  fi
fi

pass "Validation PASS"
