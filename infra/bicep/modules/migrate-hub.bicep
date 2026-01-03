// =====================================================
// Azure Migrate Hub Module
// =====================================================
// Creates Azure Migrate project and supporting resources:
// - Azure Migrate project with system-assigned identity
// - Assessment project for server assessments
// - Hyper-V site for discovery
// - Master site for coordinating discovery
// - Solutions for discovery, assessment, and migration
// - Recovery Services Vault for replication
// - Key Vault for appliance secrets
// - Storage account for migrate appliance and cache

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Log Analytics Workspace ID for diagnostics')
param logAnalyticsWorkspaceId string = ''

@description('Enable diagnostic settings (requires workspace to be fully provisioned)')
param enableDiagnostics bool = false

@description('Appliance name for Hyper-V discovery')
param applianceName string = 'AzureMigrateAppliance'

@description('Resource tags')
param tags object

// =====================================================
// Variables
// =====================================================

var migrateProjectName = 'migrate-project-${namingPrefix}'
var assessmentProjectName = '${migrateProjectName}-assessment'
var hyperVSiteName = '${migrateProjectName}-hyperv-site'
var masterSiteName = '${migrateProjectName}-master-site'
var recoveryVaultName = 'rsv-${namingPrefix}'
var keyVaultName = 'kv-${take(replace(namingPrefix, '-', ''), 21)}' // Key Vault names max 24 chars
var storageAccountName = 'stm${replace(namingPrefix, '-', '')}' // Storage for migrate appliance
var cacheStorageName = 'stc${replace(namingPrefix, '-', '')}' // Storage for cache

// =====================================================
// Storage Account for Azure Migrate
// =====================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: take(storageAccountName, 24)
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    networkAcls: {
      defaultAction: 'Allow' // For demo purposes; restrict in production
      bypass: 'AzureServices'
    }
  }
}

// Blob container for appliance configuration
resource applianceContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/migrate-appliance'
  properties: {
    publicAccess: 'None'
  }
}

// =====================================================
// Cache Storage Account for Replication
// =====================================================

resource cacheStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: take(cacheStorageName, 24)
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        blob: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// =====================================================
// Key Vault
// =====================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: true
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled' // For demo; restrict in production
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Diagnostic settings for Key Vault
resource keyVaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics && !empty(logAnalyticsWorkspaceId)) {
  scope: keyVault
  name: 'diagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// =====================================================
// Recovery Services Vault
// =====================================================

resource recoveryVault 'Microsoft.RecoveryServices/vaults@2023-08-01' = {
  name: recoveryVaultName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

// Configure backup storage redundancy
resource backupConfig 'Microsoft.RecoveryServices/vaults/backupconfig@2023-08-01' = {
  parent: recoveryVault
  name: 'vaultconfig'
  properties: {
    storageType: 'LocallyRedundant' // Cost-optimized for demo
    storageTypeState: 'Unlocked'
  }
}

// Diagnostic settings for Recovery Services Vault
resource recoveryVaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics && !empty(logAnalyticsWorkspaceId)) {
  scope: recoveryVault
  name: 'diagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AzureBackupReport'
        enabled: true
      }
      {
        category: 'AzureSiteRecoveryJobs'
        enabled: true
      }
      {
        category: 'AzureSiteRecoveryEvents'
        enabled: true
      }
      {
        category: 'AzureSiteRecoveryReplicatedItems'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Health'
        enabled: true
      }
    ]
  }
}

// =====================================================
// Azure Migrate Project
// =====================================================

resource migrateProject 'Microsoft.Migrate/migrateProjects@2020-06-01-preview' = {
  name: migrateProjectName
  location: location
  tags: union(tags, {
    'Migrate Project': migrateProjectName
  })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    utilityStorageAccountId: storageAccount.id
  }
}

// =====================================================
// Assessment Project for Server Assessments
// =====================================================

resource assessmentProject 'Microsoft.Migrate/assessmentProjects@2023-05-01-preview' = {
  name: assessmentProjectName
  location: location
  tags: union(tags, {
    'Migrate Project': migrateProjectName
  })
  properties: {
    assessmentSolutionId: '${migrateProject.id}/solutions/Servers-Assessment-ServerAssessment'
    projectStatus: 'Active'
    publicNetworkAccess: 'Enabled'
  }
}

