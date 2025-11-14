# Deploy ARO via Azure Portal

Since CLI deployments are blocked by VM SKU restrictions, try the Azure Portal which may have different validation logic or show additional VM size options.

## Prerequisites

You'll need these values from our CLI setup:

```bash
# Run these commands to get the required values:
cd /workspaces/openshift-to-aks/lab1-deploy-aro

# Get Subscription ID
az account show --query id -o tsv

# Get Service Principal details
echo "Client ID: e7074ead-89e4-43c0-a7be-50794f62b7ab"
echo "Client Secret: $(grep '"password":' deploy-eastus-debug2.log | cut -d'"' -f4 | head -1)"

# Get Resource Group and VNet details for eastus
echo "Resource Group: rg-aro-lab-eastus"
echo "VNet: aro-vnet"
az network vnet subnet show -g rg-aro-lab-eastus --vnet-name aro-vnet -n master-subnet --query id -o tsv
az network vnet subnet show -g rg-aro-lab-eastus --vnet-name aro-vnet -n worker-subnet --query id -o tsv
```

## Step-by-Step Portal Deployment

### 1. Navigate to ARO Creation
- Open: https://portal.azure.com/#create/Microsoft.OpenShiftCluster
- Or search "Azure Red Hat OpenShift" in the Azure Portal marketplace

### 2. Basics Tab

**Project Details:**
- Subscription: Select your subscription
- Resource Group: Use existing `rg-aro-lab-eastus` (or create new for different region)
- Region: Try these in order:
  1. **East US** (network already deployed)
  2. Central US
  3. West US 2
  4. North Central US

**Cluster Details:**
- Resource name: `aro-cluster-portal`
- OpenShift version: `4.18.26` (or latest available)

**Pull Secret:**
- Leave empty or get from: https://console.redhat.com/openshift/install/pull-secret

Click **Next: Authentication**

### 3. Authentication Tab

**Service Principal:**
- Client ID: `e7074ead-89e4-43c0-a7be-50794f62b7ab`
- Client Secret: `<paste from command above>`

**Red Hat pull secret:**
- Optional: Leave empty for this test

Click **Next: Networking**

### 4. Networking Tab

**Virtual Network:**
- Use existing virtual network: **Yes**
- Virtual network: `aro-vnet` (if using rg-aro-lab-eastus)
- Master subnet: `master-subnet`
- Worker subnet: `worker-subnet`

**Network Connectivity:**
- API server visibility: **Public**
- Ingress visibility: **Public**

Click **Next: Virtual Machine Sizes**

### 5. Virtual Machine Sizes Tab

**CRITICAL - Try VM sizes in this order:**

**Option 1 - Standard sizes (if available):**
- Master VM size: `Standard_D8s_v3`
- Worker VM size: `Standard_D4s_v3`
- Worker count: `3`

**Option 2 - E-series (if D-series unavailable):**
- Master VM size: `Standard_E8s_v3`
- Worker VM size: `Standard_E4s_v3`
- Worker count: `3`

**Option 3 - Larger sizes (if smaller unavailable):**
- Master VM size: `Standard_D16s_v3` or `Standard_E16s_v3`
- Worker VM size: `Standard_D8s_v3` or `Standard_E8s_v3`
- Worker count: `3`

**Option 4 - v4 or v5 generations:**
- Master VM size: `Standard_D8s_v4` or `Standard_D8s_v5`
- Worker VM size: `Standard_D4s_v4` or `Standard_D4s_v5`
- Worker count: `3`

> **Note**: The Portal may show different VM sizes than the CLI. Browse the dropdown to see all available options.

Click **Next: Tags**

### 6. Tags Tab (Optional)
Add tags if needed:
- `environment`: `lab`
- `purpose`: `openshift-to-aks-migration`

Click **Next: Review + create**

### 7. Review + Create

**Review all settings:**
- Check for any validation errors
- Pay special attention to VM size availability messages

**If you see errors:**
- **"VM size not available"**: Go back and try different VM sizes from the dropdown
- **"Subnet has NSG attached"**: Run cleanup script below
- **"Network requirements not met"**: Verify subnets are clean

**If validation passes:**
- Click **Create**
- Deployment will take 30-45 minutes

### 8. Monitor Deployment

