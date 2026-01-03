// =====================================================
// Azure Migrate Demo - Main Orchestration Template
// =====================================================
// This template deploys a complete Azure Migrate demo environment including:
// - Azure Migrate Hub with project and tools
// - Networking infrastructure (Hub VNet, Bastion)
// - Hyper-V host VM for on-premises simulation
// - Landing zone for migrated VMs
// - Monitoring and logging infrastructure

targetScope = 'subscription'

// =====================================================
// Parameters
// =====================================================

@description('Primary Azure region for deployment')
@allowed([
  'centralus'
  'westeurope'
  'westus2'
  'northeurope'
  'eastasia'
  'southeastasia'
  'uksouth'
  'canadacentral'
  'australiaeast'
])
param location string 

@description('Environment prefix for resource naming')
@minLength(3)
@maxLength(10)
param environmentPrefix string = 'migrate'

@description('Administrator username for VMs')
param adminUsername string = 'azureadmin'

@description('Administrator password for VMs')
@secure()
param adminPassword string

@description('Deploy Hyper-V host VM for on-premises simulation')
param deployHyperVHost bool = true

@description('Deploy Azure Bastion for secure VM access')
param deployBastion bool = true

@description('Hyper-V host VM size (must support nested virtualization)')
@allowed([
  'Standard_D16s_v5'
  'Standard_D16s_v4'
  'Standard_E16s_v5'
  'Standard_D8s_v5'
])
param hypervHostVmSize string = 'Standard_D16s_v5'

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'Demo'
  Project: 'Azure-Migrate'
  ManagedBy: 'Bicep'
  Purpose: 'Migration-Demo'
  SecurityControl: 'Ignore'
}

// =====================================================
// Variables
// =====================================================

var resourceGroupNames = {
  hub: 'rg-${environmentPrefix}-hub'
  network: 'rg-${environmentPrefix}-network'
  target: 'rg-${environmentPrefix}-target'
  monitor: 'rg-${environmentPrefix}-monitor'
  onprem: 'rg-${environmentPrefix}-onprem'
}

var namingPrefix = '${environmentPrefix}-${uniqueString(subscription().subscriptionId, location)}'

// =====================================================
// Resource Groups
// =====================================================

resource rgHub 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupNames.hub
  location: location
  tags: tags
}

resource rgNetwork 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupNames.network
  location: location
  tags: tags
}

resource rgTarget 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupNames.target
  location: location
  tags: tags
}

resource rgMonitor 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupNames.monitor
  location: location
  tags: tags
}

resource rgOnPrem 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupNames.onprem
  location: location
  tags: tags
}

// =====================================================
// Module: Monitoring Infrastructure
// =====================================================

module monitoring './modules/monitoring.bicep' = {
  scope: rgMonitor
  name: 'deploy-monitoring-${deployment().name}'
  params: {
    location: location
    namingPrefix: namingPrefix
    tags: tags
  }
}

// =====================================================
// Module: Networking Infrastructure
// =====================================================

module networking './modules/networking.bicep' = {
  scope: rgNetwork
  name: 'deploy-networking-${deployment().name}'
  params: {
    location: location
    namingPrefix: namingPrefix
    deployBastion: deployBastion
    tags: tags
  }
}

// =====================================================
// Module: Azure Migrate Hub
// =====================================================

module migrateHub './modules/migrate-hub.bicep' = {
  scope: rgHub
  name: 'deploy-migrate-hub-${deployment().name}'
  params: {
    location: location
    namingPrefix: namingPrefix
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    enableDiagnostics: false // Disable to avoid workspace propagation issues
    tags: tags
  }
  dependsOn: [
    monitoring
  ]
}

// =====================================================
// Module: Landing Zone
// =====================================================

module landingZone './modules/landing-zone.bicep' = {
  scope: rgTarget
  name: 'deploy-landing-zone-${deployment().name}'
  params: {
    location: location
    namingPrefix: namingPrefix
    tags: tags
  }
}

// =====================================================
// Module: Hyper-V Host (On-Premises Simulation)
// =====================================================

module hypervHost './modules/hyperv-host.bicep' = if (deployHyperVHost) {
  scope: rgOnPrem
  name: 'deploy-hyperv-host-${deployment().name}'
  params: {
    location: location
    namingPrefix: namingPrefix
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: hypervHostVmSize
    subnetId: networking.outputs.onpremSubnetId
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    dataCollectionRuleId: monitoring.outputs.dataCollectionRuleId
    tags: tags
  }
  dependsOn: [
    networking
    monitoring
  ]
}

// =====================================================
// Outputs
// =====================================================

@description('Resource group names')
output resourceGroups object = resourceGroupNames

@description('Azure Migrate project name')
output migrateProjectName string = migrateHub.outputs.migrateProjectName

@description('Recovery Services Vault name')
output recoveryServicesVaultName string = migrateHub.outputs.recoveryServicesVaultName

@description('Key Vault name for migration secrets')
output keyVaultName string = migrateHub.outputs.keyVaultName

@description('Hub Virtual Network ID')
output hubVnetId string = networking.outputs.hubVnetId

@description('Target subnet ID for migrated VMs')
output targetSubnetId string = networking.outputs.targetSubnetId

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = monitoring.outputs.logAnalyticsWorkspaceId

@description('Hyper-V host VM name')
output hypervHostVmName string = deployHyperVHost ? hypervHost.?outputs.?vmName ?? 'Not deployed' : 'Not deployed'

@description('Hyper-V host public IP (if deployed)')
output hypervHostPublicIp string = deployHyperVHost ? hypervHost.?outputs.?publicIpAddress ?? 'N/A' : 'N/A'

@description('Hyper-V host FQDN (if deployed)')
output hypervHostFqdn string = deployHyperVHost ? hypervHost.?outputs.?fqdn ?? 'N/A' : 'N/A'

@description('Bastion host name')
output bastionHostName string = deployBastion ? networking.outputs.bastionHostName : 'Not deployed'

@description('Deployment summary')
output deploymentSummary object = {
  location: location
  prefix: environmentPrefix
  hypervHostDeployed: deployHyperVHost
  bastionDeployed: deployBastion
  estimatedMonthlyCost: deployHyperVHost ? '$450-550 USD' : '$150-250 USD'
}
