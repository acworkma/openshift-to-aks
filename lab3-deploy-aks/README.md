

# AKS Cluster and Azure Container Registry Lab

## Overview
This lab provisions a blank Azure Kubernetes Service (AKS) cluster and an Azure Container Registry (ACR) using Bicep infrastructure-as-code and deployment scripts. The ACR is configured for use in Lab 4 to migrate container images from OpenShift to AKS. No application is deployed—focus is solely on cluster and registry creation, validation, and credential management.

## Prerequisites
- Azure CLI (`az`)
- `kubectl` CLI
- Contributor access to an Azure subscription

## Deployment
```bash
# Create resource group (if not exists)
az group create --name rg-aks-lab3-aue --location australiaeast

# Deploy AKS and ACR (Bicep)
./scripts/deploy.sh
```
The script provisions:
- AKS cluster named `aks-lab3` in `australiaeast`
- ACR instance with a unique name (e.g., `acrlab3<uniquestring>`)
- Outputs ACR name, login server, admin username, and admin password to `.env` for Lab 4

## Validation
```bash
./scripts/validate.sh
```
Expected: PASS for AKS cluster readiness, ACR existence, and ACR admin credentials.

The script validates:
- AKS cluster provisioning status and node availability
- ACR registry existence and admin credentials retrieval

## ACR Credentials for Lab 4
After deployment, `.env` contains:
```dotenv
ACR_NAME=<acr-name>
ACR_LOGIN_SERVER=<acr-login-server>
ACR_ADMIN_USERNAME=<admin-username>
ACR_ADMIN_PASSWORD=<admin-password>
```
These credentials are used by Lab 4 to import container images into ACR during migration.

## Cleanup
```bash
./scripts/cleanup.sh
```
This deletes the AKS cluster and ACR registry (and optionally the resource group if `CLEANUP_DELETE_RG=true` in `.env`).

## (Optional) Advanced/Reference
- Infrastructure template: see `infrastructure/main.bicep` and `parameters.example.json` for Bicep definitions.
- For advanced AKS config: [AKS Documentation](https://docs.microsoft.com/azure/aks/)
- For ACR best practices: [ACR Documentation](https://docs.microsoft.com/azure/container-registry/)

## Next Steps
Continue to [Lab 4](../lab4-migration-script/README.md) to migrate workloads from OpenShift to AKS, including container image migration to the ACR provisioned in this lab.

