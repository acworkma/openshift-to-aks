# Lab 1: Azure Red Hat OpenShift (ARO) Cluster Deployment

## Overview
This lab provisions an Azure Red Hat OpenShift (ARO) cluster using an opinionated, repeatable Bicep template and helper scripts. You can either let the provided scripts orchestrate provider registration, networking, and cluster creation, or deploy manually/with the legacy ARM template. The goal: get a working ARO cluster you can use for subsequent labs.

Azure Red Hat OpenShift is a jointly engineered, managed OpenShift service by Microsoft and Red Hat. This lab keeps resources minimal while following deterministic naming and clean teardown patterns.

## Prerequisites
- Azure subscription with sufficient quota for ARO (masters + workers)
- Role: Contributor (plus ability to register resource providers)
- Tools: Azure CLI (`az`), optional OpenShift CLI (`oc`)
- (Optional) Red Hat pull secret
- (Optional) Service Principal (if not using managed identity) — store client secret securely

## Deployment
Quick start (recommended script flow) – defaults now target `centralus`:

```bash
cd lab1-deploy-aro/
cp .env.example .env
# Edit .env to adjust region, cluster name, worker count, etc.
./scripts/deploy.sh
```

The script will:
- Register required providers (idempotent)
- Create / reuse the resource group you specify (`ARO_RG`)
- Deploy networking + cluster via `infrastructure/main.bicep`
- Print console & API server URLs when available

### Manual Bicep Deployment (alternative)
You can run the Bicep template directly:

```bash
az group create --name $ARO_RG --location centralus
az deployment group create \
  --resource-group $ARO_RG \
  --template-file infrastructure/main.bicep \
  --parameters location=centralus clusterName=$CLUSTER_NAME workerCount=3
```

### Legacy ARM Template (optional)
The original ARM template remains for reference: `deploy-aro.json`.

```bash
az deployment group create \
  --resource-group $ARO_RG \
  --template-file deploy-aro.json \
  --parameters @parameters.json
```

Provisioning can take 30–40 minutes; scripts will show endpoints early even if the cluster is still finalizing.

### Service Principal Requirement
The Bicep deployment path requires a valid service principal (clientId + clientSecret). Set `SP_CLIENT_ID` and `SP_CLIENT_SECRET` in your `.env` or let the script create one automatically by setting `AUTO_CREATE_SP=true`.

Manual creation:
```bash
SUB_ID=$(az account show --query id -o tsv)
az ad sp create-for-rbac --name aro-sp-lab --role Contributor --scopes "/subscriptions/$SUB_ID" --years 1 -o json
```
Fill `.env`:
```env
SP_CLIENT_ID=<appId>
SP_CLIENT_SECRET=<password>
```
Auto-create (no pre-step needed):
```bash
AUTO_CREATE_SP=true ./scripts/deploy.sh
```

### Selecting an OpenShift Version
List available versions for your target region:
```bash
az aro get-versions -l $LOCATION -o table
```
Set `OPENSHIFT_VERSION` in `.env` (e.g. `4.17.27`) before running `./scripts/deploy.sh` to pin a version. Leave blank to let ARO choose the latest supported.

## Validation
Run the validation script at any time to check readiness:

```bash
./scripts/validate.sh
```

Success criteria:
- Script outputs `[PASS] Console URL` and `[PASS] API Server URL`
- (Optional) If `oc` installed and credentials available, node list retrieved

Manual checks:

```bash
az aro show -g $ARO_RG -n $CLUSTER_NAME --query consoleProfile.url -o tsv
az aro show -g $ARO_RG -n $CLUSTER_NAME --query apiserverProfile.url -o tsv
az aro list-credentials -g $ARO_RG -n $CLUSTER_NAME
```

Login using `oc` (after credentials are ready):

```bash
API_URL=$(az aro show -g $ARO_RG -n $CLUSTER_NAME --query apiserverProfile.url -o tsv)
KUBEADMIN_PASSWD=$(az aro list-credentials -g $ARO_RG -n $CLUSTER_NAME --query kubeadminPassword -o tsv)
oc login "$API_URL" -u kubeadmin -p "$KUBEADMIN_PASSWD" --insecure-skip-tls-verify
oc get nodes
```

## Cleanup
Teardown everything safely (idempotent):

```bash
./scripts/cleanup.sh
```

This triggers ARO cluster deletion then resource group deletion. You can re-run; missing resources are skipped.

Manual cleanup if preferred:

```bash
az aro delete -g $ARO_RG -n $CLUSTER_NAME --yes
az group delete -n $ARO_RG --yes
```

## Troubleshooting
| Issue | Cause | Resolution |
|-------|-------|------------|
| Provider registration hangs | Network or permission delay | Re-run `./scripts/deploy.sh`; it is idempotent. |
| `az aro show` returns NotFound | Cluster still provisioning | Wait and retry `./scripts/validate.sh` every few minutes. |
| `oc login` fails TLS | Insecure cert during early provisioning | Use `--insecure-skip-tls-verify` temporarily; remove once cluster stabilizes. |
| Missing kubeadmin password | Credentials not yet issued | Retry `az aro list-credentials` after a few minutes. |
| Invalid OpenShift version error | Specified version not available in region | Leave `OPENSHIFT_VERSION` blank for auto-detection or check available versions: `az aro get-versions -l $LOCATION` |
| VM size not available | Insufficient capacity in region | Try different region (centralus typically has better availability) or different VM sizes |
| Cluster creation fails | Various reasons (quota, capacity, config) | Check error output from script; verify service principal credentials, check quota limits, review troubleshooting steps in error message |
| Network deployment fails | Parameter or permission issues | Verify Bicep syntax: `az bicep build --file infrastructure/main.bicep`, check service principal has Contributor role |

### Common Deployment Failures

**OpenShift Version Errors:**
The deploy script now auto-detects available OpenShift versions for your region. If you still encounter version errors:
- Check available versions: `az aro get-versions -l centralus`
- Ensure your Azure CLI is up to date: `az upgrade`

**Regional Capacity Issues:**
If deployment fails due to capacity issues in one region:
- Try centralus (generally better availability)
- Check VM SKU availability: `az vm list-skus -l centralus -o table | grep -E 'Standard_D4s_v3|Standard_D8s_v3'`
- Consider alternative VM sizes if needed

**Service Principal Issues:**
- Verify SP credentials are valid: `az ad sp show --id $SP_CLIENT_ID`
- Ensure SP has Contributor role on subscription
- Or use `AUTO_CREATE_SP=true` to have the script create one automatically

**Monitoring Long-Running Deployments:**
Use the monitor script to track cluster provisioning:
```bash
./scripts/monitor.sh
```

This will continuously poll the cluster state and notify you when provisioning completes or fails.

## Files & Structure
- `infrastructure/main.bicep` – Bicep template for network + cluster
- `infrastructure/parameters.example.json` – Sanitized sample parameter set (centralus region)
- `scripts/deploy.sh` – Idempotent provisioning script with auto-version detection
- `scripts/validate.sh` – Cluster readiness checks
- `scripts/cleanup.sh` – Safe teardown
- `scripts/monitor.sh` – Real-time cluster provisioning monitor
- `.env.example` – Environment variable scaffolding (copy to `.env`)
- `deploy-aro.json` – Legacy ARM template (alternative)

## Next Steps
Proceed to [Lab 2](../lab2-deploy-app-openshift/README.md) to deploy a sample application onto the ARO cluster.

## Additional Resources
- [Azure Red Hat OpenShift Docs](https://learn.microsoft.com/azure/openshift/)
- [OpenShift Docs](https://docs.openshift.com/)
