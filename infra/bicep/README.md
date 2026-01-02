# Azure Migrate Demo Infrastructure

Complete Bicep deployment for an Azure Migrate demonstration environment.

## 📋 Overview

This infrastructure deployment creates a comprehensive Azure Migrate demo environment including:

- **Azure Migrate Hub** - Project, Recovery Services Vault, Key Vault, and storage
- **Networking** - Hub VNet with multiple subnets, NSGs, and Azure Bastion
- **Hyper-V Host** - Large Azure VM (Standard_D16s_v5) configured for nested virtualization
- **Landing Zone** - Availability Sets and target infrastructure for migrated VMs
- **Monitoring** - Log Analytics workspace with VM Insights and diagnostic storage

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Subscription Scope                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │  rg-migrate-hub  │  │ rg-migrate-network│                   │
│  │  - Migrate Proj. │  │  - Hub VNet       │                   │
│  │  - Recovery Vault│  │  - Bastion        │                   │
│  │  - Key Vault     │  │  - NSGs           │                   │
│  │  - Storage       │  │                  │                   │
│  └──────────────────┘  └──────────────────┘                    │
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │ rg-migrate-target│  │ rg-migrate-monitor│                   │
│  │  - Avail. Sets   │  │  - Log Analytics  │                   │
│  │  - PPG           │  │  - Diag Storage   │                   │
│  └──────────────────┘  └──────────────────┘                    │
│                                                                 │
│  ┌──────────────────┐                                          │
│  │ rg-migrate-onprem│                                          │
│  │  - Hyper-V VM    │                                          │
│  │  - Public IP     │                                          │
│  └──────────────────┘                                          │
└─────────────────────────────────────────────────────────────────┘
```

## 📦 Resources Deployed

### Resource Groups
- `rg-migrate-hub` - Azure Migrate resources
- `rg-migrate-network` - Networking infrastructure
- `rg-migrate-target` - Target landing zone
- `rg-migrate-monitor` - Monitoring and logging
- `rg-migrate-onprem` - On-premises simulation (Hyper-V)

### Networking (10.0.0.0/16)
| Subnet | Address Space | Purpose |
|--------|---------------|---------|
| subnet-migrate-appliance | 10.0.1.0/24 | Azure Migrate appliance |
| subnet-target-vms | 10.0.2.0/24 | Migrated VMs |
| AzureBastionSubnet | 10.0.3.0/26 | Azure Bastion |
| subnet-onprem-hyperv | 10.0.10.0/24 | Hyper-V host |

### Compute
- **Hyper-V Host VM**: Standard_D16s_v5 (16 vCPU, 64GB RAM, 512GB data disk)
  - Windows Server 2022 Datacenter Azure Edition
  - Hyper-V role installed
  - Nested virtualization enabled
  - Public IP with DNS name

### Storage
- Migrate storage account
- Cache storage account (for replication)
- Diagnostics storage account

### Monitoring
- Log Analytics workspace with solutions:
  - VM Insights
  - Change Tracking
  - Security
- Data Collection Rules for VM monitoring
- Action Group for alerts

## 🚀 Deployment

### Prerequisites

1. **Azure CLI** (version 2.50.0 or later)
   ```powershell
   az --version
   ```

2. **Bicep CLI** (included with Azure CLI)
   ```powershell
   az bicep version
   ```

3. **Azure Subscription** with:
   - Owner or Contributor role
   - Sufficient quota for Standard_D16s_v5 VMs
   - Regional availability for all services

4. **PowerShell 7+** (recommended)

### Step 1: Clone and Navigate

```powershell
cd c:\azd-builds\azd-azmigrate\infra\bicep
```

### Step 2: Login to Azure

```powershell
az login
az account set --subscription "<your-subscription-id>"
```

### Step 3: Update Parameters

Edit `parameters.dev.json` and update:

```json
{
  "adminPassword": {
    "value": "YourSecurePassword123!"
  }
}
```

**⚠️ IMPORTANT**: Use a secure password that meets Azure VM requirements:
- 12-123 characters
- Contains uppercase, lowercase, number, and special character
- Not a common password

### Step 4: Validate Deployment

```powershell
az deployment sub validate `
  --location eastus `
  --template-file main.bicep `
  --parameters parameters.dev.json
```

### Step 5: Deploy Infrastructure

```powershell
az deployment sub create `
  --name "migrate-demo-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
  --location eastus `
  --template-file main.bicep `
  --parameters parameters.dev.json `
  --verbose
```

**Deployment Time**: ~45-60 minutes (VPN Gateway is the longest resource)

### Step 6: Retrieve Outputs

```powershell
az deployment sub show `
  --name "migrate-demo-<timestamp>" `
  --query properties.outputs
```

## 📊 Deployment Options

### Cost-Optimized (Default)
```json
{
  "deployHyperVHost": true,
  "deployVpnGateway": true,
  "deployBastion": true,
  "hypervHostVmSize": "Standard_D16s_v5"
}
```
**Estimated Cost**: $600-800/month

### Minimal Deployment (No Hyper-V)
```json
{
  "deployHyperVHost": false,
  "deployVpnGateway": true,
  "deployBastion": true
}
```
**Estimated Cost**: $200-300/month

### Network-Only Deployment
```json
{
  "deployHyperVHost": false,
  "deployVpnGateway": false,
  "deployBastion": false
}
```
**Estimated Cost**: $50-100/month

