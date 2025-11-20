# Lab 2: Build & Deploy Next.js App on OpenShift

This lab demonstrates building a containerized Next.js application, pushing it to GitHub Container Registry (GHCR), and deploying it to Azure Red Hat OpenShift using Kubernetes manifests.

## Prerequisites
- Completed [Lab 1](../lab1-deploy-aro/README.md) – cluster accessible
- `oc` CLI installed & logged in (`oc login ...`)
- Docker (or compatible) CLI for image build
- GHCR credentials (`docker login ghcr.io`)
- `curl` for validation

## Environment Configuration
Edit `.env.example` and copy to `.env` if needed:
```
NAMESPACE=nextjs-sample
IMAGE=ghcr.io/acworkma/nextjs-sample:latest
EXPORT_DIR=exported
```

## 1. Build & Push Image
```bash
cd lab2-deploy-app-openshift
./scripts/build-image.sh
```

## 2. Deploy Resources
```bash
./scripts/deploy.sh
```
Applies: `configmap.yaml`, `deployment.yaml`, `service.yaml`, `route.yaml`.

## 3. Validate Deployment
```bash
./scripts/validate.sh
```
Checks rollout, service, route, and health endpoint (`/api/health`).

## 4. Access Application
```bash
ROUTE=$(oc get route nextjs-sample -o jsonpath='{.spec.host}')
curl http://$ROUTE/api/health
```
Expect JSON `{"status":"ok" ...}`.

## 5. Export (Optional)
```bash
./scripts/export-config.sh
ls exported/
```

## 6. Cleanup
```bash
./scripts/cleanup.sh
```

## Application Details
- Image: `ghcr.io/acworkma/nextjs-sample:latest`
- Container port: 3000 (Service exposes 80 → 3000)
- Health endpoint: `/api/health`
- ConfigMap keys: `app.message`, `app.environment` → env vars `APP_MESSAGE`, `APP_ENVIRONMENT`
- Replicas: 2 default

## Troubleshooting
| Issue | Action |
|-------|--------|
| Image pull error | Verify push & GHCR visibility (public or token). |
| Route not resolving | Wait a few seconds; check `oc get route`. |
| Health failing | Check logs `oc logs deployment/nextjs-sample`. |
| Env vars missing | Confirm ConfigMap applied before Deployment. |

## Next Steps
Continue to [Lab 3](../lab3-deploy-aks/README.md) for AKS deployment.
