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

NAMESPACE="${NAMESPACE:-nextjs-sample}"
APP_NAME="nextjs-sample"

if ! command -v oc >/dev/null 2>&1 || ! oc whoami >/dev/null 2>&1; then
  fail "Not logged into OpenShift (oc)."; fi

log "Validating deployment in namespace: $NAMESPACE"

oc get namespace "$NAMESPACE" >/dev/null 2>&1 || fail "Namespace $NAMESPACE missing"
pass "Namespace exists"

oc get configmap sample-app-config -n "$NAMESPACE" >/dev/null 2>&1 || fail "ConfigMap sample-app-config missing"
pass "ConfigMap exists"

oc get deployment "$APP_NAME" -n "$NAMESPACE" >/dev/null 2>&1 || fail "Deployment $APP_NAME missing"
pass "Deployment exists"

READY=$(oc get deployment "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
DESIRED=$(oc get deployment "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
[[ "$READY" == "$DESIRED" ]] || fail "Only $READY/$DESIRED pods ready"
pass "All $READY pods ready"

oc get service "$APP_NAME" -n "$NAMESPACE" >/dev/null 2>&1 || fail "Service missing"
pass "Service exists"

oc get route "$APP_NAME" -n "$NAMESPACE" >/dev/null 2>&1 || fail "Route missing"
pass "Route exists"

HOST=$(oc get route "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.host}')
URL="http://$HOST/api/health"
log "Testing health endpoint: $URL"
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$URL")
[[ "$CODE" == "200" ]] || fail "Health check returned $CODE"
pass "Health endpoint OK (200)"

pass "Validation complete"

