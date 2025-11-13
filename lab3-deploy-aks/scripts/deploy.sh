#!/usr/bin/env bash
set -euo pipefail

# Lab 3: Deploy AKS Cluster
# Idempotent: skips creation if cluster already exists.

log() { echo "[INFO] $*"; }
pass() { echo "[PASS] $*"; }
err() { echo "[ERROR] $*" >&2; }
fail() { err "$*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_ROOT"

# Load .env if present
if [[ -f .env ]]; then
  export $(grep -v '^#' .env | xargs -d '\n' 2>/dev/null) || true
fi

AKS_LOCATION="${AKS_LOCATION:-eastus}"
AKS_RG="${AKS_RG:-rg-aks-lab-${AKS_LOCATION}}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-aks-cluster}"
AKS_NODE_SIZE="${AKS_NODE_SIZE:-Standard_D2s_v3}"
AKS_NODE_COUNT="${AKS_NODE_COUNT:-3}"
AKS_ENABLE_AUTOSCALER="${AKS_ENABLE_AUTOSCALER:-true}"
AKS_MIN_COUNT="${AKS_MIN_COUNT:-1}"
AKS_MAX_COUNT="${AKS_MAX_COUNT:-5}"
AKS_VERSION="${AKS_VERSION:-}"  # blank means latest
AKS_NETWORK_PLUGIN="${AKS_NETWORK_PLUGIN:-azure}" # azure | kubenet
AKS_NETWORK_POLICY="${AKS_NETWORK_POLICY:-}"      # azure | calico (optional)
AKS_ENABLE_MONITORING="${AKS_ENABLE_MONITORING:-false}" # true installs OMS agent
AKS_ENABLE_RBAC="${AKS_ENABLE_RBAC:-true}"
AKS_IDENTITY_TYPE="${AKS_IDENTITY_TYPE:-SystemAssigned}" # SystemAssigned | UserAssigned

ensure_group() {
  if az group show -n "$AKS_RG" >/dev/null 2>&1; then
    pass "Resource group $AKS_RG exists"
  else
    log "Creating resource group $AKS_RG in $AKS_LOCATION"
    az group create -n "$AKS_RG" -l "$AKS_LOCATION" >/dev/null
    pass "Resource group created"
  fi
}

resolve_version() {
  if [[ -n "$AKS_VERSION" ]]; then
    pass "Using specified Kubernetes version: $AKS_VERSION"
    return
  fi
  local ver
  ver=$(az aks get-versions -l "$AKS_LOCATION" --query "orchestrators[?isPreview==null].orchestratorVersion" -o tsv 2>/dev/null | sort -V | tail -1)
  if [[ -z "$ver" ]]; then
    fail "Unable to resolve latest stable AKS version"
  fi
  AKS_VERSION="$ver"
  pass "Resolved latest stable AKS version: $AKS_VERSION"
}

cluster_exists() {
  az aks show -g "$AKS_RG" -n "$AKS_CLUSTER_NAME" >/dev/null 2>&1
}

create_cluster() {
  local autoscaler_flags=""
  if [[ "$AKS_ENABLE_AUTOSCALER" == "true" ]]; then
    autoscaler_flags="--enable-cluster-autoscaler --min-count $AKS_MIN_COUNT --max-count $AKS_MAX_COUNT"
  fi
  local net_policy_flag=""
  if [[ -n "$AKS_NETWORK_POLICY" ]]; then
    net_policy_flag="--network-policy $AKS_NETWORK_POLICY"
  fi
  local monitoring_flag=""
  if [[ "$AKS_ENABLE_MONITORING" == "true" ]]; then
    monitoring_flag="--enable-addons monitoring"
  fi

  log "Creating AKS cluster $AKS_CLUSTER_NAME (nodes: $AKS_NODE_COUNT size: $AKS_NODE_SIZE version: $AKS_VERSION)"
  az aks create \
    --resource-group "$AKS_RG" \
    --name "$AKS_CLUSTER_NAME" \
    --location "$AKS_LOCATION" \
    --node-count "$AKS_NODE_COUNT" \
    --node-vm-size "$AKS_NODE_SIZE" \
    --kubernetes-version "$AKS_VERSION" \
    --network-plugin "$AKS_NETWORK_PLUGIN" \
    $net_policy_flag \
    --enable-managed-identity \
    $( [[ "$AKS_ENABLE_RBAC" == "true" ]] && echo "--enable-rbac" || echo "--disable-rbac" ) \
    $autoscaler_flags \
    $monitoring_flag \
    --output none || fail "az aks create failed"
  pass "Cluster create command submitted"
}

wait_cluster() {
  log "Waiting for cluster provisioning to succeed..."
  for i in {1..40}; do
    local state
    state=$(az aks show -g "$AKS_RG" -n "$AKS_CLUSTER_NAME" --query "provisioningState" -o tsv 2>/dev/null || echo "missing")
    if [[ "$state" == "Succeeded" ]]; then
      pass "Cluster provisioning state: Succeeded"
      return
    fi
    if [[ "$state" == "Failed" ]]; then
      fail "Cluster provisioning failed"
    fi
    log "Provisioning state: $state (poll $i)"
    sleep 30
  done
  fail "Timed out waiting for cluster provisioning"
}

get_credentials() {
  log "Fetching kubeconfig credentials (merging)..."
  az aks get-credentials -g "$AKS_RG" -n "$AKS_CLUSTER_NAME" --overwrite-existing --admin >/dev/null || fail "Failed to get credentials"
  pass "Credentials merged"
}

post_checks() {
  log "Validating cluster access (kubectl get nodes)"
  kubectl get nodes || fail "kubectl cannot access cluster"
  pass "kubectl access OK"
}

ensure_group
resolve_version
if cluster_exists; then
  pass "Cluster $AKS_CLUSTER_NAME already exists; skipping creation"
else
  create_cluster
  wait_cluster
fi
get_credentials
post_checks

controlPlaneFQDN=$(az aks show -g "$AKS_RG" -n "$AKS_CLUSTER_NAME" --query "fqdn" -o tsv 2>/dev/null || echo "")
if [[ -n "$controlPlaneFQDN" ]]; then
  log "API Server FQDN: $controlPlaneFQDN"
fi

pass "AKS deployment complete"