# Azure Migrate Demo - Azure Developer CLI (azd) Deployment Guide

## 🚀 Quick Start with azd

Azure Developer CLI (azd) simplifies the deployment process with automated infrastructure provisioning and environment management.

### Prerequisites

1. **Install Azure Developer CLI (azd)**
   ```powershell
   # Windows (PowerShell)
   powershell -ex AllSigned -c "Invoke-RestMethod 'https://aka.ms/install-azd.ps1' | Invoke-Expression"
   
   # Or via winget
   winget install microsoft.azd
   ```

2. **Install Azure CLI** (if not already installed)
   ```powershell
   winget install microsoft.azurecli
   ```

3. **Verify installations**
   ```powershell
   azd version
   az version
   ```

### Step-by-Step Deployment

#### 1. Initialize Environment

```powershell
# Navigate to project directory
cd c:\azd-builds\azd-azmigrate

# Login to Azure
azd auth login

# Initialize the environment (first time only)
azd env new migrate-demo

# Or use an existing environment
azd env select migrate-demo
```

#### 2. Configure Environment Variables

Edit `.azure/migrate-demo/.env` or set variables interactively:

```powershell
# Set subscription (required)
azd env set AZURE_SUBSCRIPTION_ID "<your-subscription-id>"

# Set VM admin password (required)
azd env set ADMIN_PASSWORD "<secure-password>"

# Optional: Customize deployment
azd env set AZURE_LOCATION "eastus"
azd env set HYPERV_VM_SIZE "Standard_D16s_v5"
azd env set DEPLOY_HYPERV_HOST "true"
azd env set DEPLOY_VPN_GATEWAY "true"
azd env set DEPLOY_BASTION "true"
```

**Password Requirements:**
- 12-123 characters
- Must contain: uppercase, lowercase, number, special character
- Example: `MySecureP@ssw0rd123!`

#### 3. Deploy Infrastructure

```powershell
# Provision all infrastructure
azd provision

# This will:
# - Validate Bicep templates
# - Create resource groups
# - Deploy networking (45-60 minutes due to VPN Gateway)
# - Deploy Azure Migrate hub
# - Deploy Hyper-V host VM
# - Configure monitoring
# - Output connection information
```

**Deployment time:** ~45-60 minutes (VPN Gateway is the slowest component)

#### 4. View Outputs

```powershell
# View all environment variables (including outputs)
azd env get-values

# Get specific values
azd env get-value HYPERVHOSTPUBLICIP
azd env get-value HYPERVHOSTFQDN
azd env get-value BASTIONHOSTNAME
azd env get-value MIGRATEPROJECTNAME
```

### Alternative: One-Command Deployment

Set all variables inline:

```powershell
$env:AZURE_SUBSCRIPTION_ID="<subscription-id>"
$env:ADMIN_PASSWORD="<secure-password>"
azd env new migrate-demo
azd provision
```

---

## 🔧 Configuration Options

### Deployment Scenarios

#### **Scenario 1: Full Demo Environment (Default)**
```powershell
azd env set DEPLOY_HYPERV_HOST "true"
azd env set DEPLOY_VPN_GATEWAY "true"
azd env set DEPLOY_BASTION "true"
azd env set HYPERV_VM_SIZE "Standard_D16s_v5"
```
**Cost:** ~$600-800/month  
**Use Case:** Complete demonstration with on-premises simulation

#### **Scenario 2: Infrastructure Only (No Hyper-V)**
```powershell
azd env set DEPLOY_HYPERV_HOST "false"
azd env set DEPLOY_VPN_GATEWAY "true"
azd env set DEPLOY_BASTION "true"
```
**Cost:** ~$200-300/month  
**Use Case:** Using external Hyper-V environment

#### **Scenario 3: Cost-Optimized (Smaller VM)**
```powershell
azd env set DEPLOY_HYPERV_HOST "true"
azd env set DEPLOY_VPN_GATEWAY "false"
azd env set DEPLOY_BASTION "true"
azd env set HYPERV_VM_SIZE "Standard_D8s_v5"
```
**Cost:** ~$350-450/month  
**Use Case:** Budget-conscious demo with fewer VMs

#### **Scenario 4: Minimal (Network Only)**
```powershell
azd env set DEPLOY_HYPERV_HOST "false"
azd env set DEPLOY_VPN_GATEWAY "false"
azd env set DEPLOY_BASTION "false"
```
**Cost:** ~$50-100/month  
**Use Case:** Testing migration hub and monitoring only

---

## 📋 Common azd Commands

### Environment Management
```powershell
# List all environments
azd env list

# Select an environment
azd env select <env-name>

# Delete an environment
azd env delete <env-name>

# View environment configuration
azd env get-values

# Set a variable
azd env set <key> <value>

# Get a specific variable
azd env get-value <key>
```

### Deployment Operations
```powershell
# Provision infrastructure
azd provision

# Re-deploy after changes
azd provision --force

# Show deployment outputs
azd provision --output json

# Preview changes (what-if)
az deployment sub what-if \
  --location eastus \
  --template-file infra/bicep/main.bicep \
  --parameters infra/bicep/main.parameters.json
```

