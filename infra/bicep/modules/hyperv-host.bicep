// =====================================================
// Hyper-V Host Module (On-Premises Simulation)
// =====================================================
// Creates a large Azure VM configured as Hyper-V host for:
// - Hosting guest VMs that simulate on-premises environment
// - Running Azure Migrate appliance
// - Demonstrating migration scenarios

@description('Azure region for resources')
param location string

@description('Naming prefix for resources')
param namingPrefix string

@description('Administrator username')
param adminUsername string

@description('Administrator password')
@secure()
param adminPassword string

@description('VM size (must support nested virtualization)')
param vmSize string = 'Standard_D16s_v5'

@description('Subnet ID for the Hyper-V host')
param subnetId string

@description('Log Analytics Workspace ID for VM insights')
param logAnalyticsWorkspaceId string

@description('Resource tags')
param tags object

@description('Data Collection Rule ID for VM Insights (optional)')
param dataCollectionRuleId string = ''

// =====================================================
// Variables
// =====================================================

var vmName = 'vm-${namingPrefix}-hyperv'
var nicName = 'nic-${vmName}'
var osDiskName = 'disk-${vmName}-os'
var dataDiskName = 'disk-${vmName}-data'
var publicIpName = 'pip-${vmName}'

// =====================================================
// Public IP Address
// =====================================================

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: toLower('${vmName}-${uniqueString(resourceGroup().id)}')
    }
  }
}

// =====================================================
// Network Interface
// =====================================================

resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    enableAcceleratedNetworking: true
  }
}

// =====================================================
// Virtual Machine
// =====================================================

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: take(vmName, 15)
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        patchSettings: {
          patchMode: 'AutomaticByPlatform'
          automaticByPlatformSettings: {
            rebootSetting: 'IfRequired'
          }
        }
        timeZone: 'UTC'
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        name: osDiskName
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 127
      }
      dataDisks: [
        {
          name: dataDiskName
          lun: 0
          createOption: 'Empty'
          caching: 'ReadWrite'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
          diskSizeGB: 512
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            primary: true
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// =====================================================
// VM Extensions
// =====================================================

// Azure Monitor Agent
resource monitoringExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: vm
  name: 'AzureMonitorWindowsAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
}

// Custom Script Extension to configure Hyper-V
resource hypervSetupExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: vm
  name: 'SetupHyperV'
  location: location
  dependsOn: [
    monitoringExtension
  ]
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {}
    protectedSettings: {
      commandToExecute: 'powershell -ExecutionPolicy Unrestricted -Command "try { Install-WindowsFeature -Name Hyper-V -IncludeManagementTools; $disk = Get-Disk | Where-Object PartitionStyle -eq \'RAW\' | Select-Object -First 1; if ($disk) { $disk | Initialize-Disk -PartitionStyle GPT -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem NTFS -NewFileSystemLabel \'VMs\' -Confirm:$false; Start-Sleep -Seconds 5; $volume = Get-Volume | Where-Object FileSystemLabel -eq \'VMs\'; $driveLetter = $volume.DriveLetter; if ($driveLetter) { New-Item -Path ($driveLetter + \':\\VMs\') -ItemType Directory -Force; New-Item -Path ($driveLetter + \':\\ISOs\') -ItemType Directory -Force; Set-VMHost -VirtualHardDiskPath ($driveLetter + \':\\VMs\') -VirtualMachinePath ($driveLetter + \':\\VMs\') -ErrorAction SilentlyContinue } }; exit 0 } catch { exit 0 }"'
    }
  }
}

// Data Collection Rule Association (if provided)
resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = if (!empty(dataCollectionRuleId)) {
  name: 'dcra-${vmName}-vminsights'
  scope: vm
  properties: {
    dataCollectionRuleId: dataCollectionRuleId
    description: 'Association of data collection rule for VM Insights'
  }
}

// =====================================================
// Outputs
// =====================================================

@description('Hyper-V host VM name')
output vmName string = vm.name

@description('Hyper-V host VM ID')
output vmId string = vm.id

@description('Public IP address')
output publicIpAddress string = publicIp.properties.ipAddress

@description('FQDN for RDP access')
output fqdn string = publicIp.properties.dnsSettings.fqdn

@description('Private IP address')
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress

@description('Admin username')
output adminUsername string = adminUsername
