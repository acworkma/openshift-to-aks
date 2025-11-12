@description('Location for all resources')
param location string

@description('Name of the ARO cluster')
param clusterName string = 'aro-cluster'

@description('Address prefix for the virtual network')
param vnetAddressPrefix string = '10.0.0.0/22'

@description('Address prefix for the master subnet')
param masterSubnetPrefix string = '10.0.0.0/23'

@description('Address prefix for the worker subnet')
param workerSubnetPrefix string = '10.0.2.0/23'

@description('Optional domain prefix for the cluster; defaults to clusterName when empty')
param domain string = ''

@secure()
@description('Red Hat pull secret (optional). Leave empty to skip.')
param pullSecret string = ''

@description('Service principal client ID (mandatory for ARO ARM deployment)')
param spClientId string

@secure()
@description('Service principal client secret (mandatory for ARO ARM deployment)')
param spClientSecret string

@description('Worker VM size')
param workerVmSize string = 'Standard_D4s_v3'

@description('Number of worker nodes')
@minValue(3)
param workerCount int = 3

@description('Master VM size')
param masterVmSize string = 'Standard_D8s_v3'

@description('Internal cluster RG suffix (short, deterministic)')
param internalSuffix string = 'int'

@description('OpenShift version (from az aro get-versions -l <region>). Leave empty for default latest.')
param openshiftVersion string = ''

@description('FIPS validated modules setting: Enabled or Disabled')
param fipsValidatedModules string = 'Disabled'

var vnetName = 'aro-vnet'
var masterSubnetName = 'master-subnet'
var workerSubnetName = 'worker-subnet'

resource vnet 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [ vnetAddressPrefix ]
    }
  }
}

resource masterSubnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' = {
  name: '${vnetName}/${masterSubnetName}'
  properties: {
    addressPrefix: masterSubnetPrefix
    serviceEndpoints: [
      {
        service: 'Microsoft.ContainerRegistry'
      }
    ]
    privateLinkServiceNetworkPolicies: 'Disabled'
  }
  dependsOn: [ vnet ]
}

resource workerSubnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' = {
  name: '${vnetName}/${workerSubnetName}'
  properties: {
    addressPrefix: workerSubnetPrefix
    serviceEndpoints: [
      {
        service: 'Microsoft.ContainerRegistry'
      }
    ]
  }
  dependsOn: [ vnet, masterSubnet ]
}

// Cluster creation moved to deploy script; template now only builds network components.
// internalClusterRg retained for reference if needed later.
var internalClusterRg = '/subscriptions/${subscription().subscriptionId}/resourceGroups/aro-${clusterName}-${internalSuffix}'

// Outputs limited to networking artifacts
output vnetName string = vnet.name
output masterSubnetId string = masterSubnet.id
output workerSubnetId string = workerSubnet.id