#!/usr/bin/env bash
set -euo pipefail

# Lab 3: Cleanup AKS Cluster (Streamlined)
log() { echo "[INFO] $*"; }
pass() { echo "[PASS] $*"; }
err() { echo "[ERROR] $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_ROOT"

if [[ -f .env ]]; then
  export $(grep -v '^#' .env | xargs -d '\n' 2>/dev/null) || true
fi


AKS_LOCATION="${AKS_LOCATION:-australiaeast}"
AKS_RG="${AKS_RG:-rg-aks-lab3-aue}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-aks-lab3}"
ACR_NAME="${ACR_NAME:-acrlab3example}"
CLEANUP_DELETE_RG="${CLEANUP_DELETE_RG:-false}"

log "Starting cleanup for cluster $AKS_CLUSTER_NAME (RG: $AKS_RG)"


# Delete AKS cluster
if az aks show -g "$AKS_RG" -n "$AKS_CLUSTER_NAME" >/dev/null 2>&1; then
  log "Deleting AKS cluster (async)"
  az aks delete -g "$AKS_RG" -n "$AKS_CLUSTER_NAME" --yes --no-wait || err "Failed to start cluster deletion"
else
  log "Cluster does not exist"
fi

# Delete ACR
if az acr show -g "$AKS_RG" -n "$ACR_NAME" >/dev/null 2>&1; then
  log "Deleting ACR $ACR_NAME (async)"
  az acr delete -g "$AKS_RG" -n "$ACR_NAME" --yes --no-wait || err "Failed to start ACR deletion"
else
  log "ACR $ACR_NAME does not exist"
fi

if [[ "$CLEANUP_DELETE_RG" == "true" ]]; then
  if az group show -n "$AKS_RG" >/dev/null 2>&1; then
    log "Deleting resource group $AKS_RG (async)"
    az group delete -n "$AKS_RG" --yes --no-wait || err "Failed to start RG deletion"
  else
    log "Resource group $AKS_RG already absent"
  fi
fi

pass "Cleanup initiated (deletions running asynchronously)"