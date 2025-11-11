# Lab 3: Deploy Azure Kubernetes Service (AKS)

This lab guides you through deploying an Azure Kubernetes Service (AKS) cluster.

## Prerequisites

- Azure subscription
- Azure CLI installed and configured
- Contributor access to the Azure subscription
- `kubectl` CLI installed

## Architecture Overview

Azure Kubernetes Service (AKS) is a managed Kubernetes service that makes it simple to deploy and manage containerized applications.

## Deployment Steps

### 1. Set Environment Variables

```bash
export LOCATION=eastus
export RESOURCEGROUP=aks-rg
export CLUSTER_NAME=aks-cluster
export NODE_COUNT=3
export NODE_SIZE=Standard_D2s_v3
```

### 2. Create Resource Group

```bash
az group create \
  --name $RESOURCEGROUP \
  --location $LOCATION
```

### 3. Create AKS Cluster

```bash
az aks create \
  --resource-group $RESOURCEGROUP \
  --name $CLUSTER_NAME \
  --node-count $NODE_COUNT \
  --node-vm-size $NODE_SIZE \
  --enable-managed-identity \
  --generate-ssh-keys \
  --network-plugin azure \
  --network-policy azure \
  --load-balancer-sku standard \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 5
```

Note: This can take 5-10 minutes to complete.

### 4. Get Cluster Credentials

```bash
az aks get-credentials \
  --resource-group $RESOURCEGROUP \
  --name $CLUSTER_NAME
```

This merges the cluster credentials into your `~/.kube/config` file.

### 5. Verify the Cluster

```bash
# Check nodes
kubectl get nodes

# Check system pods
kubectl get pods -n kube-system

# Get cluster info
kubectl cluster-info
```

## Advanced Configuration

### Enable Azure Container Registry (ACR) Integration

```bash
# Create ACR
ACR_NAME=myaksacr$RANDOM
az acr create \
  --resource-group $RESOURCEGROUP \
  --name $ACR_NAME \
  --sku Basic

# Attach ACR to AKS
az aks update \
  --name $CLUSTER_NAME \
  --resource-group $RESOURCEGROUP \
  --attach-acr $ACR_NAME
```

### Enable Azure Monitor for Containers

```bash
az aks enable-addons \
  --resource-group $RESOURCEGROUP \
  --name $CLUSTER_NAME \
  --addons monitoring
```

### Enable Azure Key Vault Provider for Secrets Store CSI Driver

```bash
az aks enable-addons \
  --resource-group $RESOURCEGROUP \
  --name $CLUSTER_NAME \
  --addons azure-keyvault-secrets-provider
```

## ARM Template Deployment (Alternative)

An ARM template is provided for automated deployment. See `deploy-aks.json` for details.

```bash
az deployment group create \
  --resource-group $RESOURCEGROUP \
  --template-file deploy-aks.json \
  --parameters @parameters.json
```

## Kubectl Context Management

```bash
# List contexts
kubectl config get-contexts

# Switch context
kubectl config use-context $CLUSTER_NAME

# View current context
kubectl config current-context
```

## Accessing the Kubernetes Dashboard

```bash
# Browse the dashboard
az aks browse \
  --resource-group $RESOURCEGROUP \
  --name $CLUSTER_NAME
```

## Namespace Creation

Create a namespace for your migrated application:

```bash
kubectl create namespace sample-app
```

## Network Configuration

### View Network Configuration

```bash
az aks show \
  --resource-group $RESOURCEGROUP \
  --name $CLUSTER_NAME \
  --query networkProfile
```

### Configure Load Balancer

```bash
# Get the load balancer public IP
az network public-ip list \
  --resource-group $(az aks show --resource-group $RESOURCEGROUP --name $CLUSTER_NAME --query nodeResourceGroup -o tsv) \
  --query "[0].ipAddress" -o tsv
```

## Cluster Upgrade

```bash
# Get available versions
az aks get-upgrades \
  --resource-group $RESOURCEGROUP \
  --name $CLUSTER_NAME

# Upgrade cluster
az aks upgrade \
  --resource-group $RESOURCEGROUP \
  --name $CLUSTER_NAME \
  --kubernetes-version <version>
```

## Clean Up

When you're done, delete the resource group:

```bash
az aks delete \
  --resource-group $RESOURCEGROUP \
  --name $CLUSTER_NAME \
  --yes

az group delete \
  --name $RESOURCEGROUP \
  --yes
```

## Next Steps

Proceed to [Lab 4](../lab4-migration-script/README.md) to use the Python migration script to move your application from OpenShift to AKS.

## Additional Resources

- [AKS Documentation](https://docs.microsoft.com/azure/aks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [AKS Best Practices](https://docs.microsoft.com/azure/aks/best-practices)
