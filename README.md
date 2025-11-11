# OpenShift to AKS Migration Labs

This repository contains a comprehensive set of labs and tools for migrating applications from Azure Red Hat OpenShift (ARO) to Azure Kubernetes Service (AKS).

## Overview

These hands-on labs guide you through the complete process of deploying OpenShift and AKS clusters, deploying sample applications, and using automated tools to migrate workloads between platforms.

## Labs

### [Lab 1: Deploy Azure Red Hat OpenShift (ARO)](./lab1-deploy-aro/README.md)

Learn how to deploy a fully managed Azure Red Hat OpenShift cluster using Azure CLI and ARM templates.

**What you'll learn:**
- Set up Azure Red Hat OpenShift cluster
- Configure networking and subnets
- Access the OpenShift console and CLI
- Understand ARO architecture

**Time:** ~45 minutes (including cluster deployment)

### [Lab 2: Deploy Sample Application to OpenShift](./lab2-deploy-app-openshift/README.md)

Deploy a sample application to your OpenShift cluster to understand OpenShift-specific concepts.

**What you'll learn:**
- Deploy applications using OpenShift manifests
- Work with Deployments, Services, and Routes
- Use ConfigMaps for configuration
- Scale applications in OpenShift
- Export application configurations

**Time:** ~30 minutes

### [Lab 3: Deploy Azure Kubernetes Service (AKS)](./lab3-deploy-aks/README.md)

Set up an Azure Kubernetes Service cluster as the migration target.

**What you'll learn:**
- Deploy AKS cluster with Azure CLI
- Configure cluster autoscaling
- Set up Azure Container Registry integration
- Enable monitoring and add-ons
- Understand AKS networking

**Time:** ~30 minutes

### [Lab 4: Migration Script - OpenShift to AKS](./lab4-migration-script/README.md)

Use a Python-based migration tool to automatically migrate applications from ARO to AKS.

**What you'll learn:**
- Document OpenShift applications
- Transform OpenShift resources to Kubernetes
- Convert Routes to Ingress
- Deploy applications to AKS
- Verify successful migration

**Time:** ~45 minutes

## Prerequisites

Before starting these labs, ensure you have:

- **Azure Subscription**: Active subscription with Contributor access
- **Azure CLI**: Version 2.30.0 or later ([Install](https://docs.microsoft.com/cli/azure/install-azure-cli))
- **OpenShift CLI (oc)**: Latest version ([Install](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html))
- **kubectl**: Version 1.25 or later ([Install](https://kubernetes.io/docs/tasks/tools/))
- **Python**: Version 3.8 or later (for Lab 4)
- **Git**: For cloning this repository

## Quick Start

```bash
# Clone this repository
git clone https://github.com/acworkma/openshift-to-aks.git
cd openshift-to-aks

# Follow the labs in order
cd lab1-deploy-aro
# ... follow instructions in README.md

cd ../lab2-deploy-app-openshift
# ... follow instructions in README.md

cd ../lab3-deploy-aks
# ... follow instructions in README.md

cd ../lab4-migration-script
# ... follow instructions in README.md
```

## Architecture

```
┌─────────────────────────┐         ┌─────────────────────────┐
│  Azure Red Hat OpenShift │         │   Azure Kubernetes      │
│        (ARO)             │         │      Service (AKS)      │
│                          │         │                         │
│  ┌────────────────────┐ │         │  ┌────────────────────┐ │
│  │  Sample App        │ │         │  │  Migrated App      │ │
│  │  - Deployment      │ │         │  │  - Deployment      │ │
│  │  - Service         │ │──────▶  │  │  - Service         │ │
│  │  - Route           │ │ Migrate │  │  - Ingress         │ │
│  │  - ConfigMap       │ │         │  │  - ConfigMap       │ │
│  └────────────────────┘ │         │  └────────────────────┘ │
│                          │         │                         │
└─────────────────────────┘         └─────────────────────────┘
            │                                   │
            └───────────────┬───────────────────┘
                            │
                  ┌─────────▼──────────┐
                  │  Migration Script  │
                  │   (Python)         │
                  │  - Document        │
                  │  - Transform       │
                  │  - Deploy          │
                  └────────────────────┘
```

## Key Features

- **Automated Migration**: Python script handles resource transformation
- **Route to Ingress**: Automatic conversion of OpenShift Routes to Kubernetes Ingress
- **Resource Documentation**: Export all application resources from OpenShift
- **Best Practices**: Follows Azure and Kubernetes best practices
- **Comprehensive Labs**: Step-by-step instructions with examples

## Migration Process

1. **Document**: Extract all resources from OpenShift application
2. **Transform**: Convert OpenShift-specific resources to standard Kubernetes
3. **Validate**: Review transformed resources
4. **Deploy**: Apply resources to AKS cluster
5. **Verify**: Test the migrated application

## Common Migration Scenarios

### Routes to Ingress
OpenShift Routes are automatically converted to Kubernetes Ingress resources with appropriate annotations.

### DeploymentConfigs to Deployments
DeploymentConfigs are transformed to standard Kubernetes Deployments.

### Image References
Image registry references are updated to work with Azure Container Registry or other registries.

### Security Contexts
Security contexts are adjusted to work with AKS security policies.

## Support and Contributions

This is a learning resource for understanding application migration from OpenShift to AKS. 

### Contributing
Contributions are welcome! Please feel free to submit issues or pull requests.

### Getting Help
- Review the individual lab README files for detailed instructions
- Check the [Azure Documentation](https://docs.microsoft.com/azure/)
- Visit the [OpenShift Documentation](https://docs.openshift.com/)

## Clean Up

After completing the labs, remember to clean up resources to avoid charges:

```bash
# Delete ARO cluster
az aro delete --resource-group aro-rg --name aro-cluster --yes
az group delete --name aro-rg --yes

# Delete AKS cluster
az aks delete --resource-group aks-rg --name aks-cluster --yes
az group delete --name aks-rg --yes
```

## Additional Resources

- [Azure Red Hat OpenShift Documentation](https://docs.microsoft.com/azure/openshift/)
- [Azure Kubernetes Service Documentation](https://docs.microsoft.com/azure/aks/)
- [OpenShift to AKS Migration Guide](https://docs.microsoft.com/azure/architecture/guide/migrate-openshift-aks)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)

## License

This project is provided as-is for educational purposes.
