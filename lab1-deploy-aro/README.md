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

### 1. Set Environment Variables

```bash
export LOCATION=eastus
export RESOURCEGROUP=aro-rg
export CLUSTER=aro-cluster
export VNET_NAME=aro-vnet
export MASTER_SUBNET=master-subnet
export WORKER_SUBNET=worker-subnet
```

### 2. Register Required Resource Providers

```bash
az provider register -n Microsoft.RedHatOpenShift --wait
az provider register -n Microsoft.Compute --wait
az provider register -n Microsoft.Storage --wait
az provider register -n Microsoft.Authorization --wait
```

### 3. Create Resource Group

```bash
az group create \
  --name $RESOURCEGROUP \
  --location $LOCATION
```

### 4. Create Virtual Network

```bash
az network vnet create \
  --resource-group $RESOURCEGROUP \
  --name $VNET_NAME \
  --address-prefixes 10.0.0.0/22

az network vnet subnet create \
  --resource-group $RESOURCEGROUP \
  --vnet-name $VNET_NAME \
  --name $MASTER_SUBNET \
  --address-prefixes 10.0.0.0/23 \
  --service-endpoints Microsoft.ContainerRegistry

az network vnet subnet create \
  --resource-group $RESOURCEGROUP \
  --vnet-name $VNET_NAME \
  --name $WORKER_SUBNET \
  --address-prefixes 10.0.2.0/23 \
  --service-endpoints Microsoft.ContainerRegistry
```

### 5. Disable Subnet Private Endpoint Policies

```bash
az network vnet subnet update \
  --name $MASTER_SUBNET \
  --resource-group $RESOURCEGROUP \
  --vnet-name $VNET_NAME \
  --disable-private-link-service-network-policies true
```

### 6. Create the ARO Cluster

```bash
az aro create \
  --resource-group $RESOURCEGROUP \
  --name $CLUSTER \
  --vnet $VNET_NAME \
  --master-subnet $MASTER_SUBNET \
  --worker-subnet $WORKER_SUBNET \
  --apiserver-visibility Public \
  --ingress-visibility Public
```

Note: This can take 30-40 minutes to complete.

> Managed Identity Variant: For a deployment pattern that leverages managed identity and virtualization features, see the external lab here: [Azure Red Hat OpenShift Virtualization (Managed Identity)](https://github.com/heisthesisko/Azure_RedHat_OpenShift_Virtualization/tree/main). You can adapt its identity setup prior to running `az aro create` in this lab.

### 7. Get Cluster Credentials

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

### 8. Log in to the Cluster

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

## ARM Template Deployment (Alternative)

An ARM template is provided for automated deployment. See `deploy-aro.json` for details.

```bash
az deployment group create \
  --resource-group $RESOURCEGROUP \
  --template-file deploy-aro.json \
  --parameters @parameters.json
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
