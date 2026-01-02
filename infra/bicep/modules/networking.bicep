// =====================================================
// Networking Infrastructure Module
// =====================================================
// Creates hub virtual network with subnets for:
// - Azure Migrate appliance
// - Target migrated VMs
// - On-premises simulation (Hyper-V host)
// - Azure Bastion

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Deploy Azure Bastion')
param deployBastion bool = true

@description('Resource tags')
param tags object

// =====================================================
// Variables
// =====================================================

var vnetName = 'vnet-${namingPrefix}-hub'
var bastionName = 'bastion-${namingPrefix}'
var bastionPublicIpName = 'pip-${bastionName}'

var subnets = {
  migrate: {
    name: 'subnet-migrate-appliance'
    addressPrefix: '10.0.1.0/24'
  }
  target: {
    name: 'subnet-target-vms'
    addressPrefix: '10.0.2.0/24'
  }
  bastion: {
    name: 'AzureBastionSubnet' // Name is required by Azure
    addressPrefix: '10.0.3.0/26'
  }
  onprem: {
    name: 'subnet-onprem-hyperv'
    addressPrefix: '10.0.10.0/24'
  }
}

// =====================================================
// Network Security Groups
// =====================================================

// NSG for Migrate Appliance Subnet
resource nsgMigrate 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-${subnets.migrate.name}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTPS-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-Azure-Services'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'AzureCloud'
        }
      }
    ]
  }
}

// NSG for Target VMs Subnet
resource nsgTarget 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-${subnets.target.name}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-RDP-From-Bastion'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: subnets.bastion.addressPrefix
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-SSH-From-Bastion'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: subnets.bastion.addressPrefix
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-HTTP-Internal'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-HTTPS-Internal'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-SQL-Internal'
        properties: {
          priority: 140
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// NSG for On-Premises Hyper-V Subnet
resource nsgOnPrem 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-${subnets.onprem.name}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-RDP-From-Bastion'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: subnets.bastion.addressPrefix
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-Hyper-V-Management'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '5985'
            '5986'
          ]
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-Azure-Migrate-Communication'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'AzureCloud'
        }
      }
    ]
  }
}

// =====================================================
// Virtual Network
// =====================================================

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnets.migrate.name
        properties: {
          addressPrefix: subnets.migrate.addressPrefix
          networkSecurityGroup: {
            id: nsgMigrate.id
          }
        }
      }
      {
        name: subnets.target.name
        properties: {
          addressPrefix: subnets.target.addressPrefix
          networkSecurityGroup: {
            id: nsgTarget.id
          }
        }
      }
      {
        name: subnets.onprem.name
        properties: {
          addressPrefix: subnets.onprem.addressPrefix
          networkSecurityGroup: {
            id: nsgOnPrem.id
          }
        }
      }
      {
        name: subnets.bastion.name
        properties: {
          addressPrefix: subnets.bastion.addressPrefix
        }
      }
    ]
  }
}

// =====================================================
// Azure Bastion
// =====================================================

resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = if (deployBastion) {
  name: bastionPublicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2023-09-01' = if (deployBastion) {
  name: bastionName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/${subnets.bastion.name}'
          }
          publicIPAddress: {
            id: bastionPublicIp.id
          }
        }
      }
    ]
  }
}

// =====================================================
// Outputs
// =====================================================

@description('Hub VNet resource ID')
output hubVnetId string = vnet.id

@description('Hub VNet name')
output hubVnetName string = vnet.name

@description('Migrate appliance subnet ID')
output migrateSubnetId string = '${vnet.id}/subnets/${subnets.migrate.name}'

@description('Target VMs subnet ID')
output targetSubnetId string = '${vnet.id}/subnets/${subnets.target.name}'

@description('On-premises Hyper-V subnet ID')
output onpremSubnetId string = '${vnet.id}/subnets/${subnets.onprem.name}'

@description('Bastion host name')
output bastionHostName string = deployBastion ? bastion.name : ''
