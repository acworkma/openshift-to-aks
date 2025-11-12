#!/usr/bin/env bash
set -euo pipefail

# Monitor ARO cluster provisioning status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_ROOT"

# Load .env if present
if [[ -f .env ]]; then
  # shellcheck disable=SC2046
  export $(grep -v '^#' .env | xargs -d '\n') || true
fi

: "${ARO_RG?ARO_RG environment variable required}"
: "${CLUSTER_NAME?CLUSTER_NAME environment variable required}"

echo "[INFO] Monitoring cluster: $CLUSTER_NAME in RG: $ARO_RG"
echo "[INFO] Press Ctrl+C to stop monitoring (cluster will continue provisioning)"
echo ""

while true; do
  STATE=$(az aro show -g "$ARO_RG" -n "$CLUSTER_NAME" --query provisioningState -o tsv 2>/dev/null || echo "NotFound")
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  
  case "$STATE" in
    Succeeded)
      echo "[$TIMESTAMP] ✅ State: $STATE"
      echo ""
      CONSOLE=$(az aro show -g "$ARO_RG" -n "$CLUSTER_NAME" --query consoleProfile.url -o tsv)
      API=$(az aro show -g "$ARO_RG" -n "$CLUSTER_NAME" --query apiserverProfile.url -o tsv)
      echo "Console URL: $CONSOLE"
      echo "API URL: $API"
      echo ""
      echo "Get credentials:"
      echo "  az aro list-credentials -g $ARO_RG -n $CLUSTER_NAME"
      exit 0
      ;;
    Failed)
      echo "[$TIMESTAMP] ❌ State: $STATE"
      echo ""
      echo "Check details:"
      echo "  az aro show -g $ARO_RG -n $CLUSTER_NAME"
      exit 1
      ;;
    Creating|Updating)
      echo "[$TIMESTAMP] ⏳ State: $STATE (still provisioning...)"
      ;;
    NotFound)
      echo "[$TIMESTAMP] ⚠️  Cluster not found"
      exit 1
      ;;
    *)
      echo "[$TIMESTAMP] 🔄 State: $STATE"
      ;;
  esac
  
  sleep 30
done
