// Alternative ARO network template for clean slate deployment
// Used when primary network has locked/orphaned resources

@description('Azure region for all resources')
param location string

@description('Unique suffix for network resources')
param networkSuffix string = uniqueString(resourceGroup().id)

@description('Address prefix for the virtual network')
param vnetAddressPrefix string = '10.1.0.0/16'

@description('Address prefix for the master subnet')
param masterSubnetPrefix string = '10.1.0.0/24'

@description('Address prefix for the worker subnet')
param workerSubnetPrefix string = '10.1.1.0/24'

var vnetName = 'aro-vnet-${networkSuffix}'
var masterSubnetName = 'master-subnet-${networkSuffix}'
var workerSubnetName = 'worker-subnet-${networkSuffix}'

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
  name: masterSubnetName
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
  name: workerSubnetName
  properties: {
    addressPrefix: workerSubnetPrefix
    serviceEndpoints: [
      {
        service: 'Microsoft.ContainerRegistry'
      }
    ]
  }
}

output vnetName string = vnet.name
output masterSubnetName string = masterSubnet.name
output workerSubnetName string = workerSubnet.name
output masterSubnetId string = masterSubnet.id
output workerSubnetId string = workerSubnet.id
