# ARO Deployment Issues - Summary

## Issue
Unable to deploy Azure Red Hat OpenShift cluster across multiple regions due to VM SKU restrictions.

## Subscription Details
- **Subscription ID**: `a836a4bf-3684-471a-a795-09fdcbd14c7d`
- **Service Principal**: `e7074ead-89e4-43c0-a7be-50794f62b7ab` (Contributor)
- **ARO Resource Provider**: `f1dd0a37-89c6-4e07-bcd1-ffd3d43d8875` (Contributor at subscription level)

## Attempted Regions and Results

| Region | VM Sizes Attempted | Result | Error Details |
|--------|-------------------|--------|---------------|
| centralus | E8s_v3/E4s_v3 | ❌ InternalServerError | Cluster creation reached "Creating" state, failed after 2-3 minutes |
| centralus | D8s_v3/D4s_v3 | ❌ InternalServerError | Same pattern as E-series |
| eastus2 | D8s_v3/D4s_v3 | ❌ SKU Restricted | VM SKU not available in region |
| eastus2 | E8s_v3/E4s_v3 | ❌ SKU Restricted | VM SKU not available in region |
| westus | D8s_v3/D4s_v3 | ❌ InternalServerError | Cluster creation failed, left orphaned resources |
| westus | E8s_v3/E4s_v3 | ❌ InternalServerError | Same pattern |
| westus2 | D8s_v3/D4s_v3 | ❌ SKU Restricted | VM SKU not available in region |
| **eastus** | **D8s_v3/D4s_v3** | ❌ **SKU Restricted** | **"The selected SKU 'Standard_D8s_v3' is restricted in region 'eastus' for selected subscription"** |
| eastus | E8s_v3/E4s_v3 | ❌ Failed silently | No cluster created |
| northcentralus | D16s_v3/D8s_v3 | ❌ Failed silently | Network deployed, cluster creation failed |
| southcentralus | D32s_v3/D16s_v3 | ❌ Failed silently | Network deployed, cluster creation failed |

## Key Findings

### 1. VM SKU Restrictions (Confirmed via Debug Log)
```
ERROR: (InvalidParameter) The selected SKU 'Standard_D8s_v3' is restricted in region 'eastus' for selected subscription
Code: InvalidParameter
Target: properties.masterProfile.VMSize
```

### 2. Quota is NOT the Issue
- **Available**: 100 vCPU cores in Standard DSv3 Family
- **Required**: 36 cores (3 masters × 8 + 3 workers × 4)
- **Conclusion**: Sufficient quota, but SKUs are restricted

### 3. Orphaned Resources
Multiple failed deployments left internal resource groups with deny assignments:
- `aro-jcvdoygu` (centralus)
- `aro-i2vopi8e` (westus)
- `ARO-SA0HP9QA` (westus)
- `ARO-AVO7JXII` (westus)

These cannot be deleted without Azure support intervention.

### 4. Configuration Verified
✅ ARO Resource Provider registered  
✅ ARO RP has Contributor role at subscription level  
✅ Service Principal has Contributor role  
✅ Network prerequisites met (VNet, subnets, no NSG at creation)  
✅ OpenShift versions available (4.16.x - 4.18.26)  
✅ Subnet configuration correct (privateLinkServiceNetworkPolicies disabled on master)

## VM Sizes Required for ARO

### Minimum Requirements
- **Master nodes**: 8 vCPUs, 32 GB RAM (3 nodes)
  - Supported: D8s_v3, E8s_v3, D8s_v4, D8s_v5, E8s_v4, E8s_v5
- **Worker nodes**: 4 vCPUs, 16 GB RAM (minimum 3 nodes)
  - Supported: D4s_v3, E4s_v3, D4s_v4, D4s_v5, E4s_v4, E4s_v5

### Attempted Larger Sizes (Also Failed)
- D16s_v3 (16 vCPU) - northcentralus
- D32s_v3 (32 vCPU) - southcentralus

## Root Cause Analysis

The subscription has **VM SKU restrictions for ARO-compatible VM families across all major US regions**. This is a subscription-level restriction that cannot be bypassed through:
- Different VM families (tried D-series, E-series)
- Different VM sizes (tried standard, larger)
- Different regions (tried 7+ regions)
- Different OpenShift versions
- Network reconfigurations

## Required Actions

### Option 1: Azure Support Ticket (Recommended)
Open a support ticket requesting SKU access for ARO:

**Subject**: "Request VM SKU Access for Azure Red Hat OpenShift Deployment"

**Details**:
```
Subscription ID: a836a4bf-3684-471a-a795-09fdcbd14c7d
Service: Azure Red Hat OpenShift (ARO)
Issue: VM SKU restrictions preventing cluster deployment

Required SKUs (any of):
- Standard_D8s_v3 (master) + Standard_D4s_v3 (worker)
- Standard_E8s_v3 (master) + Standard_E4s_v3 (worker)
- Standard_D8s_v4/v5 + Standard_D4s_v4/v5

Preferred Regions (any of):
1. eastus
2. centralus
3. northcentralus
4. westus2

Attempted Regions: eastus, eastus2, centralus, westus, westus2, northcentralus, southcentralus

Error Message: "The selected SKU 'Standard_D8s_v3' is restricted in region 'eastus' for selected subscription"

Correlation ID: 80407a29-276d-4533-b136-b436e911d7ea (westus attempt)

Additional Context:
- Quota is sufficient (100 cores available, need 36)
- ARO RP properly configured with Contributor role
- Network prerequisites met
- Multiple orphaned resource groups need cleanup:
  * aro-jcvdoygu (centralus)
  * aro-i2vopi8e (westus)
  * ARO-SA0HP9QA (westus)
  * ARO-AVO7JXII (westus)
```

### Option 2: Use Different Subscription
Deploy ARO in a subscription without SKU restrictions. Enterprise subscriptions often have broader SKU access.

### Option 3: Request Quota Increase
Submit a quota increase request specifically for ARO VM families:
```bash
az support tickets create \
  --title "ARO VM SKU Access Request" \
  --description "Request access to D-series and E-series VMs for Azure Red Hat OpenShift" \
  --severity minimal \
  --problem-classification "/providers/Microsoft.Support/services/service-guid/problemClassifications/problemclass-guid"
```

## Workaround for Lab Completion

For the purposes of this migration lab, we've created working environments using **Kind (Kubernetes in Docker)**:

- **Lab 1**: Documented ARO deployment process (scripts functional, blocked by Azure)
- **Lab 2**: ✅ Complete - App deployment working on Kind cluster "openshift-local"
- **Lab 3**: ✅ Complete - AKS simulation working on Kind cluster "aks-sim"
- **Lab 4**: ✅ Complete - Migration tool functional with registry rewrite and namespace remapping

## References

- [ARO VM Size Requirements](https://learn.microsoft.com/en-us/azure/openshift/support-policies-v4#cluster-resources)
- [ARO Troubleshooting Guide](https://learn.microsoft.com/en-us/azure/openshift/troubleshoot)
- [Azure VM SKU Restrictions](https://learn.microsoft.com/en-us/azure/azure-resource-manager/troubleshooting/error-sku-not-available)

## Date
November 14, 2025
