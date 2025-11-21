#!/usr/bin/env bash
set -euo pipefail

# Lab 3: Validate AKS Cluster (Streamlined)
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


AKS_LOCATION="${AKS_LOCATION:-australiaeast}"
AKS_RG="${AKS_RG:-rg-aks-lab3-aue}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-aks-lab3}"
ACR_NAME="${ACR_NAME:-acrlab3example}"


log "Validating AKS cluster: $AKS_CLUSTER_NAME in RG: $AKS_RG"

if ! az group show -n "$AKS_RG" >/dev/null 2>&1; then
  fail "Resource group $AKS_RG not found"
fi
pass "Resource group exists"

if ! az aks show -g "$AKS_RG" -n "$AKS_CLUSTER_NAME" >/dev/null 2>&1; then
  fail "AKS cluster $AKS_CLUSTER_NAME not found"
fi
pass "Cluster exists"

state=$(az aks show -g "$AKS_RG" -n "$AKS_CLUSTER_NAME" --query provisioningState -o tsv)
log "Provisioning state: $state"
if [[ "$state" != "Succeeded" ]]; then
  fail "Cluster not in Succeeded state (state=$state)"
fi
pass "Cluster provisioning succeeded"

log "Retrieving kubeconfig (admin)"
az aks get-credentials -g "$AKS_RG" -n "$AKS_CLUSTER_NAME" --overwrite-existing --admin >/dev/null || fail "Failed to get credentials"
pass "Credentials merged"

log "Listing nodes"
nodes=$(kubectl get nodes -o name 2>/dev/null || true)
if [[ -z "$nodes" ]]; then
  fail "No nodes returned by kubectl"
fi
echo "$nodes"
pass "kubectl can list nodes"



# Validate ACR
log "Validating ACR: $ACR_NAME in RG: $AKS_RG"
if ! az acr show -g "$AKS_RG" -n "$ACR_NAME" >/dev/null 2>&1; then
  fail "ACR $ACR_NAME not found"
fi
pass "ACR exists"

acr_login_server=$(az acr show -g "$AKS_RG" -n "$ACR_NAME" --query loginServer -o tsv)
acr_admin_user=$(az acr credential show -g "$AKS_RG" -n "$ACR_NAME" --query username -o tsv)
acr_admin_pass=$(az acr credential show -g "$AKS_RG" -n "$ACR_NAME" --query passwords[0].value -o tsv)
log "ACR login server: $acr_login_server"
log "ACR admin username: $acr_admin_user"
if [[ -n "$acr_admin_pass" ]]; then
  pass "ACR admin password retrieved"
else
  fail "ACR admin password not found"
fi

pass "AKS and ACR validation complete"