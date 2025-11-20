
# AKS Deployment Lab

## Overview
This lab demonstrates how to deploy a prebuilt container image to Azure Kubernetes Service (AKS) using infrastructure-as-code and simple scripts. No application build or source code is included—focus is on cluster provisioning and deploying a public image.

## Prerequisites
- Azure CLI (`az`)
- `kubectl` CLI
- Contributor access to an Azure subscription

## Deployment
```bash
az group create --name rg-aks-lab-001 --location eastus
./scripts/deploy.sh
```
The script provisions an AKS cluster and deploys a sample app using a public image (e.g., `ghcr.io/acworkma/nextjs-sample:latest`).

## Validation
```bash
./scripts/validate.sh
```
Expected: PASS and printed app endpoint.

## Cleanup
```bash
./scripts/cleanup.sh
```
This deletes the AKS cluster and all related resources.

## (Optional) Advanced/Reference
- Infrastructure template: see `infrastructure/main.bicep` and `parameters.example.json` for IaC details.
- For custom images, see Azure Container Registry (ACR) docs.
- For advanced cluster config, see [AKS Documentation](https://docs.microsoft.com/azure/aks/).

## Next Steps
Continue to [Lab 4](../lab4-migration-script/README.md) to migrate your app from OpenShift to AKS.
