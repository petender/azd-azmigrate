// =====================================================
// Azure Migrate Hub Module
// =====================================================
// Creates Azure Migrate project and supporting resources:
// - Azure Migrate project
// - Recovery Services Vault for replication
// - Key Vault for secrets management
// - Storage account for migrate appliance and cache

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Log Analytics Workspace ID for diagnostics')
param logAnalyticsWorkspaceId string = ''

@description('Enable diagnostic settings (requires workspace to be fully provisioned)')
param enableDiagnostics bool = false

@description('Resource tags')
param tags object

// =====================================================
// Variables
// =====================================================

var migrateProjectName = 'migrate-project-${namingPrefix}'
var recoveryVaultName = 'rsv-${namingPrefix}'
var keyVaultName = 'kv-${take(namingPrefix, 21)}' // Key Vault names max 24 chars
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
  tags: tags
  properties: {
    publicNetworkAccess: 'Enabled'
    utilityStorageAccountId: storageAccount.id
  }
}

// =====================================================
// Outputs
// =====================================================

@description('Azure Migrate project name')
output migrateProjectName string = migrateProject.name

@description('Azure Migrate project ID')
output migrateProjectId string = migrateProject.id

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
