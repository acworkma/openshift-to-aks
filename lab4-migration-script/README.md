# Lab 4: Migration Script — OpenShift to AKS

This lab provides a Python script to document applications in OpenShift and migrate them to Azure Kubernetes Service (AKS). It exports OpenShift resources, transforms them into AKS-compatible manifests, and can optionally apply them to an AKS cluster.

## Prerequisites

- Python 3.8 or higher
- `kubectl` and (optional) `oc` installed
- Kubeconfig contexts for your OpenShift source and AKS target clusters
- Recommended: complete Lab 2 (sample app on OpenShift) and Lab 3 (AKS cluster)

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
- Document: export Deployments, Services, ConfigMaps, Secrets, and Routes from OpenShift
- Transform: convert to AKS-compatible manifests
  - Routes → Ingress (nginx class)
  - Strip `clusterIP/clusterIPs` from Services
  - Remove non-portable metadata and `status`
  - Optional: rewrite container image registry
  - Optional: remap namespace
- Apply: optionally create resources on AKS

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

# Migrate with registry rewrite (images point to ACR)
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
  --apply
```

### Options

- `--apply`: apply transformed resources to AKS
- `--registry-rewrite <registry>`: replace the registry portion of container images (e.g., `myacr.azurecr.io`)
- `--target-namespace <ns>`: override the namespace used in output and AKS deployment
- `--verbose` / `-v`: enable verbose logging

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

### Step 2: Migrate (transform) resources

Transformation happens automatically inside `migrate`:
- Routes → Ingress (nginx class)
- Services: strip `clusterIP/clusterIPs`
- All resources: remove non-portable metadata and `status`
- Images: optionally rewrite registry via `--registry-rewrite`
- Namespace: optionally override via `--target-namespace`

Outputs:
- `output/source/` — raw export from OpenShift
- `output/aks/` — transformed manifests for AKS

### Step 3: Deploy to AKS (optional)

```bash
python migrate.py migrate \
  --namespace sample-app \
  --source-context <openshift-context> \
  --target-context <aks-context> \
  --output ./aks-manifests \
  --apply
```

### Step 4: Validate on AKS

```bash
kubectl get deployments -n sample-app
kubectl get pods -n sample-app
kubectl get svc -n sample-app
kubectl get ingress -n sample-app
```

## Notes on Secrets

Secrets are exported and transformed (metadata cleanup only). Review and update them as needed before applying to AKS (e.g., image pull secrets for ACR).

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
