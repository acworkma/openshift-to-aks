#!/usr/bin/env bash
set -euo pipefail

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
pass() { echo "[PASS] $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_ROOT"

# Load .env if present
if [[ -f .env ]]; then
  export $(grep -v '^#' .env | xargs -d '\n' 2>/dev/null) || true
fi

NAMESPACE="${NAMESPACE:-sample-app}"
APP_NAME="${APP_NAME:-sample-app}"

# Detect cluster type
if command -v oc >/dev/null 2>&1 && oc whoami >/dev/null 2>&1; then
  CLI="oc"
  CLUSTER_TYPE="openshift"
  log "Detected OpenShift cluster"
elif command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
  CLI="kubectl"
  CLUSTER_TYPE="kubernetes"
  log "Detected Kubernetes cluster"
else
  err "No cluster connection found. Login with 'oc login' or configure kubectl context"
  exit 1
fi

log "Creating namespace/project: $NAMESPACE"
if [[ "$CLUSTER_TYPE" == "openshift" ]]; then
  oc new-project "$NAMESPACE" 2>/dev/null || oc project "$NAMESPACE"
else
  kubectl create namespace "$NAMESPACE" 2>/dev/null || true
  kubectl config set-context --current --namespace="$NAMESPACE"
fi

log "Deploying ConfigMap..."
$CLI apply -f configmap.yaml -n "$NAMESPACE"

log "Deploying application..."
$CLI apply -f deployment.yaml -n "$NAMESPACE"

log "Deploying service..."
$CLI apply -f service.yaml -n "$NAMESPACE"

log "Deploying route/ingress..."
if [[ "$CLUSTER_TYPE" == "openshift" ]]; then
  $CLI apply -f route.yaml -n "$NAMESPACE"
else
  # Convert Route to Ingress for Kubernetes
  log "Converting OpenShift Route to Kubernetes Ingress..."
  cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $APP_NAME
  labels:
    app: $APP_NAME
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: ${APP_NAME}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: $APP_NAME
            port:
              number: 80
EOF
fi

log "Waiting for pods to be ready..."
$CLI wait --for=condition=ready pod -l app="$APP_NAME" -n "$NAMESPACE" --timeout=120s || {
  err "Pods failed to become ready"
  $CLI get pods -n "$NAMESPACE"
  exit 1
}

pass "Deployment complete!"
log "Resources in namespace $NAMESPACE:"
$CLI get all -n "$NAMESPACE"

if [[ "$CLUSTER_TYPE" == "openshift" ]]; then
  ROUTE_URL=$($CLI get route "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
  if [[ -n "$ROUTE_URL" ]]; then
    log "Application URL: http://$ROUTE_URL"
  fi
else
  log "Application accessible at: http://${APP_NAME}.local (add to /etc/hosts)"
  log "Or use port-forward: kubectl port-forward -n $NAMESPACE svc/$APP_NAME 8080:80"
fi
