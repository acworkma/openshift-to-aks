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
  # shellcheck disable=SC2046
  export $(grep -v '^#' .env | xargs -d '\n') || true
fi

: "${ARO_RG?ARO_RG environment variable required (resource group)}"
: "${LOCATION?LOCATION environment variable required (Azure region)}"
: "${CLUSTER_NAME?CLUSTER_NAME environment variable required (ARO cluster name)}"
INTERNAL_SUFFIX="${INTERNAL_SUFFIX:-int}"
WORKER_COUNT="${WORKER_COUNT:-3}"
WORKER_VM_SIZE="${WORKER_VM_SIZE:-Standard_D4s_v3}"
MASTER_VM_SIZE="${MASTER_VM_SIZE:-Standard_D8s_v3}"
SP_CLIENT_ID_RAW="${SP_CLIENT_ID:-}" # optional raw value
SP_CLIENT_SECRET_RAW="${SP_CLIENT_SECRET:-}" # optional raw value
OPENSHIFT_VERSION="${OPENSHIFT_VERSION:-}" # optional specific OpenShift version
SKIP_RP_RBAC="${SKIP_RP_RBAC:-false}" # set true to skip RP Network Contributor assignment

# Treat placeholder values (starting with REPLACE_ME_) as empty
if [[ "$SP_CLIENT_ID_RAW" == REPLACE_ME_* ]]; then SP_CLIENT_ID_RAW=""; fi
if [[ "$SP_CLIENT_SECRET_RAW" == REPLACE_ME_* ]]; then SP_CLIENT_SECRET_RAW=""; fi

SP_CLIENT_ID="$SP_CLIENT_ID_RAW"
SP_CLIENT_SECRET="$SP_CLIENT_SECRET_RAW"

# Auto-create service principal if requested and missing
AUTO_CREATE_SP="${AUTO_CREATE_SP:-false}"
if [[ -z "$SP_CLIENT_ID" || -z "$SP_CLIENT_SECRET" ]]; then
  if [[ "$AUTO_CREATE_SP" == "true" ]]; then
    log "AUTO_CREATE_SP=true and SP credentials missing; creating service principal (Contributor on subscription)."
    SUB_ID=$(az account show --query id -o tsv)
    SP_JSON=$(az ad sp create-for-rbac --name "aro-sp-${CLUSTER_NAME}" --role Contributor --scopes "/subscriptions/${SUB_ID}" --years 1 -o json)
    SP_CLIENT_ID=$(echo "$SP_JSON" | grep -E '"appId"' | cut -d '"' -f4)
    SP_CLIENT_SECRET=$(echo "$SP_JSON" | grep -E '"password"' | cut -d '"' -f4)
    pass "Created SP appId=$SP_CLIENT_ID"
  else
    err "Service principal credentials required (set SP_CLIENT_ID/SP_CLIENT_SECRET or AUTO_CREATE_SP=true)."; exit 1
  fi
fi
PULL_SECRET="${PULL_SECRET:-}" # optional
DEPLOY_NO_WAIT="${DEPLOY_NO_WAIT:-false}" # if true, do not wait for full deployment

if ! command -v az >/dev/null 2>&1; then
  err "Azure CLI (az) not found on PATH"; exit 1
fi

# Pre-deployment validation
log "Running pre-deployment validation..."
# Check if logged in to Azure
if ! az account show >/dev/null 2>&1; then
  err "Not logged in to Azure. Run: az login"
  exit 1
fi

# Verify location is valid
if ! az account list-locations --query "[?name=='$LOCATION'].name" -o tsv | grep -q "$LOCATION"; then
  err "Invalid location: $LOCATION"
  err "List valid locations: az account list-locations -o table"
  exit 1
fi
pass "Azure login and location validated"

log "Registering required resource providers (idempotent)..."
az provider register -n Microsoft.RedHatOpenShift >/dev/null || true
az provider register -n Microsoft.Compute >/dev/null || true
az provider register -n Microsoft.Storage >/dev/null || true
az provider register -n Microsoft.Authorization >/dev/null || true

log "Ensuring resource group '$ARO_RG' exists..."
if ! az group show -n "$ARO_RG" >/dev/null 2>&1; then
  az group create --name "$ARO_RG" --location "$LOCATION" --output none
  log "Created resource group $ARO_RG"
