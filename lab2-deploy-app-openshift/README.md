# Lab 2: Deploy Sample Application to OpenShift

This lab guides you through deploying a sample application to your Azure Red Hat OpenShift cluster.

## Prerequisites

- Completed [Lab 1](../lab1-deploy-aro/README.md) - ARO cluster deployed and accessible
- `oc` CLI installed and logged into the cluster
- `kubectl` CLI (optional)

## Sample Application

We'll deploy a simple Python Flask application that demonstrates:
- Deployment configuration
- Service exposure
- Route creation
- ConfigMaps and environment variables

## Deployment Steps

### 1. Create a New Project

```bash
oc new-project sample-app
```

### 2. Deploy the Application Using Manifests

Apply the Kubernetes manifests provided in this lab:

```bash
oc apply -f deployment.yaml
oc apply -f service.yaml
oc apply -f route.yaml
oc apply -f configmap.yaml
```

### 3. Verify the Deployment

```bash
# Check deployment status
oc get deployments

# Check pods
oc get pods

# Check service
oc get svc

# Check route
oc get route
```

### 4. Access the Application

```bash
# Get the application URL
ROUTE_URL=$(oc get route sample-app -o jsonpath='{.spec.host}')
echo "Application URL: http://$ROUTE_URL"

# Test the application
curl http://$ROUTE_URL
```

### 5. Scale the Application

```bash
# Scale to 3 replicas
oc scale deployment/sample-app --replicas=3

# Verify scaling
oc get pods
```

## Alternative: Deploy Using Source-to-Image (S2I)

OpenShift can build container images directly from source code:

```bash
# Create a new app from Git repository
oc new-app python:3.9~https://github.com/sclorg/django-ex.git

# Expose the service
oc expose svc/django-ex

# Get the route
oc get route django-ex
```

## Application Details

The sample application includes:
- **Deployment**: Defines the application pods and replicas
- **Service**: Provides internal load balancing
- **Route**: Exposes the service externally
- **ConfigMap**: Stores configuration data

## Monitoring

### View Logs

```bash
# Get logs from a specific pod
POD_NAME=$(oc get pods -l app=sample-app -o jsonpath='{.items[0].metadata.name}')
oc logs $POD_NAME

# Stream logs
oc logs -f $POD_NAME
```

### Describe Resources

```bash
oc describe deployment sample-app
oc describe pod $POD_NAME
```

## Troubleshooting

### Pod Not Starting

```bash
oc describe pod <pod-name>
oc logs <pod-name>
```

### Service Not Accessible

```bash
oc get endpoints
oc describe service sample-app
```

## Export Application Configuration

Export the application configuration for migration:

```bash
# Export deployment
oc get deployment sample-app -o yaml > sample-app-deployment.yaml

# Export service
oc get service sample-app -o yaml > sample-app-service.yaml

# Export route
oc get route sample-app -o yaml > sample-app-route.yaml

# Export configmap
oc get configmap sample-app-config -o yaml > sample-app-configmap.yaml
```

## Clean Up

```bash
# Delete the project (removes all resources)
oc delete project sample-app
```

## Next Steps

Proceed to [Lab 3](../lab3-deploy-aks/README.md) to deploy an Azure Kubernetes Service cluster.

## Additional Resources

- [OpenShift Developer Guide](https://docs.openshift.com/container-platform/latest/applications/creating_applications/creating-applications.html)
- [Source-to-Image (S2I)](https://docs.openshift.com/container-platform/latest/openshift_images/using-s21.html)
