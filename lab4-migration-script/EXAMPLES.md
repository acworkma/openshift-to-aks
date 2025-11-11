# OpenShift to AKS Migration Script Usage Examples

This document provides practical examples of using the migration script.

## Example 1: Document an OpenShift Application

Export all resources from a namespace in OpenShift:

```bash
# Basic export
python migrate.py document \
  --namespace sample-app \
  --output ./exported-app

# Export with specific context
python migrate.py document \
  --namespace my-production-app \
  --context aro-production \
  --output ./prod-export
```

**Output:**
```
./exported-app/
├── deployments.yaml
├── services.yaml
├── routes.yaml
├── configmaps.yaml
├── secrets.yaml
└── migration-report.json
```

## Example 2: Full Migration with Apply

Migrate and automatically deploy to AKS:

```bash
python migrate.py migrate \
  --namespace sample-app \
  --source-context aro-cluster \
  --target-context aks-cluster \
  --output ./migration-output \
  --apply
```

**Process:**
1. Exports resources from OpenShift
2. Transforms resources to AKS-compatible format
3. Creates namespace in AKS (if needed)
4. Applies all resources to AKS
5. Reports success/failure

## Example 3: Migration Without Auto-Apply

Review transformed resources before applying:

```bash
# Step 1: Migrate and transform
python migrate.py migrate \
  --namespace sample-app \
  --source-context aro-cluster \
  --target-context aks-cluster \
  --output ./migration-output

# Step 2: Review the transformed files
ls -la ./migration-output/aks/
cat ./migration-output/aks/deployments.yaml
cat ./migration-output/aks/ingresses.yaml

# Step 3: Manually apply if satisfied
kubectl apply -f ./migration-output/aks/ --namespace sample-app
```

## Example 4: Using Verbose Logging

Get detailed information during migration:

```bash
python migrate.py migrate \
  --namespace sample-app \
  --source-context aro-cluster \
  --target-context aks-cluster \
  --output ./migration-output \
  --verbose
```

**Sample Output:**
```
2024-01-15 10:30:00 - __main__ - INFO - Documenting application in namespace: sample-app
2024-01-15 10:30:05 - __main__ - INFO - Exported 2 deployment(s)
2024-01-15 10:30:06 - __main__ - INFO - Exported 2 service(s)
2024-01-15 10:30:07 - __main__ - INFO - Exported 1 route(s)
2024-01-15 10:30:08 - __main__ - INFO - Exported 1 configmap(s)
2024-01-15 10:30:09 - __main__ - INFO - Export complete
2024-01-15 10:30:10 - __main__ - INFO - Transformation complete
```

## Example 5: Multi-Namespace Migration

Migrate multiple applications:

```bash
#!/bin/bash
# migrate-all-apps.sh

NAMESPACES=("app1" "app2" "app3")
SOURCE_CTX="aro-cluster"
TARGET_CTX="aks-cluster"

for ns in "${NAMESPACES[@]}"; do
  echo "Migrating namespace: $ns"
  python migrate.py migrate \
    --namespace "$ns" \
    --source-context "$SOURCE_CTX" \
    --target-context "$TARGET_CTX" \
    --output "./migrations/$ns" \
    --apply
  
  if [ $? -eq 0 ]; then
    echo "✓ Successfully migrated $ns"
  else
    echo "✗ Failed to migrate $ns"
  fi
done
```

## Example 6: Pre-Migration Checklist

Before running migration, verify your setup:

```bash
# 1. Check OpenShift connection
oc login <openshift-url>
oc get projects

# 2. Check AKS connection
az aks get-credentials --resource-group <rg> --name <cluster>
kubectl get nodes

# 3. Verify contexts
kubectl config get-contexts

# 4. List available namespaces in OpenShift
oc get projects

# 5. Test the migration script help
python migrate.py --help
```

## Example 7: Post-Migration Verification

After migration, verify the deployment:

```bash
# Switch to AKS context
kubectl config use-context aks-cluster

# Check all resources
kubectl get all -n sample-app

# Check deployments in detail
kubectl describe deployment sample-app -n sample-app

# Check pods are running
kubectl get pods -n sample-app -w

# Check service endpoints
kubectl get endpoints -n sample-app

# Check ingress
kubectl get ingress -n sample-app

# Test the application
INGRESS_IP=$(kubectl get ingress sample-app -n sample-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$INGRESS_IP
```

