#!/usr/bin/env bash
set -euo pipefail

# Lab 3: Validate AKS Cluster

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

SIMULATE_LOCAL="${SIMULATE_LOCAL:-false}"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-aks-sim}"
AKS_LOCATION="${AKS_LOCATION:-eastus}"
AKS_RG="${AKS_RG:-rg-aks-lab-${AKS_LOCATION}}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-aks-cluster}"

if [[ "$SIMULATE_LOCAL" == "true" ]]; then
  log "SIMULATE_LOCAL=true: Performing local Kind cluster validation (name: $KIND_CLUSTER_NAME)"
  context_exists=$(kubectl config get-contexts -o name | grep -E "kind-${KIND_CLUSTER_NAME}" || true)
  if [[ -z "$context_exists" ]]; then
    fail "Kind cluster kind-${KIND_CLUSTER_NAME} context not found. Run simulate-kind.sh first."
  fi
  kubectl config use-context "kind-${KIND_CLUSTER_NAME}" >/dev/null
  nodes=$(kubectl get nodes -o name || true)
  if [[ -z "$nodes" ]]; then
    fail "No nodes found in simulated cluster"
  fi
  echo "$nodes"
  pass "Nodes present in simulated cluster"
  log "Running DNS test in simulated cluster"
  kubectl run dns-test --image=busybox:1.36 --restart=Never --command -- sh -c 'sleep 3; nslookup kubernetes.default.svc.cluster.local || true' >/dev/null 2>&1 || true
  kubectl wait --for=condition=Ready pod/dns-test --timeout=40s >/dev/null 2>&1 || true
  kubectl logs dns-test 2>/dev/null || true
  kubectl delete pod dns-test --ignore-not-found >/dev/null 2>&1 || true
  pass "Local simulation validation complete"
  exit 0
fi

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

log "Creating quick test pod"
kubectl run dns-test --image=busybox:1.36 --restart=Never -n kube-system --command -- sh -c 'sleep 5; nslookup kubernetes.default.svc.cluster.local || true' >/dev/null 2>&1 || true
kubectl wait --for=condition=Ready pod/dns-test -n kube-system --timeout=40s >/dev/null 2>&1 || true
log "Pod logs (dns-test):"
kubectl logs dns-test -n kube-system 2>/dev/null || true
kubectl delete pod dns-test -n kube-system --ignore-not-found >/dev/null 2>&1 || true

pass "AKS validation complete"