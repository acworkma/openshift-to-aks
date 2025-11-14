#!/usr/bin/env bash
set -euo pipefail

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
pass() { echo "[PASS] $*"; }
warn() { echo "[WARN] $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_ROOT"

# Load .env if present
if [[ -f .env ]]; then
  # shellcheck disable=SC2046
  export $(grep -v '^#' .env | xargs -d '\n') || true
fi

CLUSTER_NAME="${CLUSTER_NAME:?CLUSTER_NAME environment variable required (ARO cluster name)}"
LOCATION="${LOCATION:-}" # may be blank if MULTI_REGION_FALLBACK provided
MULTI_REGION_FALLBACK="${MULTI_REGION_FALLBACK:-}" # e.g. "centralus,eastus2,westus2"
IFS=',' read -r -a REGION_LIST <<< "${MULTI_REGION_FALLBACK:-$LOCATION}" || true
if [[ ${#REGION_LIST[@]} -eq 0 || -z "${REGION_LIST[0]}" ]]; then
  err "LOCATION or MULTI_REGION_FALLBACK must be set"; exit 1
fi
ORIGINAL_ARO_RG="${ARO_RG:-}" # may derive per region if empty
INTERNAL_SUFFIX="${INTERNAL_SUFFIX:-int}"
WORKER_COUNT="${WORKER_COUNT:-3}"
# Requested sizes (may be auto-adjusted if restricted in region)
REQUESTED_WORKER_VM_SIZE="${WORKER_VM_SIZE:-Standard_D4s_v3}"
REQUESTED_MASTER_VM_SIZE="${MASTER_VM_SIZE:-Standard_D8s_v3}"
# Effective sizes (resolved later)
WORKER_VM_SIZE="$REQUESTED_WORKER_VM_SIZE"
MASTER_VM_SIZE="$REQUESTED_MASTER_VM_SIZE"
SP_CLIENT_ID_RAW="${SP_CLIENT_ID:-}" # optional raw value
SP_CLIENT_SECRET_RAW="${SP_CLIENT_SECRET:-}" # optional raw value
OPENSHIFT_VERSION="${OPENSHIFT_VERSION:-}" # optional specific OpenShift version
SKIP_RP_RBAC="${SKIP_RP_RBAC:-false}" # set true to skip RP Network Contributor assignment
SKIP_VM_SIZE_CHECK="${SKIP_VM_SIZE_CHECK:-false}" # set true to skip VM size restriction check

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

log "Registering required resource providers (idempotent)..."
az provider register -n Microsoft.RedHatOpenShift >/dev/null || true
az provider register -n Microsoft.Compute >/dev/null || true
az provider register -n Microsoft.Storage >/dev/null || true
az provider register -n Microsoft.Authorization >/dev/null || true

# Helper: pick available VM size via fallback chain (first unrestricted wins)
pick_vm_size() {
  local role="$1" requested="$2" location="$3"
  local -a chain
  if [[ "$role" == "master" ]]; then
    chain=("$requested" "Standard_D8s_v5" "Standard_D8s_v4" "Standard_D8s_v3")
  else
    chain=("$requested" "Standard_D4s_v5" "Standard_D4s_v4" "Standard_D4s_v3")
  fi
  for size in "${chain[@]}"; do
    if az vm list-skus -l "$location" --size "${size%_*}" --query "[?name=='$size' && (restrictions[?type=='Location']|length(@)==\`0\`)].name" -o tsv 2>/dev/null | grep -q "$size"; then
      echo "$size"; return 0
    fi
  done
  echo "$requested"
}

# Helper: auto-detect latest OpenShift version if not supplied
resolve_openshift_version() {
  local location="$1"
  if [[ -n "$OPENSHIFT_VERSION" ]]; then
    echo "$OPENSHIFT_VERSION"; return 0
  fi
  log "OPENSHIFT_VERSION unset; querying versions for $location..."
  local versions
  versions=$(az aro get-versions -l "$location" -o tsv 2>/dev/null || true)
  if [[ -z "$versions" ]]; then
    err "Could not retrieve versions; proceeding with platform default."; echo ""; return 0
  fi
  local latest
  latest=$(echo "$versions" | sort -V | tail -1)
  log "Using latest detected version: $latest"
  echo "$latest"
}

ensure_rg(){
  local region="$1"
  # Derive RG if not supplied: rg-aro-lab-<region>
  ARO_RG="${ORIGINAL_ARO_RG:-rg-aro-lab-${region}}"
  log "Ensuring resource group '$ARO_RG' in $region exists..."
  if ! az group show -n "$ARO_RG" >/dev/null 2>&1; then
    az group create --name "$ARO_RG" --location "$region" --output none
    log "Created resource group $ARO_RG"
  else
    log "Resource group already exists"
  fi
}

# Function: ensure Network Contributor role for ARO Resource Provider SP on VNet scope
ensure_rp_role_assignment() {
  local vnet_name="${VNET_NAME:-aro-vnet}"
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

attempt_cluster(){
  local region="$1"
  ensure_rg "$region"

  # Network names (will be overridden if alt network used)
  VNET_NAME="aro-vnet"
  MASTER_SUBNET_NAME="master-subnet"
  WORKER_SUBNET_NAME="worker-subnet"
  USE_ALT_NETWORK=false

  log "Evaluating VM size restrictions in region '$region'..."
  if [[ "$SKIP_VM_SIZE_CHECK" == "true" ]]; then
    log "SKIP_VM_SIZE_CHECK=true; using requested sizes without validation."
    MASTER_VM_SIZE="$REQUESTED_MASTER_VM_SIZE"
    WORKER_VM_SIZE="$REQUESTED_WORKER_VM_SIZE"
  else
    MASTER_VM_SIZE="$(pick_vm_size master "$REQUESTED_MASTER_VM_SIZE" "$region")"
    # include E-series fallback if D restricted
    if [[ "$MASTER_VM_SIZE" == "$REQUESTED_MASTER_VM_SIZE" ]]; then
      alt=$(for c in Standard_E8s_v3 Standard_D8s_v4 Standard_D8s_v3; do az vm list-skus -l "$region" --size "${c%_*}" --query "[?name=='$c' && (restrictions[?type=='Location']|length(@)==\`0\`)].name" -o tsv 2>/dev/null | grep -q "$c" && echo "$c" && break; done); MASTER_VM_SIZE="${alt:-$MASTER_VM_SIZE}"; fi
    WORKER_VM_SIZE="$(pick_vm_size worker "$REQUESTED_WORKER_VM_SIZE" "$region")"
    if [[ "$WORKER_VM_SIZE" == "$REQUESTED_WORKER_VM_SIZE" ]]; then
      altw=$(for c in Standard_E4s_v3 Standard_D4s_v4 Standard_D4s_v3; do az vm list-skus -l "$region" --size "${c%_*}" --query "[?name=='$c' && (restrictions[?type=='Location']|length(@)==\`0\`)].name" -o tsv 2>/dev/null | grep -q "$c" && echo "$c" && break; done); WORKER_VM_SIZE="${altw:-$WORKER_VM_SIZE}"; fi
  fi
  pass "Master VM size resolved: $MASTER_VM_SIZE (requested: $REQUESTED_MASTER_VM_SIZE)"
  pass "Worker VM size resolved: $WORKER_VM_SIZE (requested: $REQUESTED_WORKER_VM_SIZE)"

  RESOLVED_VERSION="$(resolve_openshift_version "$region")"
  [[ -n "$RESOLVED_VERSION" ]] && OPENSHIFT_VERSION="$RESOLVED_VERSION"
  [[ -n "$OPENSHIFT_VERSION" ]] && pass "OpenShift version: $OPENSHIFT_VERSION" || log "OpenShift version: (platform default)"

  local SKIP_NETWORK_REDEPLOY="${SKIP_NETWORK_REDEPLOY:-false}"
  if [[ "$SKIP_NETWORK_REDEPLOY" == "true" ]] && az network vnet show -g "$ARO_RG" -n aro-vnet >/dev/null 2>&1; then
    log "Skipping network redeployment (SKIP_NETWORK_REDEPLOY=true and VNet exists)."
  else
    if az network vnet show -g "$ARO_RG" -n aro-vnet >/dev/null 2>&1; then
      log "VNet aro-vnet already exists; attempting idempotent Bicep deployment (will not delete subnets)."
    else
      log "Deploying network (Bicep) for region $region..."
    fi
    BICEP_FILE="infrastructure/main.bicep"
    DEPLOY_PARAMS=(location="$region" clusterName="$CLUSTER_NAME")
    PARAM_ARGS=(); for p in "${DEPLOY_PARAMS[@]}"; do PARAM_ARGS+=(--parameters "$p"); done
    set +e
    az deployment group create --resource-group "$ARO_RG" --name "aroNetwork" --template-file "$BICEP_FILE" "${PARAM_ARGS[@]}" --output none
    local net_exit=$?
    set -e
    if [[ $net_exit -ne 0 ]]; then
      local deploy_err details_codes internal_rg retry_exit
      deploy_err=$(az deployment group show -g "$ARO_RG" -n aroNetwork --query properties.error.message -o tsv 2>/dev/null || echo "")
      details_codes=$(az deployment group show -g "$ARO_RG" -n aroNetwork --query "properties.error.details[].code" -o tsv 2>/dev/null || echo "")
      if echo "$deploy_err $details_codes" | grep -q "InUseSubnetCannotBeDeleted"; then
        err "In-use subnet detected during network deploy (subnet locked by orphan resources). Initiating cleanup."
        # Attempt to extract internal resource group from first detail message
        internal_rg=$(az deployment group show -g "$ARO_RG" -n aroNetwork --query "properties.error.details[0].message" -o tsv 2>/dev/null | sed -n 's#.*resourceGroups/\([^/]*\)/providers/Microsoft.Network/loadBalancers.*#\1#p' || true)
        if [[ -n "$internal_rg" && "$internal_rg" != "$ARO_RG" ]]; then
          log "Deleting orphan internal RG: $internal_rg"
          az group delete -n "$internal_rg" --yes --no-wait || warn "Failed to initiate delete for $internal_rg"
          for i in {1..12}; do
            if az group show -n "$internal_rg" >/dev/null 2>&1; then
              log "Waiting for internal RG $internal_rg deletion (attempt $i)"; sleep 5
            else
              pass "Internal RG $internal_rg deletion acknowledged."; break
            fi
          done
        else
          warn "Could not parse distinct internal RG from error; continuing without RG delete."
        fi
        log "Skipping further network redeploy (will assume existing subnets)."
        SKIP_NETWORK_REDEPLOY=true
      else
        err "Network deployment failed (exit $net_exit). Attempting alternate network as fallback."
        log "Deploying alternate network (fresh VNet with unique suffix)..."
        ALT_BICEP="infrastructure/alt-network.bicep"
        SUFFIX=$(echo "$region-$(date +%s)" | md5sum | cut -c1-8)
        set +e
        ALT_OUTPUT=$(az deployment group create --resource-group "$ARO_RG" --name "aroNetworkAlt" --template-file "$ALT_BICEP" --parameters location="$region" networkSuffix="$SUFFIX" --query 'properties.outputs' -o json 2>&1)
        local alt_exit=$?
        set -e
        if [[ $alt_exit -eq 0 ]]; then
          VNET_NAME=$(echo "$ALT_OUTPUT" | jq -r '.vnetName.value')
          MASTER_SUBNET_NAME=$(echo "$ALT_OUTPUT" | jq -r '.masterSubnetName.value')
          WORKER_SUBNET_NAME=$(echo "$ALT_OUTPUT" | jq -r '.workerSubnetName.value')
          USE_ALT_NETWORK=true
          pass "Alternate network deployed: VNet=$VNET_NAME, Master=$MASTER_SUBNET_NAME, Worker=$WORKER_SUBNET_NAME"
        else
          err "Alternate network deployment also failed. Error codes: ${details_codes:-none}"
          return 2
        fi
      fi
    else
      pass "Network deployment succeeded in $region."
    fi
  fi
  ensure_rp_role_assignment || { err "RP role assignment step failed."; return 3; }

  # Optional sanitation of residual artifacts (NSGs, route tables, service endpoints) on subnets
  local SANITIZE_SUBNETS="${SANITIZE_SUBNETS:-true}"
  local FORCE_DELETE_EXISTING_CLUSTER="${FORCE_DELETE_EXISTING_CLUSTER:-true}"
  local vnet_name="$VNET_NAME"
  local master_subnet="$MASTER_SUBNET_NAME"
  local worker_subnet="$WORKER_SUBNET_NAME"

  # Skip sanitation for fresh alternate network
  if [[ "$USE_ALT_NETWORK" == "true" ]]; then
    log "Using fresh alternate network; skipping sanitation."
    SANITIZE_SUBNETS=false
  fi

  if [[ "$SANITIZE_SUBNETS" == "true" ]]; then
    log "Subnet sanitation enabled (SANITIZE_SUBNETS=true). Checking subnets for NSGs/route tables/service endpoints..."
    for sn in "$master_subnet" "$worker_subnet"; do
      if az network vnet subnet show -g "$ARO_RG" --vnet-name "$vnet_name" -n "$sn" >/dev/null 2>&1; then
        local details
        details=$(az network vnet subnet show -g "$ARO_RG" --vnet-name "$vnet_name" -n "$sn" -o json)
        local has_nsg has_rt has_se eps
        has_nsg=$(echo "$details" | jq -r 'has("networkSecurityGroup")') || has_nsg=false
        # networkSecurityGroup may exist but be null; treat that as absent
        if [[ "$has_nsg" == "true" ]]; then
          local nsg_id
          nsg_id=$(echo "$details" | jq -r '.networkSecurityGroup.id // ""')
          if [[ -n "$nsg_id" ]]; then
            log "Detaching NSG from subnet $sn"
            az network vnet subnet update -g "$ARO_RG" --vnet-name "$vnet_name" -n "$sn" --remove networkSecurityGroup --output none || warn "Failed to detach NSG from $sn"
          fi
        fi
        has_rt=$(echo "$details" | jq -r 'has("routeTable")') || has_rt=false
        if [[ "$has_rt" == "true" ]]; then
          local rt_id
          rt_id=$(echo "$details" | jq -r '.routeTable.id // ""')
          if [[ -n "$rt_id" ]]; then
            log "Detaching route table from subnet $sn"
            az network vnet subnet update -g "$ARO_RG" --vnet-name "$vnet_name" -n "$sn" --remove routeTable --output none || warn "Failed to detach route table from $sn"
          fi
        fi
        eps=$(echo "$details" | jq -r '.serviceEndpoints | length' 2>/dev/null || echo "0")
        if [[ "$eps" != "0" ]]; then
          log "Service endpoints present on subnet $sn (will be managed by ARO during creation); skipping manual removal."
        fi
      else
        log "Subnet $sn not found; skipping sanitation for now."
      fi
    done
  else
    log "Subnet sanitation disabled (SANITIZE_SUBNETS=false)."
  fi

  # If a cluster resource already exists and force delete requested, remove it when not succeeded
  if [[ "$FORCE_DELETE_EXISTING_CLUSTER" == "true" ]]; then
    if az aro show -g "$ARO_RG" -n "$CLUSTER_NAME" >/dev/null 2>&1; then
      local prov_state
      prov_state=$(az aro show -g "$ARO_RG" -n "$CLUSTER_NAME" --query provisioningState -o tsv 2>/dev/null || echo "Unknown")
      if [[ "$prov_state" != "Succeeded" ]]; then
        log "Existing cluster resource found with state '$prov_state'; deleting before fresh create (FORCE_DELETE_EXISTING_CLUSTER=true)."
        az resource delete --ids $(az resource list -g "$ARO_RG" --resource-type Microsoft.RedHatOpenShift/openShiftClusters --query "[?name=='$CLUSTER_NAME'].id" -o tsv) || warn "Cluster resource delete attempt failed"
        # small delay to allow backend to release subnets
        sleep 5
      fi
    fi
  fi

  if az aro show -g "$ARO_RG" -n "$CLUSTER_NAME" >/dev/null 2>&1; then
    log "Cluster '$CLUSTER_NAME' already exists in $region; skipping create (or previously deleted still releasing)."
  else
    log "Creating ARO cluster in $region (may take 30-40 minutes)..."
    log "Network: VNet=$VNET_NAME, Master=$MASTER_SUBNET_NAME, Worker=$WORKER_SUBNET_NAME"
    if ! az aro create \
      --resource-group "$ARO_RG" \
      --name "$CLUSTER_NAME" \
      --vnet "$VNET_NAME" \
      --master-subnet "$MASTER_SUBNET_NAME" \
      --worker-subnet "$WORKER_SUBNET_NAME" \
      --apiserver-visibility Public \
      --ingress-visibility Public \
      --worker-count "$WORKER_COUNT" \
      --master-vm-size "$MASTER_VM_SIZE" \
      --worker-vm-size "$WORKER_VM_SIZE" \
      ${OPENSHIFT_VERSION:+--version "$OPENSHIFT_VERSION"} \
      --output json; then
        err "az aro create failed in $region."; return 4
    fi
    pass "Cluster create submitted in $region."
  fi

  if [[ "$DEPLOY_NO_WAIT" == "true" ]]; then
    log "DEPLOY_NO_WAIT=true; not polling cluster readiness."
    return 0
  fi

  log "Polling cluster provisioning state (region $region)..."
  local state=""; for i in {1..5}; do
    state=$(az aro show -g "$ARO_RG" -n "$CLUSTER_NAME" --query provisioningState -o tsv 2>/dev/null || echo "Unknown")
    if [[ "$state" == "Succeeded" ]]; then pass "Cluster Succeeded in $region"; break; fi
    if [[ "$state" == "Failed" ]]; then err "Cluster Failed in $region"; break; fi
    log "Attempt $i: state=$state (wait 60s)"; sleep 60
  done
  if [[ "$state" == "Failed" ]]; then
    log "Activity log (last 5 events) in $ARO_RG:" || true
    az monitor activity-log list --resource-group "$ARO_RG" --offset 2h --max-events 5 --query "[].{time:eventTimestamp,op:operationName.localizedValue,status:status.localizedValue}" -o table 2>/dev/null || true
    return 5
  fi
  [[ "$state" == "Succeeded" ]] || log "Cluster still provisioning beyond initial poll; continuing." 
  return 0
}

FAILOVER_ENABLED=true
for region in "${REGION_LIST[@]}"; do
  log "=== Region attempt: $region ==="
  if attempt_cluster "$region"; then
    pass "Deployment flow finished for region $region"
    break
  else
    rc=$?
    if [[ $rc -eq 5 || $rc -eq 4 ]]; then
      log "Cluster creation failed in $region (code $rc). Trying next region if available..."
    else
      err "Non-recoverable error (code $rc) in $region, aborting."; exit $rc
    fi
  fi
done

FINAL_RG="$ARO_RG"
log "Retrieving console & API URLs (may be empty until provisioning succeeds)..."
CONSOLE_URL=$(az aro show -g "$FINAL_RG" -n "$CLUSTER_NAME" --query consoleProfile.url -o tsv 2>/dev/null || echo "")
API_URL=$(az aro show -g "$FINAL_RG" -n "$CLUSTER_NAME" --query apiserverProfile.url -o tsv 2>/dev/null || echo "")
pass "Console URL: ${CONSOLE_URL:-<pending>}"
pass "API Server URL: ${API_URL:-<pending>}"
log "Use: az aro list-credentials -g $FINAL_RG -n $CLUSTER_NAME to obtain kubeadmin password once console URL resolves."