**In the Portal:**
- Go to "Deployments" in the resource group
- Watch for status changes
- Check "Activity log" for detailed messages

**Or use CLI to monitor:**
```bash
# Watch deployment status
watch -n 30 'az aro show -g rg-aro-lab-eastus -n aro-cluster-portal --query "{State:provisioningState,Created:systemData.createdAt}" -o table 2>&1'

# Check for any errors
az aro show -g rg-aro-lab-eastus -n aro-cluster-portal 2>&1 | grep -i error
```

## If Subnet Cleanup Needed

If Portal shows NSG errors, run this before trying again:

```bash
cd /workspaces/openshift-to-aks/lab1-deploy-aro

# Remove NSGs from subnets
az network vnet subnet update \
  -g rg-aro-lab-eastus \
  --vnet-name aro-vnet \
  -n master-subnet \
  --remove networkSecurityGroup

az network vnet subnet update \
  -g rg-aro-lab-eastus \
  --vnet-name aro-vnet \
  -n worker-subnet \
  --remove networkSecurityGroup

echo "Subnets cleaned. Try Portal deployment again."
```

## Alternative: Try New Region in Portal

If East US still shows restrictions, create a fresh deployment in a different region:

### Option A: Use Portal to Create Everything Fresh

1. **Region**: Select **North Central US** or **South Central US**
2. **Resource Group**: Create new `rg-aro-portal-test`
3. **Virtual Network**: Select "Create new"
   - VNet name: `aro-portal-vnet`
   - Master subnet: `10.0.0.0/23` (512 IPs)
   - Worker subnet: `10.0.2.0/23` (512 IPs)
4. **VM Sizes**: Browse dropdown for available options in that region
5. Create and monitor

### Option B: Use Our Scripts for New Region

```bash
cd /workspaces/openshift-to-aks/lab1-deploy-aro

# Pick a region and deploy network
LOCATION=northcentralus  # or southcentralus, uksouth, etc.

az group create --name rg-aro-${LOCATION} --location $LOCATION

az deployment group create \
  --resource-group rg-aro-${LOCATION} \
  --name aroNetwork \
  --template-file infrastructure/main.bicep \
  --parameters location=${LOCATION} clusterName=aro-cluster

# Then use Portal to create cluster using this VNet
echo "VNet deployed in ${LOCATION}"
echo "Now use Azure Portal to create ARO cluster"
echo "Resource Group: rg-aro-${LOCATION}"
echo "VNet: aro-vnet"
```

## What to Look For in Portal

The Portal may reveal:

1. **Different VM sizes available** - The dropdown may show sizes not listed by CLI
2. **Clearer error messages** - Portal validation often provides better guidance
3. **Regional differences** - Portal shows real-time availability per region
4. **Alternative configurations** - May suggest different subnet sizes or configurations

## Success Indicators

**If successful, you'll see:**
- Deployment starts (not immediate failure)
- Cluster resource appears in resource group
- `provisioningState` changes to "Creating"
- Internal resource group created (name like `aro-xxxxxxxx`)
- After 30-45 minutes: `provisioningState` becomes "Succeeded"

**To access your cluster:**
```bash
# Get console URL
az aro show -g rg-aro-lab-eastus -n aro-cluster-portal --query consoleProfile.url -o tsv

# Get credentials
az aro list-credentials -g rg-aro-lab-eastus -n aro-cluster-portal

# Login with oc CLI
oc login <api-server> -u kubeadmin -p <password>
```

## If Portal Also Fails

If the Portal deployment also fails with VM size restrictions, the issue is definitely subscription-level SKU access. Next steps:

1. **Open Azure Support Ticket** (see DEPLOYMENT_BLOCKERS.md)
2. **Try different subscription** if available
3. **Continue labs with Kind clusters** (Labs 2-4 are complete and functional)

## Quick Access Links

- Azure Portal ARO: https://portal.azure.com/#create/Microsoft.OpenShiftCluster
- Red Hat Pull Secret: https://console.redhat.com/openshift/install/pull-secret
- ARO Documentation: https://learn.microsoft.com/en-us/azure/openshift/
- VM Size Requirements: https://learn.microsoft.com/en-us/azure/openshift/support-policies-v4#cluster-resources

---

**Created**: November 14, 2025  
**Purpose**: Workaround for CLI VM SKU restrictions
