#!/usr/bin/env bash
set -euo pipefail

# Lab 1: Check Azure Quota for ARO Deployment
# Diagnoses quota and capacity issues preventing cluster creation

log() { echo "[INFO] $*"; }
pass() { echo "[PASS] $*"; }
warn() { echo "[WARN] $*" >&2; }
fail() { echo "[FAIL] $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_ROOT"

if [[ -f .env ]]; then
  export $(grep -v '^#' .env | xargs -d '\n' 2>/dev/null) || true
fi

LOCATION="${LOCATION:-eastus}"
MASTER_VM_SIZE="${MASTER_VM_SIZE:-Standard_D8s_v3}"
WORKER_VM_SIZE="${WORKER_VM_SIZE:-Standard_D4s_v3}"
WORKER_COUNT="${WORKER_COUNT:-3}"
CHECK_REGIONS="${CHECK_REGIONS:-$LOCATION}"  # comma-separated

log "=== Azure Quota Check for ARO Deployment ==="
echo ""

# Calculate required cores
get_vm_cores() {
  local size="$1"
  case "$size" in
    Standard_D2s_v3|Standard_E2s_v3) echo 2 ;;
    Standard_D4s_v3|Standard_E4s_v3) echo 4 ;;
    Standard_D8s_v3|Standard_E8s_v3) echo 8 ;;
    Standard_D16s_v3|Standard_E16s_v3) echo 16 ;;
    Standard_D2s_v4|Standard_E2s_v4) echo 2 ;;
    Standard_D4s_v4|Standard_E4s_v4) echo 4 ;;
    Standard_D8s_v4|Standard_E8s_v4) echo 8 ;;
    Standard_D16s_v4|Standard_E16s_v4) echo 16 ;;
    Standard_D2s_v5|Standard_E2s_v5) echo 2 ;;
    Standard_D4s_v5|Standard_E4s_v5) echo 4 ;;
    Standard_D8s_v5|Standard_E8s_v5) echo 8 ;;
    Standard_D16s_v5|Standard_E16s_v5) echo 16 ;;
    *) echo 0 ;;
  esac
}

MASTER_CORES=$(get_vm_cores "$MASTER_VM_SIZE")
WORKER_CORES=$(get_vm_cores "$WORKER_VM_SIZE")
TOTAL_MASTER_CORES=$((MASTER_CORES * 3))
TOTAL_WORKER_CORES=$((WORKER_CORES * WORKER_COUNT))
TOTAL_REQUIRED_CORES=$((TOTAL_MASTER_CORES + TOTAL_WORKER_CORES))

log "Configuration:"
echo "  Masters: 3 × $MASTER_VM_SIZE = $TOTAL_MASTER_CORES cores"
echo "  Workers: $WORKER_COUNT × $WORKER_VM_SIZE = $TOTAL_WORKER_CORES cores"
echo "  Total Required: $TOTAL_REQUIRED_CORES cores"
echo ""

