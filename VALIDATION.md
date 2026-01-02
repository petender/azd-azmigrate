# Deployment Validation Checklist

Use this checklist before deploying to ensure everything is configured correctly.

## ✅ Pre-Deployment Validation

### 1. Prerequisites Installed
- [ ] Azure Developer CLI (azd) installed: `azd version`
- [ ] Azure CLI installed: `az version`
- [ ] Logged into Azure: `azd auth login` or `az login`
- [ ] Subscription ID obtained: `az account show --query id -o tsv`

### 2. Bicep Templates Validated
Run from `c:\azd-builds\azd-azmigrate\infra\bicep`:
```powershell
# Build and validate
az bicep build --file main.bicep

# Expected: Warnings are OK, no errors
```

**Expected Warnings (Safe to Ignore):**
- BCP318: Conditional resource outputs (by design)
- BCP081: Azure Migrate API preview (expected)
- no-unused-params: logAnalyticsWorkspaceId (used via dependency)

### 3. Configuration Files Present
- [ ] `azure.yaml` exists in project root
- [ ] `infra/bicep/main.bicep` exists
- [ ] `infra/bicep/main.parameters.json` exists (azd)
- [ ] `infra/bicep/parameters.dev.json` exists (Azure CLI)
- [ ] `.azure/migrate-demo/.env` template exists
- [ ] All module files exist in `infra/bicep/modules/`

### 4. Environment Configuration

**Required Variables:**
```powershell
# Check these are set
azd env get-value AZURE_SUBSCRIPTION_ID  # Should not be empty
azd env get-value ADMIN_PASSWORD         # Should not be empty
```

**Optional Variables (with defaults):**
```powershell
azd env get-value AZURE_LOCATION         # Default: eastus
azd env get-value DEPLOY_HYPERV_HOST     # Default: true
azd env get-value DEPLOY_VPN_GATEWAY     # Default: true
azd env get-value DEPLOY_BASTION         # Default: true
azd env get-value HYPERV_VM_SIZE         # Default: Standard_D16s_v5
```

