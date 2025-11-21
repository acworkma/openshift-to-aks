# Lab 2: Deploy a Prebuilt Next.js Container on OpenShift

This lab focuses purely on deploying an existing, publicly available Next.js container image to an Azure Red Hat OpenShift cluster using Kubernetes/OpenShift manifests.

## Prerequisites
- Completed [Lab 1](../lab1-deploy-aro/README.md) – cluster accessible
- `oc` CLI installed & logged in (`oc login ...`)
- `curl` for validating the health endpoint

## Image
The deployment pulls the public image:
```
ghcr.io/acworkma/nextjs-sample:latest
```
You do NOT build or push an image in this lab.

## Environment Configuration
Optionally create a `.env` based on `.env.example` to override namespace or export directory.
```
NAMESPACE=nextjs-sample
EXPORT_DIR=exported
# Optional: override image (must be publicly accessible)
# IMAGE=ghcr.io/yourorg/alternate:tag
```

## 1. Deploy Resources
```bash
cd lab2-deploy-app-openshift
./scripts/deploy.sh
```
Applies: `configmap.yaml`, `deployment.yaml`, `service.yaml`, `route.yaml`.

## 2. Validate Deployment
```bash
./scripts/validate.sh
```
Checks rollout, service, route, and health endpoint (`/api/health`).

## 3. Access Application
```bash
ROUTE=$(oc get route nextjs-sample -o jsonpath='{.spec.host}')
curl http://$ROUTE/api/health
```
Expected JSON: `{"status":"ok" ...}`.

## 4. Export (Optional)
```bash
./scripts/export-config.sh
ls exported/
```
Captures live cluster configuration for later comparison or migration.

## 5. Cleanup
```bash
./scripts/cleanup.sh
```
Deletes the namespace and all associated resources.

## Application Details
- Image: `ghcr.io/acworkma/nextjs-sample:latest`
- Service: Port 80 → container port 3000
- Health endpoint: `/api/health`
- ConfigMap keys: `app.message`, `app.environment`
- Replicas: 2

## Troubleshooting
| Issue | Action |
|-------|--------|
| Image pull error | Confirm image is public and tag exists. |
| Route not resolving | Wait a few seconds, `oc get route` to verify host. |
| Health failing | `oc logs deployment/nextjs-sample` for errors. |
| Env vars missing | Ensure `configmap.yaml` applied before deployment. |

## Next Steps
Proceed to [Lab 3](../lab3-deploy-aks/README.md) to explore AKS deployment.
