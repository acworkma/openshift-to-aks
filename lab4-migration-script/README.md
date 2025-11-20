# Lab 4: Migration Script — OpenShift to AKS

This lab provides a Python script to document applications in OpenShift and migrate them to Azure Kubernetes Service (AKS). It exports OpenShift resources, transforms them into AKS-compatible manifests, and can optionally apply them to an AKS cluster. **New:** Automated container image import to Azure Container Registry (ACR) is supported, allowing seamless migration of images referenced in your application manifests.

## Prerequisites

- Python 3.8 or higher
- `kubectl` and (optional) `oc` installed
- Azure CLI (`az`) for ACR image import
- Kubeconfig contexts for your OpenShift source and AKS target clusters
- Recommended: complete Lab 2 (sample app on OpenShift) and Lab 3 (AKS cluster + ACR)
- If using ACR import: `.env` file from Lab 3 containing ACR credentials

## Install Dependencies

```bash
pip install -r requirements.txt
```

## Configure Contexts

```bash
# Login to OpenShift (optional if kubeconfig already set)
oc login <openshift-api-url> -u <username> -p <password>

# Get AKS credentials
az aks get-credentials --resource-group <rg> --name <aks-cluster>

# Verify
kubectl config get-contexts
```

## Script Overview


`migrate.py` provides:
- Document: export Deployments, StatefulSets, Jobs, CronJobs, Services, ConfigMaps, Secrets, PVCs, ServiceAccounts, DeploymentConfigs, and Routes from OpenShift. Warns on BuildConfigs, ImageStreams, Templates, SCCs, and CRDs.
- Transform: convert to AKS-compatible manifests
  - Routes → Ingress (nginx class)
  - DeploymentConfigs → Deployments (basic conversion)
  - Strip `clusterIP/clusterIPs` from Services
  - Remove non-portable metadata and `status`
  - Optional: rewrite container image registry (including image pull secrets for ACR)
  - Optional: remap namespace
  - PVCs: storageClassName mapping (manual review may be required)
  - CronJobs: ensure apiVersion compatibility
- **ACR Image Import (New)**: automatically extract all unique container images from manifests, import them to ACR using `az acr import`, and rewrite image references to use the ACR login server.
- Apply: optionally create resources on AKS (Deployments, StatefulSets, Jobs, CronJobs, Services, ConfigMaps, Secrets, PVCs, ServiceAccounts, Ingress)

### Supported Resources

- Deployments, StatefulSets, Jobs, CronJobs, Services, ConfigMaps, Secrets, PVCs, ServiceAccounts, DeploymentConfigs (converted), Routes (as Ingress)
- Warns on: BuildConfigs, ImageStreams, Templates, SCCs, CRDs (manual migration may be required)

### CLI and Interactive Usage

- All required arguments can be provided as CLI flags or will be prompted interactively.
- Confirmation is required before applying resources to AKS.

### Output Structure

- `output/source/` — raw export from OpenShift (YAML per resource type)
- `output/aks/` — transformed manifests for AKS (YAML per resource type)
- `migration-report.json` — summary of exported resources

### Assumptions and Limitations

- BuildConfigs, ImageStreams, Templates, SCCs, and CRDs are not migrated; warnings are issued.
- DeploymentConfig conversion is basic; review output for advanced features.
- PVC storageClassName mapping may require manual adjustment for AKS compatibility.
- Image pull secrets are rewritten for ACR if `--registry-rewrite` is used, but credentials must be valid for the target registry.
- Custom resources and advanced OpenShift features may require manual migration.
- **ACR import requires Azure CLI (`az`) and valid ACR credentials in `.env`.**

## Usage

### Document an OpenShift application

```bash
python migrate.py document \
  --namespace sample-app \
  --output ./output \
  [--context <openshift-context>]
```

### Migrate (transform) and optionally apply to AKS

```bash
# Basic migration without registry rewrite
python migrate.py migrate \
  --namespace sample-app \
  --source-context <openshift-context> \
  --target-context <aks-context> \
  --output ./migrated

# Migrate with ACR import (recommended workflow after Lab 3)
# This will:
# 1. Extract all container images from manifests
# 2. Import them to ACR using az acr import
# 3. Rewrite image references to use ACR login server
python migrate.py migrate \
  --namespace sample-app \
  --source-context <openshift-context> \
  --target-context <aks-context> \
  --output ./migrated \
  --acr-env-path ../lab3-deploy-aks/.env \
  --apply

# Migrate with manual registry rewrite (if ACR credentials not in .env)
python migrate.py migrate \
  --namespace sample-app \
  --source-context <openshift-context> \
  --target-context <aks-context> \
  --output ./migrated \
  --registry-rewrite myacr.azurecr.io \
  --apply

# Migrate into a different namespace on AKS
python migrate.py migrate \
  --namespace sample-app \
  --source-context <openshift-context> \
  --target-context <aks-context> \
  --output ./migrated \
  --target-namespace sample-app-prod \
  --acr-env-path ../lab3-deploy-aks/.env \
  --apply
```

