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
AKS_RG="${AKS_RG:-rg-aks-lab3-aue}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-aks-lab3}"
AKS_NODE_SIZE="${AKS_NODE_SIZE:-Standard_D2s_v3}"
AKS_NODE_COUNT="${AKS_NODE_COUNT:-3}"
ACR_NAME="${ACR_NAME:-acrlab3example}"
ACR_SKU="${ACR_SKU:-Standard}"

# Create resource group if needed
if ! az group show -n "$AKS_RG" >/dev/null 2>&1; then
  log "Creating resource group $AKS_RG in $AKS_LOCATION"
  az group create -n "$AKS_RG" -l "$AKS_LOCATION" >/dev/null
  pass "Resource group created"
else
  pass "Resource group $AKS_RG exists"
fi


# Deploy AKS and ACR using Bicep
log "Deploying AKS and ACR via Bicep..."
DEPLOY_OUT=$(az deployment group create \
  --resource-group "$AKS_RG" \
  --template-file infrastructure/main.bicep \
  --parameters \
    clusterName="$AKS_CLUSTER_NAME" \
    location="$AKS_LOCATION" \
    nodeCount="$AKS_NODE_COUNT" \
    nodeVMSize="$AKS_NODE_SIZE" \
    acrName="$ACR_NAME" \
    acrSku="$ACR_SKU" \
    enableAutoScaling=true \
    minNodeCount=1 \
    maxNodeCount=5 \
    networkPlugin=azure \
    enableRBAC=true \
    dnsPrefix="${AKS_CLUSTER_NAME}-dns" \
    kubernetesVersion="1.33" \
  --query properties.outputs \
  --output json)
if [[ -z "$DEPLOY_OUT" ]]; then
  fail "Bicep deployment failed"
fi
pass "Bicep deployment succeeded"

# Parse outputs using jq for reliability
ACR_NAME=$(echo "$DEPLOY_OUT" | jq -r '.acrName.value // empty')
ACR_LOGIN_SERVER=$(echo "$DEPLOY_OUT" | jq -r '.acrLoginServer.value // empty')
ACR_ADMIN_USERNAME=$(echo "$DEPLOY_OUT" | jq -r '.acrAdminUsername.value // empty')
ACR_ADMIN_PASSWORD=$(echo "$DEPLOY_OUT" | jq -r '.acrAdminPassword.value // empty')

# Write outputs to .env (append or update)
ENV_FILE=".env"
touch "$ENV_FILE"
sed -i "/^ACR_NAME=/d;/^ACR_LOGIN_SERVER=/d;/^ACR_ADMIN_USERNAME=/d;/^ACR_ADMIN_PASSWORD=/d" "$ENV_FILE"
{
  echo "ACR_NAME=$ACR_NAME"
  echo "ACR_LOGIN_SERVER=$ACR_LOGIN_SERVER"
  echo "ACR_ADMIN_USERNAME=$ACR_ADMIN_USERNAME"
  echo "ACR_ADMIN_PASSWORD=$ACR_ADMIN_PASSWORD"
} >> "$ENV_FILE"
pass "ACR outputs written to $ENV_FILE"

# Get AKS credentials
log "Fetching kubeconfig credentials"
az aks get-credentials -g "$AKS_RG" -n "$AKS_CLUSTER_NAME" --overwrite-existing --admin >/dev/null || fail "Failed to get credentials"
pass "Credentials merged"

log "Deployment complete. Run ./scripts/validate.sh to verify."