## Example 8: Rollback After Migration

If something goes wrong:

```bash
# Delete all resources in the namespace
kubectl delete namespace sample-app

# Or delete specific resources
kubectl delete -f ./migration-output/aks/ --namespace sample-app

# Re-run migration with fixes
python migrate.py migrate \
  --namespace sample-app \
  --source-context aro-cluster \
  --target-context aks-cluster \
  --output ./migration-output-v2 \
  --apply
```

## Example 9: Selective Resource Export

Export only specific resource types:

```bash
# Document the app first
python migrate.py document \
  --namespace sample-app \
  --output ./exported

# Then manually select which files to transform
# For example, copy only deployments and services
mkdir -p ./selective-migration
cp ./exported/deployments.yaml ./selective-migration/
cp ./exported/services.yaml ./selective-migration/

# Manually apply to AKS
kubectl apply -f ./selective-migration/ -n sample-app
```

## Example 10: Integration with CI/CD

Example GitLab CI configuration:

```yaml
# .gitlab-ci.yml
stages:
  - export
  - transform
  - deploy

export_openshift:
  stage: export
  script:
    - oc login $OPENSHIFT_URL --token=$OPENSHIFT_TOKEN
    - python migrate.py document --namespace $APP_NAMESPACE --output ./export
  artifacts:
    paths:
      - export/

transform_for_aks:
  stage: transform
  dependencies:
    - export_openshift
  script:
    - python migrate.py migrate --namespace $APP_NAMESPACE --output ./migration --source-context openshift --target-context aks
  artifacts:
    paths:
      - migration/aks/

deploy_to_aks:
  stage: deploy
  dependencies:
    - transform_for_aks
  script:
    - az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER
    - kubectl apply -f ./migration/aks/ --namespace $APP_NAMESPACE
  only:
    - main
```

## Common Patterns

### Pattern 1: Test Migration in Dev First

```bash
# 1. Export from production OpenShift
python migrate.py document \
  --namespace myapp-prod \
  --context openshift-prod \
  --output ./prod-export

# 2. Deploy to dev AKS
python migrate.py migrate \
  --namespace myapp-dev \
  --source-context openshift-prod \
  --target-context aks-dev \
  --output ./dev-migration \
  --apply

# 3. Test in dev
# ... testing ...

# 4. Deploy to prod AKS
python migrate.py migrate \
  --namespace myapp-prod \
  --source-context openshift-prod \
  --target-context aks-prod \
  --output ./prod-migration \
  --apply
```

### Pattern 2: Blue-Green Migration

```bash
# Deploy to new namespace (green)
python migrate.py migrate \
  --namespace myapp-green \
  --source-context openshift \
  --target-context aks \
  --output ./green-deployment \
  --apply

# Test green deployment
# ... testing ...

# Switch traffic to green
kubectl patch service myapp-lb -n production --patch '{"spec":{"selector":{"version":"green"}}}'

# Delete old deployment (blue)
kubectl delete namespace myapp-blue
```

## Tips and Best Practices

1. **Always export first**: Use `document` command before `migrate` to review resources
2. **Test without --apply**: Review transformed resources before applying
3. **Use version control**: Commit exported and transformed resources to Git
4. **Backup OpenShift**: Take snapshots before migration
5. **Use verbose mode**: Enable `--verbose` for troubleshooting
6. **Verify contexts**: Double-check you're connected to the right clusters
7. **Start small**: Migrate a simple app first to understand the process
8. **Document changes**: Keep notes on any manual adjustments needed

## Troubleshooting

### Issue: "Context not found"
```bash
# List available contexts
kubectl config get-contexts

# Use the correct context name
python migrate.py migrate --source-context <correct-name> ...
```

### Issue: "Permission denied"
```bash
# Verify permissions in OpenShift
oc auth can-i get deployments -n sample-app

# Verify permissions in AKS
kubectl auth can-i create deployments -n sample-app
```

### Issue: "Image pull errors in AKS"
1. Update image references in transformed manifests
2. Configure image pull secrets
3. Or attach ACR to AKS cluster

## Additional Resources

- [Migration Script README](./README.md)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Azure AKS Documentation](https://docs.microsoft.com/azure/aks/)
