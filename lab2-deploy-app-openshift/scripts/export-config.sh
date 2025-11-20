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
APP_NAME="nextjs-sample"
EXPORT_DIR="${EXPORT_DIR:-exported}"

if ! command -v oc >/dev/null 2>&1 || ! oc whoami >/dev/null 2>&1; then
  echo "[ERROR] Not logged into OpenShift"; exit 1; fi

log "Exporting configuration from namespace: $NAMESPACE"
mkdir -p "$EXPORT_DIR"

log "Exporting deployment"
oc get deployment "$APP_NAME" -n "$NAMESPACE" -o yaml > "$EXPORT_DIR/deployment.yaml"
log "Exporting service"
oc get service "$APP_NAME" -n "$NAMESPACE" -o yaml > "$EXPORT_DIR/service.yaml"
log "Exporting route"
oc get route "$APP_NAME" -n "$NAMESPACE" -o yaml > "$EXPORT_DIR/route.yaml" || true
log "Exporting configmap"
oc get configmap sample-app-config -n "$NAMESPACE" -o yaml > "$EXPORT_DIR/configmap.yaml"

pass "Export complete ($EXPORT_DIR)"

