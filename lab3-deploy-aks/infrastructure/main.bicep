
@description('The name of the AKS cluster')
param clusterName string = 'aks-lab3'
@description('The location for all resources')
param location string = resourceGroup().location
@description('Optional DNS prefix for the AKS API server')
param dnsPrefix string = '${clusterName}-dns'
@description('The number of nodes for the cluster')
param nodeCount int = 3
@description('The size of the Virtual Machine')
param nodeVMSize string = 'Standard_D2s_v3'
@description('The version of Kubernetes')
param kubernetesVersion string = '1.33'
@description('Enable cluster autoscaler')
param enableAutoScaling bool = true
@description('Minimum number of nodes for auto-scaling')
param minNodeCount int = 1
@description('Maximum number of nodes for auto-scaling')
param maxNodeCount int = 5
@description('Network plugin used for building Kubernetes network')
@allowed(['azure', 'kubenet'])
param networkPlugin string = 'azure'
@description('Enable RBAC on the AKS cluster')
param enableRBAC bool = true

@description('The name of the Azure Container Registry')
param acrName string = 'acrlab3${uniqueString(resourceGroup().id)}'
@description('The SKU of the Azure Container Registry')
@allowed(['Basic', 'Standard', 'Premium'])
param acrSku string = 'Standard'

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: true
  }
}

resource aks 'Microsoft.ContainerService/managedClusters@2023-05-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: dnsPrefix
    kubernetesVersion: kubernetesVersion
    enableRBAC: enableRBAC
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: nodeCount
        vmSize: nodeVMSize
        osType: 'Linux'
        mode: 'System'
        enableAutoScaling: enableAutoScaling
        minCount: enableAutoScaling ? minNodeCount : null
        maxCount: enableAutoScaling ? maxNodeCount : null
        type: 'VirtualMachineScaleSets'
      }
    ]
    networkProfile: {
      networkPlugin: networkPlugin
      loadBalancerSku: 'standard'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
    }
  }
  dependsOn: [ acr ]
}

output controlPlaneFQDN string = aks.properties.fqdn
output clusterName string = clusterName
output acrLoginServer string = acr.properties.loginServer
output acrName string = acr.name
output acrAdminUsername string = acr.listCredentials().username
output acrAdminPassword string = acr.listCredentials().passwords[0].value
