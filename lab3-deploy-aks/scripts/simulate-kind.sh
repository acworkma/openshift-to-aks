#!/usr/bin/env bash
set -euo pipefail

# Lab 3: Simulate AKS locally with Kind for testing scripts without Azure quotas.

log() { echo "[INFO] $*"; }
pass() { echo "[PASS] $*"; }
err() { echo "[ERROR] $*" >&2; }
fail() { err "$*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_ROOT"

if [[ -f .env ]]; then
  export $(grep -v '^#' .env | xargs -d '\n' 2>/dev/null) || true
fi

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-aks-sim}"
SIM_NODE_COUNT="${SIM_NODE_COUNT:-3}" # 1 control-plane + (SIM_NODE_COUNT-1) workers

if ! command -v kind >/dev/null 2>&1; then
  fail "Kind not installed. Install with: curl -Lo kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64 && chmod +x kind && sudo mv kind /usr/local/bin/"
fi

if kubectl config get-contexts -o name | grep -q "kind-${KIND_CLUSTER_NAME}"; then
  pass "Kind cluster kind-${KIND_CLUSTER_NAME} already exists; skipping creation"
  exit 0
fi

log "Creating Kind cluster '$KIND_CLUSTER_NAME' simulating AKS (nodes: $SIM_NODE_COUNT)"

CONFIG_FILE=$(mktemp)
cat > "$CONFIG_FILE" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${KIND_CLUSTER_NAME}
nodes:
- role: control-plane
EOF

if (( SIM_NODE_COUNT > 1 )); then
  for i in $(seq 2 "$SIM_NODE_COUNT"); do
    cat >> "$CONFIG_FILE" <<EOF
- role: worker
EOF
  done
fi

kind create cluster --config "$CONFIG_FILE" >/dev/null
rm -f "$CONFIG_FILE"
pass "Kind cluster created"

log "Waiting for nodes to become Ready"
for i in {1..30}; do
  ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l || echo 0)
  total=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo 0)
  log "Ready nodes: $ready/$total (poll $i)"
  if [[ "$ready" == "$total" && "$total" -gt 0 ]]; then
    break
  fi
  sleep 3
done

kubectl get nodes
pass "Simulation complete. Run: SIMULATE_LOCAL=true ./scripts/validate.sh"