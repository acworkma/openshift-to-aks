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

NAMESPACE="${NAMESPACE:-nextjs-sample}"

if ! command -v oc >/dev/null 2>&1 || ! oc whoami >/dev/null 2>&1; then
  log "Not logged into OpenShift - nothing to clean up."; exit 0; fi

log "Cleaning up namespace: $NAMESPACE"
oc get namespace "$NAMESPACE" >/dev/null 2>&1 || { log "Namespace absent"; exit 0; }
oc delete namespace "$NAMESPACE" --ignore-not-found=true --wait=true
pass "Cleanup complete"

