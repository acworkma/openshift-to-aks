#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[INFO] $*"; }
warn(){ echo "[WARN] $*"; }
err(){ echo "[ERROR] $*" >&2; }
pass(){ echo "[PASS] $*"; }
section(){ echo -e "\n==== $* ====\n"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_ROOT"

if [[ -f .env ]]; then
  # shellcheck disable=SC2046
  export $(grep -v '^#' .env | xargs -d '\n') || true
fi

LOCATION="${LOCATION:-${1:-}}"
CLUSTER_NAME="${CLUSTER_NAME:-aro-cluster}"
ARO_RG="${ARO_RG:-rg-aro-lab-${LOCATION}}"
MASTER_VM_SIZE="${MASTER_VM_SIZE:-Standard_D8s_v3}"
WORKER_VM_SIZE="${WORKER_VM_SIZE:-Standard_D4s_v3}"

if ! command -v az >/dev/null 2>&1; then err "Azure CLI not found"; exit 1; fi
if [[ -z "$LOCATION" ]]; then err "LOCATION not set (.env or first arg)"; exit 1; fi

section "Provider Registration"
for p in Microsoft.RedHatOpenShift Microsoft.Compute Microsoft.Storage Microsoft.Authorization; do
  state=$(az provider show -n "$p" --query registrationState -o tsv 2>/dev/null || echo "Unknown")
  echo "$p -> $state"
done

section "OpenShift Versions in $LOCATION"
VERSIONS=$(az aro get-versions -l "$LOCATION" -o tsv 2>/dev/null || true)
if [[ -n "$VERSIONS" ]]; then
  echo "$VERSIONS" | awk '{print "version: "$0}'
  LATEST=$(echo "$VERSIONS" | sort -V | tail -1)
  pass "Latest candidate: $LATEST"
else
  warn "No versions returned (region may not support ARO or transient API issue)."
fi

section "VM SKU Availability"
check_sku(){
  local size="$1" label="$2"
  if az vm list-skus -l "$LOCATION" --size "${size%_*}" --query "[?name=='$size' && (restrictions[?type=='Location']|length(@)==\`0\`)].name" -o tsv 2>/dev/null | grep -q "$size"; then
    pass "$label $size available"
  else
    warn "$label $size restricted or unavailable"
  fi
}
check_sku "$MASTER_VM_SIZE" master
check_sku "$WORKER_VM_SIZE" worker
echo "Fallback suggestions (master): Standard_D8s_v5 Standard_D8s_v4 Standard_E8s_v3"
echo "Fallback suggestions (worker): Standard_D4s_v5 Standard_D4s_v4 Standard_E4s_v3"

section "Quota Snapshot (Total Regional Cores)"
az vm list-usage -l "$LOCATION" --query "[?contains(name.value,'Total Regional Cores')].{limit:limit,current:currentValue}" -o table 2>/dev/null || warn "Quota query failed"

section "Network Subnet Checks"
for subnet in master-subnet worker-subnet; do
  if az network vnet subnet show -g "$ARO_RG" --vnet-name aro-vnet -n "$subnet" >/dev/null 2>&1; then
    az network vnet subnet show -g "$ARO_RG" --vnet-name aro-vnet -n "$subnet" \
      --query '{name:name,nsg:networkSecurityGroup,routeTable:routeTable,serviceEndpoints:serviceEndpoints,policies:{privateEndpoint:privateEndpointNetworkPolicies,privateLink:privateLinkServiceNetworkPolicies}}' -o json
  else
    warn "Subnet $subnet not found yet"
  fi
done

section "Role Assignments"
SUB_ID=$(az account show --query id -o tsv)
echo "Subscription: $SUB_ID"
# Service principal used for deployment (may be blank if auto or MI)
if [[ -n "${SP_CLIENT_ID:-}" ]]; then
  echo "Deployment SP assignments:"; az role assignment list --assignee "$SP_CLIENT_ID" --query "[].{Role:roleDefinitionName,Scope:scope}" -o table 2>/dev/null || warn "No assignments returned"
else
  warn "SP_CLIENT_ID not set; skipping deployment SP role audit"
fi

RP_APP_ID="f1dd0a37-89c6-4e07-bcd1-ffd3d43d8875"
RP_SP_ID=$(az ad sp list --filter "appId eq '$RP_APP_ID'" --query "[0].id" -o tsv 2>/dev/null || true)
if [[ -n "$RP_SP_ID" ]]; then
  echo "ARO RP VNet assignment check:";
  VNET_ID=$(az network vnet show -g "$ARO_RG" -n aro-vnet --query id -o tsv 2>/dev/null || echo "")
  if [[ -n "$VNET_ID" ]]; then
    az role assignment list --assignee "$RP_SP_ID" --scope "$VNET_ID" --query "[].{Role:roleDefinitionName,Scope:scope}" -o table 2>/dev/null || warn "No RP assignments on VNet"
  else
    warn "VNet aro-vnet not found; cannot check RP assignment"
  fi
else
  warn "Could not resolve RP service principal"
fi

section "Existing / Failed Cluster Artifacts"
az resource list -g "$ARO_RG" --resource-type Microsoft.RedHatOpenShift/openShiftClusters --query "[].{Name:name,State:properties.provisioningState}" -o table 2>/dev/null || warn "Listing failed"

section "Recent Activity Log (ARO operations)"
az monitor activity-log list --resource-group "$ARO_RG" --offset 6h --max-events 15 \
  --query "[?contains(operationName.value,'openShiftClusters')].{Time:eventTimestamp,Operation:operationName.localizedValue,Status:status.localizedValue,SubStatus:subStatus.localizedValue}" -o table 2>/dev/null || warn "No activity events found"

section "Summary"
echo "If all validations pass and InternalServerError persists: likely platform capacity or RP issue. Capture '--debug' output of az aro create and open Azure support ticket with timestamps above."

pass "Diagnostics complete for $LOCATION (RG=$ARO_RG, Cluster=$CLUSTER_NAME)"