// =====================================================
// Master Site for Coordinating Discovery
// =====================================================

resource masterSite 'Microsoft.OffAzure/MasterSites@2023-06-06' = {
  name: masterSiteName
  location: location
  tags: union(tags, {
    'Migrate Project': migrateProjectName
  })
  properties: {
    allowMultipleSites: true
    publicNetworkAccess: 'Enabled'
  }
}

// =====================================================
// Hyper-V Site for Discovery
// =====================================================

resource hyperVSite 'Microsoft.OffAzure/HyperVSites@2023-06-06' = {
  name: hyperVSiteName
  location: location
  tags: union(tags, {
    'Migrate Project': migrateProjectName
  })
  properties: {
    applianceName: applianceName
    discoverySolutionId: '${migrateProject.id}/solutions/Servers-Discovery-ServerDiscovery'
    agentDetails: {
      keyVaultId: keyVault.id
      keyVaultUri: keyVault.properties.vaultUri
    }
  }
  dependsOn: [
    masterSite
  ]
}

// =====================================================
// Azure Migrate Solutions
// =====================================================

// Server Discovery Solution
resource discoverySolution 'Microsoft.Migrate/migrateProjects/solutions@2020-06-01-preview' = {
  parent: migrateProject
  name: 'Servers-Discovery-ServerDiscovery'
  properties: {
    tool: 'ServerDiscovery'
    purpose: 'Discovery'
    goal: 'Servers'
    status: 'Active'
  }
}

// Server Assessment Solution
resource assessmentSolution 'Microsoft.Migrate/migrateProjects/solutions@2020-06-01-preview' = {
  parent: migrateProject
  name: 'Servers-Assessment-ServerAssessment'
  properties: {
    tool: 'ServerAssessment'
    purpose: 'Assessment'
    goal: 'Servers'
    status: 'Active'
  }
}

// Server Migration Solution
resource migrationSolution 'Microsoft.Migrate/migrateProjects/solutions@2020-06-01-preview' = {
  parent: migrateProject
  name: 'Servers-Migration-ServerMigration'
  properties: {
    tool: 'ServerMigration'
    purpose: 'Migration'
    goal: 'Servers'
    status: 'Active'
  }
}

// Server Migration Data Replication Solution
resource migrationDataReplicationSolution 'Microsoft.Migrate/migrateProjects/solutions@2020-06-01-preview' = {
  parent: migrateProject
  name: 'Servers-Migration-ServerMigration_DataReplication'
  properties: {
    tool: 'ServerMigration_DataReplication'
    purpose: 'Migration'
    goal: 'Servers'
    status: 'Active'
  }
}

// Server Discovery Import Solution
resource discoveryImportSolution 'Microsoft.Migrate/migrateProjects/solutions@2020-06-01-preview' = {
  parent: migrateProject
  name: 'Servers-Discovery-ServerDiscovery_Import'
  properties: {
    tool: 'ServerDiscovery_Import'
    purpose: 'Discovery'
    goal: 'Servers'
    status: 'Active'
  }
}

// =====================================================
// Outputs
// =====================================================

@description('Azure Migrate project name')
output migrateProjectName string = migrateProject.name

@description('Azure Migrate project ID')
output migrateProjectId string = migrateProject.id

@description('Assessment project name')
output assessmentProjectName string = assessmentProject.name

@description('Assessment project ID')
output assessmentProjectId string = assessmentProject.id

@description('Hyper-V site name')
output hyperVSiteName string = hyperVSite.name

@description('Hyper-V site ID')
output hyperVSiteId string = hyperVSite.id

@description('Master site name')
output masterSiteName string = masterSite.name

@description('Master site ID')
output masterSiteId string = masterSite.id

@description('Recovery Services Vault name')
output recoveryServicesVaultName string = recoveryVault.name

@description('Recovery Services Vault ID')
output recoveryServicesVaultId string = recoveryVault.id

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault ID')
output keyVaultId string = keyVault.id

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Storage account ID')
output storageAccountId string = storageAccount.id

@description('Cache storage account name')
output cacheStorageAccountName string = cacheStorage.name

@description('Cache storage account ID')
output cacheStorageAccountId string = cacheStorage.id