### Monitoring & Management
```powershell
# View deployment status in portal
azd monitor

# Open Azure Portal to resource group
az group show --name rg-migrate-demo-hub --query id -o tsv | % { Start-Process "https://portal.azure.com/#@/resource$_" }
```

---

## 🔐 Post-Deployment Access

### Connect to Hyper-V Host

**Method 1: Azure Bastion (Recommended)**
```powershell
# Get VM name
$vmName = azd env get-value HYPERVHOSTVMNAME

# Open Azure Portal to VM
az vm show -n $vmName -g rg-migrate-demo-onprem --query id -o tsv | % { Start-Process "https://portal.azure.com/#@/resource$_" }

# In Portal: Click "Connect" → "Bastion"
# Username: azureadmin
# Password: <ADMIN_PASSWORD from environment>
```

**Method 2: Direct RDP (if Bastion not deployed)**
```powershell
# Get public IP
$publicIp = azd env get-value HYPERVHOSTPUBLICIP

# Connect via RDP
mstsc /v:$publicIp
```

### Access Azure Migrate Project

```powershell
# Get project name
$projectName = azd env get-value MIGRATEPROJECTNAME

# Open in Portal
az resource show --ids "/subscriptions/$(azd env get-value AZURE_SUBSCRIPTION_ID)/resourceGroups/rg-migrate-demo-hub/providers/Microsoft.Migrate/migrateProjects/$projectName" --query id -o tsv | % { Start-Process "https://portal.azure.com/#@/resource$_" }
```

---

## 🧹 Cleanup

### Delete Entire Environment

```powershell
# Clean up all resources
azd down

# This will:
# - Delete all resource groups
# - Remove deployment history
# - Preserve environment configuration

# To also remove environment configuration
azd down --purge

# Manual cleanup of resource groups (alternative)
az group list --query "[?starts_with(name, 'rg-migrate-demo')].name" -o tsv | ForEach-Object {
    az group delete --name $_ --yes --no-wait
}
```

---

## 🔍 Troubleshooting

### Common Issues

#### **Issue: azd not found**
```powershell
# Reinstall azd
winget install microsoft.azd --force
# Restart terminal
```

#### **Issue: Authentication errors**
```powershell
# Re-authenticate
azd auth login --use-device-code

# Or use different authentication method
azd auth login --client-id <client-id> --tenant-id <tenant-id>
```

#### **Issue: Deployment timeout (VPN Gateway)**
This is normal! VPN Gateway takes 30-45 minutes. The deployment will continue.

#### **Issue: Quota exceeded**
```powershell
# Check quota
az vm list-usage --location eastus --query "[?name.value=='standardDSv5Family']"

# Request increase via Portal
Start-Process "https://portal.azure.com/#view/Microsoft_Azure_Support/NewSupportRequestV3Blade/issueType/quota"
```

#### **Issue: Parameter validation errors**
```powershell
# Validate parameters
az deployment sub validate \
  --location eastus \
  --template-file infra/bicep/main.bicep \
  --parameters infra/bicep/main.parameters.json \
  --parameters adminPassword="<password>"
```

### View Deployment Logs

```powershell
# Get latest deployment
az deployment sub list --query "[0]" -o json

# View deployment operations
az deployment sub operation list \
  --name <deployment-name> \
  --query "[?properties.provisioningState=='Failed']"
```

---

## 📊 Cost Management

### View Estimated Costs

```powershell
# Navigate to Cost Management
Start-Process "https://portal.azure.com/#blade/Microsoft_Azure_CostManagement/Menu/costanalysis"

# Filter by resource groups starting with "rg-migrate-demo"
```

### Stop Resources to Save Costs

```powershell
# Stop (deallocate) Hyper-V VM
$vmName = azd env get-value HYPERVHOSTVMNAME
az vm deallocate -n $vmName -g rg-migrate-demo-onprem
# Savings: ~$15/day

# Start VM when needed
az vm start -n $vmName -g rg-migrate-demo-onprem
```

---

## 🔄 Update Deployment

### Modify Infrastructure

1. **Edit Bicep files** in `infra/bicep/`
2. **Re-provision**:
   ```powershell
   azd provision
   ```

azd will detect changes and update only affected resources.

### Change Environment Variables

```powershell
# Update variable
azd env set HYPERV_VM_SIZE "Standard_D8s_v5"

# Re-provision to apply changes
azd provision
```

---

## 📚 Next Steps

After successful deployment:

1. ✅ **Connect to Hyper-V host** via Bastion
2. ✅ **Download Azure Migrate appliance VHD** from Azure Portal
3. ✅ **Import appliance VM** to Hyper-V
4. ✅ **Configure discovery** in Azure Migrate project
5. ✅ **Create sample VMs** for migration testing (coming in Phase 2)

---

## 🆘 Support & Documentation

- **Azure Developer CLI**: https://learn.microsoft.com/azure/developer/azure-developer-cli/
- **Azure Migrate**: https://learn.microsoft.com/azure/migrate/
- **Bicep**: https://learn.microsoft.com/azure/azure-resource-manager/bicep/

---

**Version:** 1.0.0  
**Last Updated:** January 2026  
**Maintained By:** Azure Migrate Demo Team
