// =====================================================
// Azure Migrate Hub Module
// =====================================================
// Creates bare minimum Azure Migrate project for appliance registration

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Resource tags')
param tags object

// =====================================================
// Variables
// =====================================================

var migrateProjectName = 'migrate-project-${namingPrefix}'

// =====================================================
// Azure Migrate Project (Bare Minimum)
// =====================================================

resource migrateProject 'Microsoft.Migrate/migrateProjects@2020-06-01-preview' = {
  name: migrateProjectName
  location: location
  tags: tags
  properties: {}
}

// =====================================================
// Outputs
// =====================================================

@description('Azure Migrate project name')
output migrateProjectName string = migrateProject.name

@description('Azure Migrate project ID')
output migrateProjectId string = migrateProject.id