### 5. Password Requirements Met
Admin password must meet Azure VM requirements:
- [ ] 12-123 characters
- [ ] Contains uppercase letter (A-Z)
- [ ] Contains lowercase letter (a-z)
- [ ] Contains number (0-9)
- [ ] Contains special character (!@#$%^&*())
- [ ] Not a common password

Example valid password: `MySecureP@ssw0rd123!`

### 6. Azure Quota Availability
```powershell
# Check quota for DSv5 family
az vm list-usage --location eastus --query "[?name.value=='standardDSv5Family']"

# Required:
# - Current: 0-16 (depending on existing usage)
# - Limit: Must be >= 16 (for Standard_D16s_v5)
```

If quota is insufficient:
1. Navigate to Azure Portal → Subscriptions
2. Select your subscription
3. Go to Usage + quotas
4. Search for "DSv5"
5. Request increase to at least 16 cores

### 7. Subscription Permissions
Required role: **Owner** or **Contributor** + **User Access Administrator**

```powershell
# Check your role
az role assignment list --assignee $(az account show --query user.name -o tsv) --query "[?scope=='/subscriptions/$(az account show --query id -o tsv)'].roleDefinitionName"
```

## 🚀 Deployment Validation

### Test Deployment (What-If)
```powershell
# Preview changes without deploying
cd c:\azd-builds\azd-azmigrate\infra\bicep

az deployment sub what-if \
  --location eastus \
  --template-file main.bicep \
  --parameters main.parameters.json \
  --parameters adminPassword="<your-password>"
```

Review the output for:
- [ ] 5 resource groups will be created
- [ ] Virtual network with 6 subnets
- [ ] Azure Bastion (if enabled)
- [ ] VPN Gateway (if enabled)
- [ ] Hyper-V VM (if enabled)
- [ ] Azure Migrate project
- [ ] Recovery Services Vault
- [ ] Key Vault
- [ ] Storage accounts
- [ ] Log Analytics workspace

### Validate with azd
```powershell
cd c:\azd-builds\azd-azmigrate

# Initialize environment
azd env new migrate-demo-test

# Set required variables
azd env set AZURE_SUBSCRIPTION_ID "<subscription-id>"
azd env set ADMIN_PASSWORD "<secure-password>"

# Preview deployment
azd provision --preview
```

## ✅ Post-Deployment Validation

After `azd provision` completes successfully:

### 1. Verify Resource Groups Created
```powershell
az group list --query "[?starts_with(name, 'rg-migrate')].name" -o table

# Expected output:
# rg-migrate-demo-hub
# rg-migrate-demo-network
# rg-migrate-demo-target
# rg-migrate-demo-monitor
# rg-migrate-demo-onprem (if Hyper-V deployed)
```

### 2. Verify Key Resources Exist
```powershell
# Azure Migrate project
az resource list -g rg-migrate-demo-hub --resource-type Microsoft.Migrate/migrateProjects -o table

# Hyper-V VM (if deployed)
az vm list -g rg-migrate-demo-onprem -o table

# Azure Bastion (if deployed)
az network bastion list -g rg-migrate-demo-network -o table

# VPN Gateway (if deployed)
az network vnet-gateway list -g rg-migrate-demo-network -o table
```

### 3. Verify Networking
```powershell
# VNet and subnets
az network vnet show -n vnet-migrate-*-hub -g rg-migrate-demo-network --query "subnets[].name" -o table

# Expected subnets:
# subnet-migrate-appliance
# subnet-target-vms
# subnet-test-migration
# subnet-onprem-hyperv
# AzureBastionSubnet
# GatewaySubnet
```

### 4. Verify Outputs Available
```powershell
# Get all outputs
azd env get-values

# Check specific outputs
azd env get-value HYPERVHOSTPUBLICIP    # Should be an IP address
azd env get-value MIGRATEPROJECTNAME    # Should be project name
azd env get-value BASTIONHOSTNAME       # Should be bastion name
```

### 5. Test Connectivity

**To Hyper-V Host via Bastion:**
1. Open Azure Portal
2. Navigate to: Resource Groups → rg-migrate-demo-onprem → VM
3. Click **Connect** → **Bastion**
4. Enter credentials
5. [ ] Successfully connected

**To Azure Migrate:**
1. Open Azure Portal
2. Navigate to: Resource Groups → rg-migrate-demo-hub → Azure Migrate
3. [ ] Project dashboard loads
4. [ ] "Discover" option available

### 6. Verify Hyper-V Configuration
Connect to Hyper-V VM and run:
```powershell
# Verify Hyper-V role installed
Get-WindowsFeature -Name Hyper-V

# Verify data disk formatted
Get-Volume -DriveLetter D

# Verify Hyper-V paths configured
Get-VMHost | Select VirtualHardDiskPath, VirtualMachinePath
```

Expected:
- [ ] Hyper-V role: InstallState = Installed
- [ ] D: drive: FileSystemLabel = VMs
- [ ] Hyper-V paths: D:\VMs

## 🔍 Troubleshooting Failed Validation

### Issue: Bicep Errors (Not Warnings)
```powershell
# Re-download/rebuild
cd c:\azd-builds\azd-azmigrate\infra\bicep
az bicep build --file main.bicep --verbose
```

### Issue: Authentication Errors
```powershell
# Re-authenticate
azd auth login --use-device-code
az login --use-device-code

# Verify subscription access
az account show
```

### Issue: Deployment Timeout
- VPN Gateway: 30-45 minutes is NORMAL
- Azure Bastion: 5-10 minutes is NORMAL
- If timeout > 90 minutes, check Azure Portal for errors

### Issue: Resource Creation Failed
```powershell
# Check deployment status
az deployment sub list --query "[0]" -o json

# View failed operations
az deployment sub operation list \
  --name <deployment-name> \
  --query "[?properties.provisioningState=='Failed']"
```

## 📋 Validation Passed!

Once all checks pass:
- [ ] All Bicep templates validated
- [ ] Environment configured correctly
- [ ] What-if deployment reviewed
- [ ] Resources deployed successfully
- [ ] Connectivity tested
- [ ] Outputs available

**You are ready to proceed with the Azure Migrate demo!**

## 📚 Next Steps

1. **Connect to Hyper-V host** and download Azure Migrate appliance
2. **Import appliance VM** to Hyper-V
3. **Register appliance** with Azure Migrate project
4. **Create sample VMs** for migration (Phase 2)
5. **Start discovery** in Azure Migrate

---

**Deployment Status**: ✅ Validated and Ready  
**Last Checked**: January 2026
