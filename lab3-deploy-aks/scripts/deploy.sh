#!/usr/bin/env bash
set -euo pipefail

# Lab 3: Deploy AKS Cluster (Streamlined)
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

# Required variables (lab3 naming)
AKS_LOCATION="${AKS_LOCATION:-australiaeast}"
AKS_RG="${AKS_RG:-rg-aks-lab3-aue}"  # rg-<service>-lab3-<shortregion>
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-aks-lab3}"  # aks-lab3
AKS_NODE_SIZE="${AKS_NODE_SIZE:-Standard_D2s_v3}"  # fallback logic below if disallowed
AKS_NODE_COUNT="${AKS_NODE_COUNT:-3}"

# Create resource group if needed
if ! az group show -n "$AKS_RG" >/dev/null 2>&1; then
  log "Creating resource group $AKS_RG in $AKS_LOCATION"
  az group create -n "$AKS_RG" -l "$AKS_LOCATION" >/dev/null
  pass "Resource group created"
else
  pass "Resource group $AKS_RG exists"
fi

# Create AKS cluster if needed
if ! az aks show -g "$AKS_RG" -n "$AKS_CLUSTER_NAME" >/dev/null 2>&1; then
  log "Creating AKS cluster $AKS_CLUSTER_NAME in $AKS_LOCATION (size: $AKS_NODE_SIZE)"
  set +e
  create_output=$(az aks create \
    --resource-group "$AKS_RG" \
    --name "$AKS_CLUSTER_NAME" \
    --location "$AKS_LOCATION" \
    --node-count "$AKS_NODE_COUNT" \
    --node-vm-size "$AKS_NODE_SIZE" \
    --enable-managed-identity \
    --generate-ssh-keys \
    --network-plugin azure \
    --output none 2>&1)
  create_rc=$?
  set -e
  if [[ $create_rc -ne 0 ]]; then
    if echo "$create_output" | grep -qi "not allowed"; then
      err "Primary VM size $AKS_NODE_SIZE disallowed; retrying with Standard_B2s"
      AKS_NODE_SIZE="Standard_B2s"
      az aks create \
        --resource-group "$AKS_RG" \
        --name "$AKS_CLUSTER_NAME" \
        --location "$AKS_LOCATION" \
        --node-count "$AKS_NODE_COUNT" \
        --node-vm-size "$AKS_NODE_SIZE" \
        --enable-managed-identity \
        --generate-ssh-keys \
        --network-plugin azure \
        --output none || fail "az aks create failed with fallback size $AKS_NODE_SIZE"
      pass "AKS cluster created with fallback size $AKS_NODE_SIZE"
    else
      echo "$create_output" >&2
      fail "az aks create failed"
    fi
  else
    pass "AKS cluster created"
  fi
else
  pass "AKS cluster $AKS_CLUSTER_NAME already exists"
fi

# Get credentials
log "Fetching kubeconfig credentials"
az aks get-credentials -g "$AKS_RG" -n "$AKS_CLUSTER_NAME" --overwrite-existing --admin >/dev/null || fail "Failed to get credentials"
pass "Credentials merged"

log "Deployment complete. Run ./scripts/validate.sh to verify."