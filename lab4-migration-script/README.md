# Lab 4: Migration Script - OpenShift to AKS

This lab provides a Python script to document applications in OpenShift and migrate them to Azure Kubernetes Service (AKS).

## Prerequisites

- Completed [Lab 1](../lab1-deploy-aro/README.md) - ARO cluster deployed
- Completed [Lab 2](../lab2-deploy-app-openshift/README.md) - Sample app deployed to OpenShift
- Completed [Lab 3](../lab3-deploy-aks/README.md) - AKS cluster deployed
- Python 3.8 or higher
- `oc` CLI configured for OpenShift cluster
- `kubectl` CLI configured for AKS cluster

## Installation

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Set Up Kubeconfig

Ensure you have access to both clusters:

```bash
# Configure OpenShift context
oc login <openshift-api-url> -u <username> -p <password>

# Configure AKS context
az aks get-credentials --resource-group <rg> --name <aks-cluster>

# Verify contexts
kubectl config get-contexts
```

## Script Overview

The migration script (`migrate.py`) provides the following functionality:

1. **Document OpenShift Application**: Extract all resources for an application
2. **Transform Resources**: Convert OpenShift-specific resources to standard Kubernetes
3. **Generate AKS Manifests**: Create AKS-compatible manifests
4. **Deploy to AKS**: Apply the transformed resources to AKS

## Usage

### Basic Usage

```bash
# Document an OpenShift application
python migrate.py document \
  --namespace sample-app \
  --output ./output

# Transform and deploy to AKS
python migrate.py migrate \
  --namespace sample-app \
  --source-context <openshift-context> \
  --target-context <aks-context> \
  --output ./migrated
```

### Command Reference

#### Document Command

Extract and document OpenShift resources:

```bash
python migrate.py document \
  --namespace <namespace> \
  --output <output-directory> \
  [--context <openshift-context>]
```

#### Migrate Command

Migrate application from OpenShift to AKS:

```bash
python migrate.py migrate \
  --namespace <namespace> \
  --source-context <openshift-context> \
  --target-context <aks-context> \
  --output <output-directory> \
  [--apply]
```

Options:
- `--apply`: Automatically apply the transformed resources to AKS
- `--dry-run`: Show what would be done without making changes

#### Transform Command

Transform OpenShift manifests to AKS-compatible format:

```bash
python migrate.py transform \
  --input <openshift-manifest.yaml> \
  --output <aks-manifest.yaml>
```

## Migration Process

### Step 1: Document the OpenShift Application

```bash
python migrate.py document \
  --namespace sample-app \
  --output ./openshift-export
```

This creates:
- `deployments.yaml` - All deployments
- `services.yaml` - All services
- `routes.yaml` - All routes (OpenShift-specific)
- `configmaps.yaml` - All ConfigMaps
- `secrets.yaml` - All secrets
- `migration-report.json` - Metadata about the export

### Step 2: Review the Export

```bash
ls -la ./openshift-export/
cat ./openshift-export/migration-report.json
```

### Step 3: Transform Resources

The script automatically transforms:
- **Routes → Ingress**: Converts OpenShift Routes to Kubernetes Ingress
- **DeploymentConfigs → Deployments**: Converts to standard Deployments
- **Image References**: Updates to use appropriate registries
- **Security Context**: Adjusts security contexts for AKS

```bash
python migrate.py transform \
  --input ./openshift-export \
  --output ./aks-manifests
```

### Step 4: Deploy to AKS

```bash
# Switch to AKS context
kubectl config use-context <aks-context>

# Create namespace
kubectl create namespace sample-app

# Apply the transformed manifests
python migrate.py migrate \
  --namespace sample-app \
  --source-context <openshift-context> \
  --target-context <aks-context> \
  --output ./aks-manifests \
  --apply
```

### Step 5: Verify the Migration

```bash
# Check deployments
kubectl get deployments -n sample-app

# Check pods
kubectl get pods -n sample-app

# Check services
kubectl get svc -n sample-app

# Check ingress
kubectl get ingress -n sample-app
```

## Configuration File

Create a `migration-config.yaml` to customize the migration:

```yaml
source:
  context: openshift-context
  namespace: sample-app

target:
  context: aks-context
  namespace: sample-app

transformations:
  replaceImageRegistry:
    enabled: true
    source: "registry.redhat.io"
    target: "myacr.azurecr.io"
  
  createIngress:
    enabled: true
    ingressClass: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
  
  adjustSecurityContext:
    enabled: true
    runAsNonRoot: true

exclude:
  resourceTypes:
    - BuildConfig
    - ImageStream
  resourceNames:
    - default-token-*
```

Use with:

```bash
python migrate.py migrate --config migration-config.yaml
```

## Advanced Features

### Selective Migration

Migrate specific resources:

```bash
python migrate.py migrate \
  --namespace sample-app \
  --resources deployment/sample-app,service/sample-app \
  --target-context aks-context
```

### Generate Helm Chart

Convert the application to a Helm chart:

```bash
python migrate.py helm \
  --namespace sample-app \
  --output ./helm-chart
```

## Troubleshooting

### Common Issues

1. **Authentication Errors**: Ensure you're logged into both clusters
2. **Context Not Found**: Verify context names with `kubectl config get-contexts`
3. **Permission Denied**: Ensure you have appropriate RBAC permissions
4. **Image Pull Errors**: Update image references or configure image pull secrets

### Verbose Logging

```bash
python migrate.py migrate \
  --namespace sample-app \
  --source-context openshift \
  --target-context aks \
  --verbose
```

## Manual Verification Steps

After migration, verify:

1. **Pods are running**: `kubectl get pods -n sample-app`
2. **Services are created**: `kubectl get svc -n sample-app`
3. **Ingress is configured**: `kubectl get ingress -n sample-app`
4. **Application is accessible**: Test the application endpoint

## Rollback

If migration fails:

```bash
# Delete the namespace in AKS
kubectl delete namespace sample-app

# Re-run the migration with fixes
python migrate.py migrate ... --apply
```

## Additional Resources

- [Script Documentation](./SCRIPT.md)
- [Kubernetes API Reference](https://kubernetes.io/docs/reference/)
- [AKS Best Practices](https://docs.microsoft.com/azure/aks/best-practices)

## Next Steps

After successful migration:
1. Configure monitoring and logging
2. Set up CI/CD pipelines for AKS
3. Configure backup and disaster recovery
4. Optimize resource requests and limits
