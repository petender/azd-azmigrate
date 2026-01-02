// =====================================================
// Monitoring Infrastructure Module
// =====================================================
// Creates centralized monitoring resources:
// - Log Analytics workspace for logs and metrics
// - Storage account for diagnostic logs
// - Data Collection Rules for VM insights

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Resource tags')
param tags object

// =====================================================
// Variables
// =====================================================

var logAnalyticsWorkspaceName = 'law-${namingPrefix}'
var diagnosticsStorageName = 'std${replace(namingPrefix, '-', '')}' // Storage for diagnostics

// =====================================================
// Log Analytics Workspace
// =====================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Enable solutions for the workspace
resource vmInsightsSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'VMInsights(${logAnalyticsWorkspace.name})'
  location: location
  tags: tags
  plan: {
    name: 'VMInsights(${logAnalyticsWorkspace.name})'
    publisher: 'Microsoft'
    product: 'OMSGallery/VMInsights'
    promotionCode: ''
  }
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
}

resource changeTrackingSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'ChangeTracking(${logAnalyticsWorkspace.name})'
  location: location
  tags: tags
  plan: {
    name: 'ChangeTracking(${logAnalyticsWorkspace.name})'
    publisher: 'Microsoft'
    product: 'OMSGallery/ChangeTracking'
    promotionCode: ''
  }
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
}

resource securitySolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'Security(${logAnalyticsWorkspace.name})'
  location: location
  tags: tags
  plan: {
    name: 'Security(${logAnalyticsWorkspace.name})'
    publisher: 'Microsoft'
    product: 'OMSGallery/Security'
    promotionCode: ''
  }
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
}

// =====================================================
// Diagnostic Storage Account
// =====================================================

resource diagnosticsStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: take(diagnosticsStorageName, 24)
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Cool' // Cost-optimized for logs
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
  }
}

// =====================================================
// Data Collection Rule for VM Insights
// =====================================================

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: 'dcr-${namingPrefix}-vminsights'
  location: location
  tags: tags
  kind: 'Windows'
  properties: {
    dataSources: {
      performanceCounters: [
        {
          name: 'VMInsightsPerfCounters'
          streams: [
            'Microsoft-InsightsMetrics'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\VmInsights\\DetailedMetrics'
          ]
        }
      ]
      extensions: [
        {
          name: 'DependencyAgentDataSource'
          streams: [
            'Microsoft-ServiceMap'
          ]
          extensionName: 'DependencyAgent'
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
          name: 'VMInsightsPerf-Logs-Dest'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-InsightsMetrics'
        ]
        destinations: [
          'VMInsightsPerf-Logs-Dest'
        ]
      }
      {
        streams: [
          'Microsoft-ServiceMap'
        ]
        destinations: [
          'VMInsightsPerf-Logs-Dest'
        ]
      }
    ]
  }
}

// =====================================================
// Action Group for Alerts
// =====================================================

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${namingPrefix}-alerts'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'MigrateDemo'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    automationRunbookReceivers: []
  }
}

// =====================================================
// Outputs
// =====================================================

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics Workspace customer ID')
output logAnalyticsCustomerId string = logAnalyticsWorkspace.properties.customerId

@description('Diagnostics storage account name')
output diagnosticsStorageAccountName string = diagnosticsStorage.name

@description('Diagnostics storage account ID')
output diagnosticsStorageAccountId string = diagnosticsStorage.id

@description('Data Collection Rule ID')
output dataCollectionRuleId string = dataCollectionRule.id

@description('Action Group ID')
output actionGroupId string = actionGroup.id
