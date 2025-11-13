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
APP_NAME="${APP_NAME:-sample-app}"
EXPORT_DIR="${EXPORT_DIR:-exported}"

# Detect CLI
if command -v oc >/dev/null 2>&1 && oc whoami >/dev/null 2>&1; then
  CLI="oc"
elif command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
  CLI="kubectl"
else
  echo "[ERROR] No cluster connection found"
  exit 1
fi

log "Exporting configuration from namespace: $NAMESPACE"

mkdir -p "$EXPORT_DIR"

log "Exporting deployment..."
$CLI get deployment "$APP_NAME" -n "$NAMESPACE" -o yaml | \
  grep -v '^\s*resourceVersion:' | \
  grep -v '^\s*uid:' | \
  grep -v '^\s*selfLink:' | \
  grep -v '^\s*creationTimestamp:' > "$EXPORT_DIR/${APP_NAME}-deployment.yaml"

log "Exporting service..."
$CLI get service "$APP_NAME" -n "$NAMESPACE" -o yaml | \
  grep -v '^\s*resourceVersion:' | \
  grep -v '^\s*uid:' | \
  grep -v '^\s*selfLink:' | \
  grep -v '^\s*creationTimestamp:' | \
  grep -v '^\s*clusterIP:' | \
  grep -v '^\s*clusterIPs:' > "$EXPORT_DIR/${APP_NAME}-service.yaml"

log "Exporting configmap..."
$CLI get configmap sample-app-config -n "$NAMESPACE" -o yaml | \
  grep -v '^\s*resourceVersion:' | \
  grep -v '^\s*uid:' | \
  grep -v '^\s*selfLink:' | \
  grep -v '^\s*creationTimestamp:' > "$EXPORT_DIR/${APP_NAME}-configmap.yaml"

if $CLI get route "$APP_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  log "Exporting route..."
  $CLI get route "$APP_NAME" -n "$NAMESPACE" -o yaml | \
    grep -v '^\s*resourceVersion:' | \
    grep -v '^\s*uid:' | \
    grep -v '^\s*selfLink:' | \
    grep -v '^\s*creationTimestamp:' > "$EXPORT_DIR/${APP_NAME}-route.yaml"
fi

pass "Configuration exported to: $EXPORT_DIR/"
ls -lh "$EXPORT_DIR"
