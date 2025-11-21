#!/usr/bin/env bash
set -euo pipefail

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
pass() { echo "[PASS] $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_ROOT"

if [[ -f .env ]]; then
  export $(grep -v '^#' .env | xargs -d '\n' 2>/dev/null) || true
fi

NAMESPACE="${NAMESPACE:-nextjs-sample}"

if ! command -v oc >/dev/null 2>&1 || ! oc whoami >/dev/null 2>&1; then
  err "OpenShift 'oc' CLI not logged in. Run 'oc login' first."; exit 1; fi

log "Ensuring project $NAMESPACE exists"
oc new-project "$NAMESPACE" 2>/dev/null || oc project "$NAMESPACE" >/dev/null

log "Applying ConfigMap"
oc apply -f configmap.yaml -n "$NAMESPACE"
log "Applying Deployment"
oc apply -f deployment.yaml -n "$NAMESPACE"
log "Applying Service"
oc apply -f service.yaml -n "$NAMESPACE"
log "Applying Route"
oc apply -f route.yaml -n "$NAMESPACE"

log "Waiting for pods"
oc wait --for=condition=ready pod -l app=nextjs-sample -n "$NAMESPACE" --timeout=180s || { err "Pods did not become ready"; oc get pods -n "$NAMESPACE"; exit 1; }

ROUTE_URL=$(oc get route nextjs-sample -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || true)
pass "Deployment complete"
[[ -n "$ROUTE_URL" ]] && log "Application URL: http://$ROUTE_URL"