# Check each region
IFS=',' read -ra REGIONS <<< "$CHECK_REGIONS"
for region in "${REGIONS[@]}"; do
  region=$(echo "$region" | xargs)  # trim whitespace
  log "=== Checking Region: $region ==="
  echo ""
  
  # 1. Check VM SKU availability
  log "Checking VM SKU availability..."
  for size in "$MASTER_VM_SIZE" "$WORKER_VM_SIZE"; do
    restrictions=$(az vm list-skus -l "$region" --size "$size" --resource-type virtualMachines \
      --query "[?name=='$size'].restrictions[0].reasonCode" -o tsv 2>/dev/null || echo "NotAvailableForSubscription")
    
    if [[ -z "$restrictions" ]]; then
      pass "$size: Available"
    elif [[ "$restrictions" == "NotAvailableForSubscription" ]]; then
      fail "$size: Restricted in your subscription"
    else
      warn "$size: Restriction reason: $restrictions"
    fi
  done
  echo ""
  
  # 2. Check quota limits
  log "Checking quota limits..."
  
  # Determine family name based on VM size
  get_family_name() {
    local size="$1"
    case "$size" in
      Standard_D*_v3) echo "standardDSv3Family" ;;
      Standard_D*_v4) echo "standardDSv4Family" ;;
      Standard_D*_v5) echo "standardDSv5Family" ;;
      Standard_E*_v3) echo "standardESv3Family" ;;
      Standard_E*_v4) echo "standardESv4Family" ;;
      Standard_E*_v5) echo "standardESv5Family" ;;
      *) echo "unknown" ;;
    esac
  }
  
  MASTER_FAMILY=$(get_family_name "$MASTER_VM_SIZE")
  WORKER_FAMILY=$(get_family_name "$WORKER_VM_SIZE")
  
  # Get quota usage
  quota_data=$(az vm list-usage -l "$region" -o json 2>/dev/null || echo "[]")
  
  check_quota() {
    local family="$1"
    local required="$2"
    local display_name="$3"
    
    if [[ "$family" == "unknown" ]]; then
      warn "$display_name: Unknown VM family, cannot check quota"
      return
    fi
    
    # Try various name formats
    local usage=$(echo "$quota_data" | jq -r ".[] | select(.name.value | test(\"$family\"; \"i\")) | .currentValue" | head -1)
    local limit=$(echo "$quota_data" | jq -r ".[] | select(.name.value | test(\"$family\"; \"i\")) | .limit" | head -1)
    
    if [[ -z "$usage" || -z "$limit" ]]; then
      warn "$display_name ($family): Unable to retrieve quota data"
      return
    fi
    
    local available=$((limit - usage))
    
    echo "  $display_name ($family):"
    echo "    Current: $usage / $limit cores"
    echo "    Available: $available cores"
    echo "    Required: $required cores"
    
    if (( available >= required )); then
      pass "Sufficient quota"
    else
      fail "Insufficient quota (need $required, have $available)"
    fi
  }
  
  check_quota "$MASTER_FAMILY" "$TOTAL_MASTER_CORES" "Masters"
  check_quota "$WORKER_FAMILY" "$TOTAL_WORKER_CORES" "Workers"
  
  # Check total regional cores
  total_usage=$(echo "$quota_data" | jq -r '.[] | select(.name.value=="cores") | .currentValue')
  total_limit=$(echo "$quota_data" | jq -r '.[] | select(.name.value=="cores") | .limit')
  
  if [[ -n "$total_usage" && -n "$total_limit" ]]; then
    total_available=$((total_limit - total_usage))
    echo ""
    echo "  Total Regional Cores:"
    echo "    Current: $total_usage / $total_limit"
    echo "    Available: $total_available"
    echo "    Required: $TOTAL_REQUIRED_CORES"
    
    if (( total_available >= TOTAL_REQUIRED_CORES )); then
      pass "Sufficient total quota"
    else
      fail "Insufficient total quota (need $TOTAL_REQUIRED_CORES, have $total_available)"
    fi
  fi
  
  echo ""
  
  # 3. Check for existing ARO clusters
  log "Checking for existing ARO clusters..."
  existing_clusters=$(az aro list --query "[?location=='$region'].{name:name,rg:resourceGroup,state:provisioningState}" -o table 2>/dev/null || echo "")
  
  if [[ -n "$existing_clusters" ]]; then
    echo "$existing_clusters"
    warn "Existing clusters may be consuming quota"
  else
    log "No existing ARO clusters in $region"
  fi
  
  echo ""
  echo "================================================"
  echo ""
done

# Recommendations
log "=== Recommendations ==="
echo ""
echo "If quota is insufficient:"
echo "  1. Request quota increase via Azure Portal:"
echo "     Support → New support request → Service and subscription limits (quotas)"
echo "  2. Delete unused VMs/clusters to free quota"
echo "  3. Try a different region with available quota"
echo "  4. Use smaller VM sizes (e.g., D4s_v3 for masters)"
echo ""
echo "If SKUs are restricted:"
echo "  1. Try alternative VM families (D → E or vice versa)"
echo "  2. Try newer generations (v3 → v4 → v5)"
echo "  3. Contact Azure support to lift restrictions"
echo ""
echo "To request quota increase for specific family:"
echo "  az vm list-usage -l $LOCATION --query \"[?contains(name.localizedValue,'Standard')].{Name:name.localizedValue,Current:currentValue,Limit:limit}\" -o table"
