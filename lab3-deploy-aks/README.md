
# AKS Cluster Provisioning Lab

## Overview
This lab demonstrates how to provision a blank Azure Kubernetes Service (AKS) cluster using infrastructure-as-code and simple scripts. No application is deployed—focus is solely on cluster creation and validation.

## Prerequisites
- Azure CLI (`az`)
- `kubectl` CLI
- Contributor access to an Azure subscription

## Deployment
```bash
az group create --name rg-aks-lab3-aue --location australiaeast
./scripts/deploy.sh
```
The script provisions an AKS cluster named `aks-lab3` in `australiaeast`.

## Validation
```bash
./scripts/validate.sh
```
Expected: PASS and confirmation that the cluster and nodes are ready.

## Cleanup
```bash
./scripts/cleanup.sh
```
This deletes the AKS cluster and all related resources.

## (Optional) Advanced/Reference
- Infrastructure template: see `infrastructure/main.bicep` and `parameters.example.json` for IaC details.
- For advanced cluster config, see [AKS Documentation](https://docs.microsoft.com/azure/aks/).

## Next Steps
Continue to [Lab 4](../lab4-migration-script/README.md) to migrate workloads from OpenShift to AKS.
