// Minimal ARO network template (clean rebuild)
// Provides VNet + master & worker subnets required for Azure Red Hat OpenShift.
// Cluster provisioning happens separately via az aro create in deploy script.

@description('Azure region for all resources')
param location string

@description('Logical cluster name used for naming the virtual network')
param clusterName string = 'aro-lab'

@description('Address prefix for the virtual network')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Address prefix for the master subnet')
param masterSubnetPrefix string = '10.0.0.0/24'

@description('Address prefix for the worker subnet')
param workerSubnetPrefix string = '10.0.1.0/24'

// Deterministic names
var vnetName = 'aro-vnet'

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [ vnetAddressPrefix ]
    }
  }
}

// Master subnet requires privateLinkServiceNetworkPolicies disabled
resource masterSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: vnet
  name: 'master-subnet'
  properties: {
    addressPrefix: masterSubnetPrefix
    privateLinkServiceNetworkPolicies: 'Disabled'
    serviceEndpoints: [
      {
        service: 'Microsoft.ContainerRegistry'
      }
    ]
  }
}

resource workerSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: vnet
  name: 'worker-subnet'
  properties: {
    addressPrefix: workerSubnetPrefix
    serviceEndpoints: [
      {
        service: 'Microsoft.ContainerRegistry'
      }
    ]
  }
}

// Outputs consumed by deploy.sh
output vnetName string = vnet.name
output masterSubnetId string = masterSubnet.id
output workerSubnetId string = workerSubnet.id