## 🔐 Post-Deployment Configuration

### 1. Access Hyper-V Host

**Via Azure Bastion** (Recommended):
1. Navigate to Azure Portal → `vm-migrate-<unique>-hyperv`
2. Click **Connect** → **Bastion**
3. Enter credentials:
   - Username: `azureadmin`
   - Password: (from parameters)

**Via RDP** (Direct):
```powershell
# Get public IP
$publicIp = az deployment sub show --name "migrate-demo-<timestamp>" --query "properties.outputs.hypervHostPublicIp.value" -o tsv

# Connect
mstsc /v:$publicIp
```

### 2. Configure Azure Migrate Appliance

1. **Download Appliance VHD**:
   - Portal: Azure Migrate → Discover → Hyper-V
   - Download the appliance VHD to the Hyper-V host

2. **Import Appliance**:
   ```powershell
   # On Hyper-V host
   Import-VM -Path "D:\VMs\AzureMigrateAppliance"
   ```

3. **Register Appliance**:
   - Open appliance configuration manager
   - Register with Azure Migrate project
   - Provide Hyper-V credentials for discovery

### 3. Create Sample VMs (Manual or Scripted)

The Hyper-V host is ready for VM creation. Options:

**Option A**: Import pre-built VHDs
**Option B**: Use automated scripts (coming in Phase 2)
**Option C**: Manually create VMs for demo

## 📈 Monitoring

### Log Analytics Queries

```kusto
// View all discovered VMs
AzureMigrate_CL
| where TimeGenerated > ago(24h)
| summarize count() by ComputerName_s

// Performance metrics
InsightsMetrics
| where TimeGenerated > ago(1h)
| where Namespace == "Processor"
| summarize avg(Val) by Computer
```

### Access Monitoring

- **Azure Portal** → Log Analytics Workspace → `law-migrate-<unique>`
- **Workbooks** → VM Insights
- **Alerts** → Action Group: `ag-migrate-<unique>-alerts`

## 🧹 Cleanup

### Delete Entire Demo Environment

```powershell
# List all resource groups
az group list --query "[?starts_with(name, 'rg-migrate')].name" -o table

# Delete all resource groups
az group list --query "[?starts_with(name, 'rg-migrate')].name" -o tsv | ForEach-Object {
    az group delete --name $_ --yes --no-wait
}
```

### Estimated cleanup time: 15-30 minutes

## 💰 Cost Management

### Daily Cost Breakdown (Approximate)

| Resource | Daily Cost (USD) |
|----------|------------------|
| Hyper-V VM (D16s_v5) | ~$15 |
| Azure Bastion | ~$4.50 |
| VPN Gateway (Basic) | ~$1 |
| Storage Accounts | ~$1 |
| Log Analytics | ~$0.50 |
| **Total** | **~$22/day** |

### Cost Savings Tips

1. **Stop Hyper-V VM** when not in use:
   ```powershell
   az vm deallocate --resource-group rg-migrate-onprem --name vm-migrate-<unique>-hyperv
   ```
   **Savings**: ~$15/day

2. **Remove Bastion** if using VPN/local network:
   ```powershell
   az network bastion delete --resource-group rg-migrate-network --name bastion-migrate-<unique>
   ```
   **Savings**: ~$4.50/day

3. **Use smaller VM** for Hyper-V host (if fewer VMs needed):
   - Standard_D8s_v5: ~$7.50/day (50% savings)

## 🔧 Troubleshooting

### Deployment Failures

**VPN Gateway timeout**:
- VPN Gateway takes 30-45 minutes to deploy
- This is expected behavior

**Quota exceeded**:
```powershell
# Check quota
az vm list-usage --location eastus --query "[?name.value=='standardDSv5Family']"

# Request increase via Portal → Subscriptions → Usage + quotas
```

**Nested virtualization not working**:
- Ensure you're using a supported VM size (DSv5, ESv5)
- Verify region supports nested virtualization

### Hyper-V Issues

**Hyper-V role not installed**:
```powershell
# On Hyper-V host, reinstall:
Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart
```

**Data disk not initialized**:
```powershell
# On Hyper-V host:
Initialize-Disk -Number 2 -PartitionStyle GPT
New-Partition -DiskNumber 2 -AssignDriveLetter -UseMaximumSize
Format-Volume -DriveLetter E -FileSystem NTFS -NewFileSystemLabel "VMs"
```

## 📚 Next Steps

1. **Phase 2**: Automated VM provisioning scripts
2. **Phase 3**: Sample application deployment
3. **Phase 4**: Migration orchestration scripts
4. **Phase 5**: Performance testing and optimization

## 📖 Additional Resources

- [Azure Migrate Documentation](https://learn.microsoft.com/azure/migrate/)
- [Hyper-V Migration Guide](https://learn.microsoft.com/azure/migrate/tutorial-migrate-hyper-v)
- [Azure Migrate Best Practices](https://learn.microsoft.com/azure/migrate/concepts-migration-planning)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)

## 🤝 Support

For issues or questions:
1. Check Azure Monitor for deployment/runtime errors
2. Review NSG flow logs for connectivity issues
3. Validate resource health in Azure Portal

---

**Version**: 1.0.0  
**Last Updated**: January 2026  
**Maintained By**: Azure Migrate Demo Team