### Options

- `--apply`: apply transformed resources to AKS
- `--registry-rewrite <registry>`: replace the registry portion of container images (e.g., `myacr.azurecr.io`)
- `--target-namespace <ns>`: override the namespace used in output and AKS deployment
- `--acr-env-path <path>`: path to `.env` file with ACR credentials (enables automatic image import to ACR)
- `--verbose` / `-v`: enable verbose logging

## ACR Image Import (New Feature)

When `--acr-env-path` is provided, the script will:
1. Load ACR credentials from the `.env` file (expects `ACR_NAME`, `ACR_LOGIN_SERVER`, `ACR_ADMIN_USERNAME`, `ACR_ADMIN_PASSWORD`)
2. Extract all unique container images referenced in exported manifests (Deployments, StatefulSets, Jobs, CronJobs, DeploymentConfigs)
3. Import each image to ACR using `az acr import --name <acr> --source <image> --image <image-name> --force`
4. Rewrite all image references in the transformed manifests to use the ACR login server

This automates the image migration process, ensuring that all container images are available in your Azure environment and reducing external registry dependencies.

**Prerequisites for ACR Import:**
- Azure CLI (`az`) installed and authenticated
- `.env` file from Lab 3 with ACR credentials populated by `deploy.sh`
- Network connectivity to source registries and ACR

**Example .env (from Lab 3):**
```dotenv
ACR_NAME=acrlab3abc123
ACR_LOGIN_SERVER=acrlab3abc123.azurecr.io
ACR_ADMIN_USERNAME=acrlab3abc123
ACR_ADMIN_PASSWORD=<password>
```

## Migration Flow

### Step 1: Document the OpenShift application

```bash
python migrate.py document \
  --namespace sample-app \
  --output ./openshift-export
```

Generated files:
- `deployments.yaml`, `services.yaml`, `configmaps.yaml`, `secrets.yaml`, `routes.yaml` (if present)
- `migration-report.json` — summary of exported counts

### Step 2: Migrate (transform) resources with ACR import

Transformation and ACR import happen automatically inside `migrate`:
- Routes → Ingress (nginx class)
- Services: strip `clusterIP/clusterIPs`
- All resources: remove non-portable metadata and `status`
- Images: extract, import to ACR, and rewrite references to ACR login server
- Namespace: optionally override via `--target-namespace`

```bash
python migrate.py migrate \
  --namespace sample-app \
  --source-context <openshift-context> \
  --target-context <aks-context> \
  --output ./aks-manifests \
  --acr-env-path ../lab3-deploy-aks/.env \
  --apply
```

Outputs:
- `output/source/` — raw export from OpenShift
- `output/aks/` — transformed manifests for AKS with ACR image references

### Step 3: Validate on AKS

```bash
kubectl get deployments -n sample-app
kubectl get pods -n sample-app
kubectl get svc -n sample-app
kubectl get ingress -n sample-app
```

## Notes on Secrets and ACR

- Secrets are exported and transformed (metadata cleanup only). Review and update them as needed before applying to AKS (e.g., image pull secrets for ACR).
- If using ACR import, image pull secrets may not be required for the ACR if AKS is configured with ACR integration (see [AKS ACR Integration](https://docs.microsoft.com/azure/aks/cluster-container-registry-integration)).

## Troubleshooting

- Authentication: ensure contexts are configured (`kubectl config get-contexts`)
- RBAC: verify permissions on both clusters
- Image pulls: rewrite registry (`--registry-rewrite`) and configure image pull secrets
- Verbose logs: add `--verbose` to `migrate` or `document`

```bash
python migrate.py migrate \
  --namespace sample-app \
  --source-context openshift \
  --target-context aks \
  --verbose
```

## Additional Resources

- Kubernetes API Reference: https://kubernetes.io/docs/reference/
- AKS Best Practices: https://learn.microsoft.com/azure/aks/best-practices
