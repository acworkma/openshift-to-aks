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
  export $(grep -v '^#' .env | xargs -d '\n' 2>/dev/null) || true
fi

NAMESPACE="${NAMESPACE:-sample-app}"
APP_NAME="${APP_NAME:-sample-app}"

# Detect CLI
if command -v oc >/dev/null 2>&1 && oc whoami >/dev/null 2>&1; then
  CLI="oc"
  CLUSTER_TYPE="openshift"
elif command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
  CLI="kubectl"
  CLUSTER_TYPE="kubernetes"
else
  fail "No cluster connection found"
fi

log "Validating deployment in namespace: $NAMESPACE"

# Check namespace exists
if ! $CLI get namespace "$NAMESPACE" >/dev/null 2>&1; then
  fail "Namespace $NAMESPACE does not exist"
fi
pass "Namespace exists"

# Check ConfigMap
if ! $CLI get configmap sample-app-config -n "$NAMESPACE" >/dev/null 2>&1; then
  fail "ConfigMap sample-app-config not found"
fi
pass "ConfigMap exists"

# Check Deployment
if ! $CLI get deployment "$APP_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  fail "Deployment $APP_NAME not found"
fi
pass "Deployment exists"

# Check replicas
READY_REPLICAS=$($CLI get deployment "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
DESIRED_REPLICAS=$($CLI get deployment "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
if [[ "$READY_REPLICAS" != "$DESIRED_REPLICAS" ]]; then
  fail "Only $READY_REPLICAS/$DESIRED_REPLICAS pods ready"
fi
pass "All $READY_REPLICAS pods ready"

# Check Service
if ! $CLI get service "$APP_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  fail "Service $APP_NAME not found"
fi
pass "Service exists"

# Check Route/Ingress
if [[ "$CLUSTER_TYPE" == "openshift" ]]; then
  if ! $CLI get route "$APP_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    fail "Route $APP_NAME not found"
  fi
  pass "Route exists"
  
  ROUTE_URL=$($CLI get route "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.host}')
  log "Testing endpoint: http://$ROUTE_URL"
  if curl -sf "http://$ROUTE_URL" >/dev/null 2>&1; then
    pass "Application endpoint is accessible"
  else
    err "Application endpoint not accessible (may still be starting)"
  fi
else
  if ! $CLI get ingress "$APP_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    fail "Ingress $APP_NAME not found"
  fi
  pass "Ingress exists"
  log "Test with: kubectl port-forward -n $NAMESPACE svc/$APP_NAME 8080:80"
fi

pass "Validation complete - all checks passed!"
