#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[INFO] $*"; }
err(){ echo "[ERROR] $*" >&2; }
pass(){ echo "[PASS] $*"; }
fail(){ echo "[FAIL] $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_ROOT"

if [[ -f .env ]]; then
  # shellcheck disable=SC2046
  export $(grep -v '^#' .env | xargs -d '\n') || true
fi

# Allow MULTI_REGION_FALLBACK (comma-separated) or single LOCATION
MULTI_REGION_FALLBACK="${MULTI_REGION_FALLBACK:-}" # e.g. "centralus,eastus2,westus2"
PRIMARY_LOCATION="${LOCATION:-}" # legacy single-region variable
if [[ -z "$PRIMARY_LOCATION" && -z "$MULTI_REGION_FALLBACK" ]]; then
  fail "LOCATION or MULTI_REGION_FALLBACK must be set"
fi

IFS=',' read -r -a REGIONS <<< "${MULTI_REGION_FALLBACK:-$PRIMARY_LOCATION}" || true
if [[ ${#REGIONS[@]} -eq 0 ]]; then fail "No regions parsed"; fi

ARO_RG="${ARO_RG:-}" # optional; will be derived per region if blank

if ! command -v az >/dev/null 2>&1; then fail "Azure CLI not found"; fi

log "Checking provider registration..."
for p in Microsoft.RedHatOpenShift Microsoft.Compute Microsoft.Storage Microsoft.Authorization; do
  state=$(az provider show -n "$p" --query registrationState -o tsv 2>/dev/null || echo "Unknown")
  log "Provider $p: $state"
  if [[ "$state" != "Registered" ]]; then
    log "Attempting registration for $p"; az provider register -n "$p" >/dev/null || true
  fi
done

# Global VM SKU availability snapshot for Standard_D8s_v5 (user-requested check)
log "Listing global SKU availability for Standard_D8s_v5 (may include restricted regions)"
az vm list-skus --size Standard_D8s_v5 --all -o table | head -n 30 || err "Failed to list Standard_D8s_v5 SKU"

for REGION in "${REGIONS[@]}"; do
  echo "--- [REGION] $REGION ---"
  log "Retrieving available OpenShift versions..."
  VERSIONS=$(az aro get-versions -l "$REGION" -o tsv 2>/dev/null || echo "")
  if [[ -z "$VERSIONS" ]]; then
    err "No versions returned (region unsupported or API transient)."
  else
    echo "$VERSIONS" | awk '{print "[VERSION] "$0}'
    LATEST=$(echo "$VERSIONS" | sort -V | tail -1)
    pass "Latest version candidate: $LATEST"
  fi

  log "Checking requested VM sizes (env WORKER_VM_SIZE / MASTER_VM_SIZE or defaults)..."
  REQ_WORKER="${WORKER_VM_SIZE:-Standard_D4s_v3}"
  REQ_MASTER="${MASTER_VM_SIZE:-Standard_D8s_v3}"

  check_size(){
    local size="$1" role="$2"
    if az vm list-skus -l "$REGION" --size "${size%_*}" --query "[?name=='$size' && (restrictions[?type=='Location']|length(@)==\`0\`)].name" -o tsv 2>/dev/null | grep -q "$size"; then
      pass "$role size $size available"
    else
      err "$role size $size appears restricted in $REGION"
    fi
  }
  check_size "$REQ_MASTER" master || true
  check_size "$REQ_WORKER" worker || true

  # Quota usage (cores) quick glance
  log "Checking core usage (Compute quotas)..."
  az vm list-usage -l "$REGION" --query "[?contains(name.value,'Total Regional Cores')].{limit:limit,current:currentValue}" -o table 2>/dev/null || err "Quota query failed"

  # Provide fallback suggestions
  log "Suggested master fallbacks: Standard_D8s_v5 Standard_D8s_v4 Standard_E8s_v3"
  log "Suggested worker fallbacks: Standard_D4s_v5 Standard_D4s_v4 Standard_E4s_v3"
done
log "Preflight complete across ${#REGIONS[@]} region(s)."