else
  log "Resource group already exists"
fi

# Auto-detect valid OpenShift version if not specified
if [[ -z "$OPENSHIFT_VERSION" ]]; then
  log "No OPENSHIFT_VERSION specified; querying available versions for region $LOCATION..."
  AVAILABLE_VERSIONS=$(az aro get-versions -l "$LOCATION" --query "[-3:]" -o tsv 2>/dev/null || true)
  if [[ -n "$AVAILABLE_VERSIONS" ]]; then
    # Pick the latest stable version (last one from the list)
    OPENSHIFT_VERSION=$(echo "$AVAILABLE_VERSIONS" | tail -1)
    log "Auto-selected OpenShift version: $OPENSHIFT_VERSION"
  else
    log "Could not query available versions; will proceed with default (may fail if region doesn't support it)"
  fi
fi

# Function: ensure Network Contributor role for ARO Resource Provider SP on VNet scope
ensure_rp_role_assignment() {
  local vnet_name="aro-vnet"
  local rp_app_id="f1dd0a37-89c6-4e07-bcd1-ffd3d43d8875" # Azure Red Hat OpenShift RP appId (public doc value)
  if [[ "$SKIP_RP_RBAC" == "true" ]]; then
    log "SKIP_RP_RBAC=true; skipping RP role assignment logic."
    return 0
  fi
  local vnet_id
  vnet_id=$(az network vnet show -g "$ARO_RG" -n "$vnet_name" --query id -o tsv 2>/dev/null || true)
  if [[ -z "$vnet_id" ]]; then
    log "VNet '$vnet_name' not found yet; delaying RP role assignment."
    return 0
  fi
  log "Ensuring Network Contributor role for ARO RP on VNet scope..."
  local rp_sp_id
  rp_sp_id=$(az ad sp list --filter "appId eq '$rp_app_id'" --query "[0].id" -o tsv 2>/dev/null || true)
  if [[ -z "$rp_sp_id" ]]; then
    err "Could not resolve RP service principal (appId=$rp_app_id). Azure AD query returned empty."; return 1
  fi
  local existing
  existing=$(az role assignment list --assignee "$rp_sp_id" --scope "$vnet_id" --query "[?roleDefinitionName=='Network Contributor'].id" -o tsv 2>/dev/null || true)
  if [[ -n "$existing" ]]; then
    pass "RP already has Network Contributor on VNet."
  else
    log "Assigning Network Contributor to RP on scope $vnet_id..."
    az role assignment create --assignee "$rp_sp_id" --role "Network Contributor" --scope "$vnet_id" --output none || {
      err "Failed to assign Network Contributor to RP."; return 1; }
    pass "Assigned Network Contributor to RP on VNet." 
  fi
}

log "Deploying network (Bicep) only (cluster via CLI)..."
BICEP_FILE="infrastructure/main.bicep"

DEPLOY_PARAMS=(
  location="$LOCATION"
  clusterName="$CLUSTER_NAME"
  workerCount="$WORKER_COUNT"
  workerVmSize="$WORKER_VM_SIZE"
  masterVmSize="$MASTER_VM_SIZE"
  internalSuffix="$INTERNAL_SUFFIX"
  spClientId="$SP_CLIENT_ID"
  spClientSecret="$SP_CLIENT_SECRET"
)
[[ -n "$OPENSHIFT_VERSION" ]] && DEPLOY_PARAMS+=(openshiftVersion="$OPENSHIFT_VERSION")
[[ -n "$PULL_SECRET" ]] && DEPLOY_PARAMS+=(pullSecret="$PULL_SECRET")

PARAM_ARGS=()
for p in "${DEPLOY_PARAMS[@]}"; do PARAM_ARGS+=(--parameters "$p"); done

set +e
az deployment group create --resource-group "$ARO_RG" --name "aroNetwork" --template-file "$BICEP_FILE" "${PARAM_ARGS[@]}" --output none
DEPLOY_EXIT=$?
set -e
if [[ $DEPLOY_EXIT -ne 0 ]]; then
  err "Network deployment failed (exit $DEPLOY_EXIT)."; exit 1
fi
pass "Network deployment succeeded."

# Ensure RP has Network Contributor on VNet scope before cluster creation
ensure_rp_role_assignment || { err "RP role assignment step failed."; exit 1; }

