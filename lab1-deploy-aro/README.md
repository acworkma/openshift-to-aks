# Lab 1: Deploy Azure Red Hat OpenShift (ARO)

This lab guides you through deploying an Azure Red Hat OpenShift (ARO) cluster.

## Prerequisites

- Azure subscription
- Azure CLI installed and configured
- Contributor access to the Azure subscription
- Red Hat pull secret (optional but recommended)

### (Optional) VM Size Availability Preflight

Before deploying, confirm the target master/worker VM size is available in your subscription/regions. Example for `Standard_D8s_v5`:

```bash
az vm list-skus --size Standard_D8s_v5 --all --output table
```

If the size shows restrictions for your desired region, choose a fallback (e.g. `Standard_D8s_v4`, `Standard_D8s_v3`) or run the provided `scripts/preflight.sh` which performs multi-region size and quota checks.

## Architecture Overview

Azure Red Hat OpenShift is a fully managed OpenShift service jointly engineered and supported by Microsoft and Red Hat.

## Deployment Steps

### 1. Deploy ARO Using Managed Identity

This lab uses a managed identity deployment pattern. Follow the comprehensive guide from the Azure Red Hat OpenShift Virtualization repository:

**[Azure Red Hat OpenShift Virtualization - Managed Identity Deployment](https://github.com/heisthesisko/Azure_RedHat_OpenShift_Virtualization)**

The external repository provides:
- Automated setup of resource providers, resource groups, and virtual networks
- Managed identity configuration for secure, passwordless authentication
- ARO cluster deployment with best-practice networking
- OpenShift Virtualization features and configuration

Clone and follow the instructions in that repository to provision your ARO cluster. Once deployment completes, return here to proceed with credential retrieval and validation.

**Quick start:**
```bash
git clone https://github.com/heisthesisko/Azure_RedHat_OpenShift_Virtualization.git
cd Azure_RedHat_OpenShift_Virtualization
# Follow the README deployment instructions
```

> **Note**: The managed identity approach eliminates the need for service principal credentials and provides enhanced security and operational simplicity. Deployment typically takes 30-40 minutes.

### 2. Get Cluster Credentials

```bash
# Get the console URL
az aro show \
  --name $CLUSTER \
  --resource-group $RESOURCEGROUP \
  --query "consoleProfile.url" -o tsv

# Get the API server URL
az aro show \
  --name $CLUSTER \
  --resource-group $RESOURCEGROUP \
  --query "apiserverProfile.url" -o tsv

# Get cluster credentials
az aro list-credentials \
  --name $CLUSTER \
  --resource-group $RESOURCEGROUP
```

### 3. Log in to the Cluster

```bash
# Get credentials
API_SERVER=$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query apiserverProfile.url -o tsv)
KUBEADMIN_PASSWD=$(az aro list-credentials --name $CLUSTER --resource-group $RESOURCEGROUP --query kubeadminPassword -o tsv)

# Login using oc CLI
oc login $API_SERVER -u kubeadmin -p $KUBEADMIN_PASSWD
```

## Verification

Verify the cluster is running:

```bash
oc get nodes
oc get clusterversion
```

## Clean Up

When you're done, delete the resource group:

```bash
az aro delete --resource-group $RESOURCEGROUP --name $CLUSTER --yes
az group delete --name $RESOURCEGROUP --yes
```

## Next Steps

Proceed to [Lab 2](../lab2-deploy-app-openshift/README.md) to deploy a sample application to your ARO cluster.

Explore a managed identity & virtualization deployment pattern: [Azure_RedHat_OpenShift_Virtualization](https://github.com/heisthesisko/Azure_RedHat_OpenShift_Virtualization/tree/main)

## Additional Resources

- [Azure Red Hat OpenShift Documentation](https://docs.microsoft.com/azure/openshift/)
- [OpenShift Documentation](https://docs.openshift.com/)
