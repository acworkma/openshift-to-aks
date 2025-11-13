#!/usr/bin/env bash
set -euo pipefail

log() { echo "[INFO] $*"; }
pass() { echo "[PASS] $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_ROOT"

if [[ -f .env ]]; then
  export $(grep -v '^#' .env | xargs -d '\n' 2>/dev/null) || true
fi

NAMESPACE="${NAMESPACE:-sample-app}"

# Detect CLI
if command -v oc >/dev/null 2>&1 && oc whoami >/dev/null 2>&1; then
  CLI="oc"
elif command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
  CLI="kubectl"
else
  log "No cluster connection found - nothing to clean up"
  exit 0
fi

log "Cleaning up resources in namespace: $NAMESPACE"

if ! $CLI get namespace "$NAMESPACE" >/dev/null 2>&1; then
  log "Namespace $NAMESPACE does not exist - nothing to clean up"
  exit 0
fi

log "Deleting namespace $NAMESPACE (this will remove all resources)..."
$CLI delete namespace "$NAMESPACE" --ignore-not-found=true --wait=true

pass "Cleanup complete!"