# Fallback/manual network creation path no longer needed since Bicep is network-only

# Create cluster if absent
if az aro show -g "$ARO_RG" -n "$CLUSTER_NAME" >/dev/null 2>&1; then
  log "Cluster '$CLUSTER_NAME' already exists; skipping creation."
else
  log "Creating ARO cluster via az aro create (may take 30-40 minutes)..."
  log "Configuration: Region=$LOCATION, Workers=$WORKER_COUNT x $WORKER_VM_SIZE, Masters=$MASTER_VM_SIZE"
  [[ -n "$OPENSHIFT_VERSION" ]] && log "OpenShift version: $OPENSHIFT_VERSION" || log "OpenShift version: default latest"
  
  set +e
  ARO_CREATE_OUTPUT=$(mktemp)
  az aro create \
    --resource-group "$ARO_RG" \
    --name "$CLUSTER_NAME" \
    --vnet aro-vnet \
    --master-subnet master-subnet \
    --worker-subnet worker-subnet \
    --apiserver-visibility Public \
    --ingress-visibility Public \
    --worker-count "$WORKER_COUNT" \
    --master-vm-size "$MASTER_VM_SIZE" \
    --worker-vm-size "$WORKER_VM_SIZE" \
    ${OPENSHIFT_VERSION:+--version "$OPENSHIFT_VERSION"} \
    --output json > "$ARO_CREATE_OUTPUT" 2>&1
  CREATE_EXIT=$?
  set -e
  
  if [[ $CREATE_EXIT -ne 0 ]]; then
    err "az aro create failed with exit code $CREATE_EXIT"
    if [[ -f "$ARO_CREATE_OUTPUT" ]]; then
      err "Error details:"
      cat "$ARO_CREATE_OUTPUT" >&2
      rm -f "$ARO_CREATE_OUTPUT"
    fi
    err ""
    err "Troubleshooting steps:"
    err "  1. Verify service principal credentials are valid"
    err "  2. Check region capacity: az vm list-skus -l $LOCATION -o table | grep -E 'Standard_D4s_v3|Standard_D8s_v3'"
    err "  3. Verify OpenShift version availability: az aro get-versions -l $LOCATION"
    err "  4. Check quota limits in the Azure Portal"
    exit 1
  fi
  rm -f "$ARO_CREATE_OUTPUT"
  pass "Cluster create command submitted."
fi

if [[ "$DEPLOY_NO_WAIT" == "true" ]]; then
  log "DEPLOY_NO_WAIT=true; not verifying cluster readiness now."
else
  log "Polling cluster provisioning state (up to 5 attempts, 60s intervals)..."
  for i in {1..5}; do
    state=$(az aro show -g "$ARO_RG" -n "$CLUSTER_NAME" --query provisioningState -o tsv 2>/dev/null || echo "Unknown")
    if [[ "$state" == "Succeeded" ]]; then
      pass "Cluster provisioningState=$state"
      break
    elif [[ "$state" == "Failed" ]]; then
      err "Cluster provisioningState=Failed. Check Azure Portal or run: az aro show -g $ARO_RG -n $CLUSTER_NAME"
      break
    else
      log "Attempt $i: state=$state (waiting 60s)"
      if [[ $i -lt 5 ]]; then
        sleep 60
      fi
    fi
  done
  if [[ "$state" != "Succeeded" && "$state" != "Failed" ]]; then
    log "Cluster still provisioning after polling. Monitor manually with: az aro show -g $ARO_RG -n $CLUSTER_NAME --query provisioningState"
  fi
fi

log "Retrieving console & API URLs (may be empty until provisioning succeeds)..."
CONSOLE_URL=$(az aro show -g "$ARO_RG" -n "$CLUSTER_NAME" --query consoleProfile.url -o tsv 2>/dev/null || echo "")
API_URL=$(az aro show -g "$ARO_RG" -n "$CLUSTER_NAME" --query apiserverProfile.url -o tsv 2>/dev/null || echo "")

pass "Console URL: ${CONSOLE_URL:-<pending>}"
pass "API Server URL: ${API_URL:-<pending>}"
log "Use: az aro list-credentials -g $ARO_RG -n $CLUSTER_NAME to obtain kubeadmin password once console URL resolves."
