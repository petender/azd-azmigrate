// =====================================================
// Landing Zone Module
// =====================================================
// Creates target infrastructure for migrated VMs:
// - Availability Sets for high availability
// - Proximity Placement Groups for low latency
// - Pre-configured for migration waves

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Resource tags')
param tags object

// =====================================================
// Variables
// =====================================================

var availabilitySets = [
  {
    name: 'avset-${namingPrefix}-web'
    faultDomains: 2
    updateDomains: 5
  }
  {
    name: 'avset-${namingPrefix}-app'
    faultDomains: 2
    updateDomains: 5
  }
  {
    name: 'avset-${namingPrefix}-data'
    faultDomains: 2
    updateDomains: 5
  }
  {
    name: 'avset-${namingPrefix}-infra'
    faultDomains: 2
    updateDomains: 3
  }
]

// =====================================================
// Proximity Placement Group
// =====================================================

resource proximityPlacementGroup 'Microsoft.Compute/proximityPlacementGroups@2023-09-01' = {
  name: 'ppg-${namingPrefix}-migrate'
  location: location
  tags: tags
  properties: {
    proximityPlacementGroupType: 'Standard'
  }
}

// =====================================================
// Availability Sets
// =====================================================

resource availabilitySet 'Microsoft.Compute/availabilitySets@2023-09-01' = [for avset in availabilitySets: {
  name: avset.name
  location: location
  tags: tags
  sku: {
    name: 'Aligned'
  }
  properties: {
    platformFaultDomainCount: avset.faultDomains
    platformUpdateDomainCount: avset.updateDomains
    proximityPlacementGroup: {
      id: proximityPlacementGroup.id
    }
  }
}]

// =====================================================
// Disk Encryption Set (Optional - for managed disk encryption)
// =====================================================

// Note: This requires Key Vault with keys configured
// Commented out for basic deployment, can be enabled if needed
/*
resource diskEncryptionSet 'Microsoft.Compute/diskEncryptionSets@2023-04-02' = {
  name: 'des-${namingPrefix}-migrate'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    activeKey: {
      sourceVault: {
        id: keyVaultId
      }
      keyUrl: diskEncryptionKeyUrl
    }
    encryptionType: 'EncryptionAtRestWithCustomerKey'
  }
}
*/

// =====================================================
// Outputs
// =====================================================

@description('Web tier availability set ID')
output webAvailabilitySetId string = availabilitySet[0].id

@description('Web tier availability set name')
output webAvailabilitySetName string = availabilitySet[0].name

@description('App tier availability set ID')
output appAvailabilitySetId string = availabilitySet[1].id

@description('App tier availability set name')
output appAvailabilitySetName string = availabilitySet[1].name

@description('Data tier availability set ID')
output dataAvailabilitySetId string = availabilitySet[2].id

@description('Data tier availability set name')
output dataAvailabilitySetName string = availabilitySet[2].name

@description('Infrastructure tier availability set ID')
output infraAvailabilitySetId string = availabilitySet[3].id

@description('Infrastructure tier availability set name')
output infraAvailabilitySetName string = availabilitySet[3].name

@description('Proximity Placement Group ID')
output proximityPlacementGroupId string = proximityPlacementGroup.id

@description('All availability set IDs')
output availabilitySetIds array = [for (avset, i) in availabilitySets: {
  name: availabilitySet[i].name
  id: availabilitySet[i].id
}]
