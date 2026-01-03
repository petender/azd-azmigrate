# Azure Migrate Demo - Complete Deployment Guide

This guide walks you through the complete deployment from infrastructure to fully functional Azure Migrate demo environment.

## 📋 Prerequisites

- Azure subscription with Owner/Contributor access
- Azure Developer CLI (azd) installed: `winget install microsoft.azd`
- At least 30GB free space on Hyper-V host for VM images

## 🚀 Step-by-Step Deployment

### Phase 1: Deploy Azure Infrastructure (20-25 minutes)

**On your local machine:**

```powershell
# 1. Navigate to project directory
cd c:\azd-builds\azd-azmigrate

# 2. Login to Azure
azd auth login

# 3. Create new environment
azd env new migrate-demo

# 4. Set required parameters
azd env set AZURE_SUBSCRIPTION_ID "<your-subscription-id>"
azd env set ADMIN_PASSWORD "<secure-password>"  # Use for Hyper-V host login

# 5. Deploy infrastructure
azd provision
```

**What gets deployed:**
- ✅ 5 Resource Groups (hub, network, target, monitor, onprem)
- ✅ Azure Migrate project with Recovery Services Vault and Key Vault
- ✅ Virtual Network with Azure Bastion
- ✅ Hyper-V Host VM (Standard_D16s_v5: 16 vCPU, 64GB RAM, 512GB disk)
- ✅ Hyper-V configured with Internal switch and NAT (192.168.100.0/24)
- ✅ PowerShell Remoting enabled
- ✅ Log Analytics workspace with monitoring
- ✅ Storage accounts for migration

**Network Configuration (Automatic):**
- Internal virtual switch: **Internal-Switch**
- NAT gateway: **192.168.100.1**
- NAT network: **192.168.100.0/24**
- VM IP range: **192.168.100.10 - 192.168.100.254**
- Internet access: ✅ Enabled via NAT

**Cost:** ~$450-550/month (stop Hyper-V VM when not in use to save ~$450/month)

---

### Phase 2: Access Hyper-V Host (2-3 minutes)

**Via Azure Bastion (Recommended):**

1. Open [Azure Portal](https://portal.azure.com)
2. Navigate to Resource Group: `rg-migrate-onprem-*`
3. Click on the Hyper-V VM
4. Click **Connect** → **Bastion**
5. Enter credentials:
   - Username: `azureadmin`
   - Password: (the password you set in ADMIN_PASSWORD)

**Via RDP (Alternative):**

```powershell
# Get public IP
azd env get-value HYPERVHOSTPUBLICIP

# Connect with Remote Desktop
mstsc /v:<ip-address>
```

---

### Phase 3: Copy Setup Scripts (2 minutes)

**On the Hyper-V host**, create a working directory and copy the scripts:

```powershell
# Create directory
New-Item -ItemType Directory -Path "C:\AzureMigrate" -Force
Set-Location C:\AzureMigrate
```

**Copy these two scripts** from your local `scripts` folder to `C:\AzureMigrate` on the Hyper-V host:

1. **CreateActualVMs.ps1** - Creates 6 bootable sample VMs
2. **Create_AzureMigrateAppliance.ps1** - Downloads and imports Azure Migrate appliance

**Copy methods:**
- **Bastion:** Use file upload feature (if available in your tier)
- **RDP:** Copy-paste via clipboard
- **Alternative:** Download directly from your repository if available

---

### Phase 4: Create Sample VMs (30-45 minutes)

**On the Hyper-V host**, run the sample VM creation script:

```powershell
Set-Location C:\AzureMigrate
.\CreateActualVMs.ps1
```

**What it does:**
- ✅ Downloads Windows Server 2022 VHD (~10GB)
- ✅ Downloads Ubuntu 24.04 image (~2GB)
- ✅ Creates 6 VMs with real OS installations:
  - **WIN-SQL-01** (Windows Server 2022, 8GB RAM, 2 vCPU)
  - **WIN-SQL-02** (Windows Server 2022, 8GB RAM, 2 vCPU)
  - **WIN-WEB-01** (Windows Server 2022, 4GB RAM, 2 vCPU)
  - **WIN-WEB-02** (Windows Server 2022, 4GB RAM, 2 vCPU)
  - **WIN-APP-01** (Windows Server 2022, 8GB RAM, 4 vCPU)
  - **LIN-DB-01** (Ubuntu 24.04, 4GB RAM, 2 vCPU)

**Storage locations:**
- Base images: `E:\VMs\BaseImages\`
- VM disks: `E:\VMs\VirtualMachines\`

**Progress:**
- Script shows progress bars for downloads
- Automatic retry on failures
- ~30-45 minutes depending on internet speed

**Verification:**
```powershell
# Check created VMs
Get-VM | Where-Object { $_.Name -match '^(WIN|LIN)' } | Select-Object Name, State, MemoryStartup, ProcessorCount

# Check disk space
Get-Volume -DriveLetter E
```

---

### Phase 5: Import Azure Migrate Appliance (30-45 minutes)

**On the Hyper-V host**, run the appliance setup script:

```powershell
Set-Location C:\AzureMigrate
.\Create_AzureMigrateAppliance.ps1
```

**What it does:**
- ✅ Downloads official Azure Migrate appliance (~12GB) from Microsoft
- ✅ Extracts and locates VM configuration files
- ✅ Fixes compatibility issues (network switch, MAC addresses)
- ✅ Imports VM with proper settings
- ✅ Connects to Hyper-V network switch

**The appliance VM:**
- Name: **AzureMigrateAppliance**
- Memory: 16GB
- vCPUs: 8
- State: Stopped (after import)

**Progress:**
- BITS transfer for reliable download
- ~30-45 minutes depending on internet speed
- Automatic cleanup of temporary files

**Verification:**
```powershell
# Check appliance VM
Get-VM -Name AzureMigrateAppliance | Select-Object Name, State, MemoryStartup, ProcessorCount

# Check network adapter
Get-VMNetworkAdapter -VMName AzureMigrateAppliance | Select-Object VMName, SwitchName, MacAddress
```

---

### Phase 6: Configure Azure Migrate Appliance (10-15 minutes)

**Start the appliance:**

```powershell
Start-VM -Name AzureMigrateAppliance
```

**Wait 2-3 minutes** for the VM to boot completely.

**Connect to appliance:**

1. Open Hyper-V Manager
2. Double-click **AzureMigrateAppliance**
3. Login with appliance credentials (displayed on screen)

**Configure appliance:**

1. **Open browser** on the appliance VM
2. Navigate to: `https://localhost:44368`
3. Accept security warnings (self-signed certificate)
4. **Accept prerequisites** - Click through license terms and prerequisites check
5. **Register with Azure:**
   - Sign in with your Azure credentials
   - Select subscription
   - Select resource group: `rg-migrate-hub-*`
   - Select Azure Migrate project
6. **Generate appliance key:**
   - Go to Azure Portal → Azure Migrate → Discovery and assessment
   - Click "Discover" → "Discover using appliance"
   - Copy the generated key
   - Paste into appliance configuration
7. **Add Hyper-V credentials:**
   - Friendly name: `HyperVHost`
   - Username: `azureadmin`
   - Password: (your ADMIN_PASSWORD)
8. **Add Hyper-V host:**
   - Get host IP: On Hyper-V host run: `(Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*")[0].IPAddress`
   - Enter IP or hostname
   - Click "Validate"
9. **Start discovery** - Click "Start discovery"

**Discovery time:** 15-30 minutes for initial discovery

---

### Phase 7: Verify Discovery (15-30 minutes)

**In Azure Portal:**

1. Navigate to **Azure Migrate**
2. Click **Servers, databases and web apps**
3. Under **Azure Migrate: Discovery and assessment**, click **Discovered servers**

**You should see:**
- ✅ 6 servers discovered
- ✅ Operating systems identified
- ✅ Installed applications (after deeper discovery)
- ✅ Dependencies (if enabled)

**Create an assessment:**

1. Click **Assess** → **Azure VM**
2. Select all discovered servers
3. Configure assessment:
   - Target location: (your region)
   - VM series: (recommended defaults)
   - Pricing: (adjust based on your needs)
4. Click **Create assessment**
5. Wait 2-3 minutes for assessment to complete

**View results:**
- TCO analysis
- Recommended VM sizes
- Monthly cost estimates
- Readiness status

---

## ✅ Deployment Complete!

You now have a fully functional Azure Migrate demo environment with:

- ✅ Complete Azure infrastructure
- ✅ 6 discoverable sample VMs (3 Windows, 3 Linux)
- ✅ Configured Azure Migrate appliance
- ✅ Active discovery and assessment
- ✅ Ready for migration testing

---

## 🎯 What's Next?

### Test Migrations
1. Select a small VM (WIN-WEB-01)
2. Start test migration
3. Verify in isolated test network
4. Clean up test resources

### Dependency Mapping
1. Enable dependency analysis in Azure Migrate
2. Install dependency agents on sample VMs
3. View application dependencies
4. Group related servers

### Cost Optimization
1. Review assessment recommendations
2. Compare VM sizes and costs
3. Test Azure Hybrid Benefit scenarios
4. Evaluate reserved instances

---

## 🧹 Cleanup

### Stop Hyper-V VM (to save costs)
```powershell
# From Azure CLI
az vm deallocate --resource-group rg-migrate-onprem-* --name vm-*-hyperv

# Saves ~$450/month
```

### Delete Sample VMs (keep infrastructure)
```powershell
# On Hyper-V host
Get-VM | Where-Object { $_.Name -match '^(WIN|LIN)' } | Stop-VM -Force
Get-VM | Where-Object { $_.Name -match '^(WIN|LIN)' } | Remove-VM -Force

# Remove VHD files
Remove-Item E:\VMs\VirtualMachines\* -Recurse -Force
```

### Delete Everything
```powershell
# From local machine
azd down --purge

# Removes all resource groups and data
# Cannot be undone
```

---

## 🐛 Troubleshooting

### Sample VMs not booting
```powershell
# Check VM state
Get-VM | Select-Object Name, State, Status

# Check VHD files
Get-ChildItem E:\VMs\VirtualMachines\* -Recurse | Where-Object Extension -eq '.vhd'

# Restart VM
Restart-VM -Name WIN-SQL-01 -Force
```

### Appliance not discovering
- Verify Hyper-V credentials are correct
- Check Windows Firewall on Hyper-V host
- Ensure PowerShell remoting is enabled: `Enable-PSRemoting -Force`
- Check sample VMs are running: `Get-VM | Where-Object State -eq 'Running'`

### Network issues
```powershell
# Check virtual switch
Get-VMSwitch

# Check VM network adapters
Get-VM | Get-VMNetworkAdapter | Select-Object VMName, SwitchName, Status
```

### Download failures
- Check internet connectivity on Hyper-V host
- Verify proxy settings if in corporate environment
- Retry script - it has automatic resume capability

---

## 📚 Additional Resources

- [Azure Migrate Documentation](https://learn.microsoft.com/azure/migrate/)
- [Hyper-V Discovery Tutorial](https://learn.microsoft.com/azure/migrate/tutorial-discover-hyper-v)
- [Assessment Best Practices](https://learn.microsoft.com/azure/migrate/best-practices-assessment)
- [Migration Best Practices](https://learn.microsoft.com/azure/migrate/migrate-best-practices)

---

## 💰 Cost Summary

| Resource | Monthly Cost | Notes |
|----------|-------------|--------|
| Hyper-V VM (D16s_v5) | ~$450 | Stop when not in use |
| Azure Bastion | ~$135 | Always running |
| Storage Accounts | ~$15 | Data + diagnostics |
| Log Analytics | ~$10 | Basic monitoring |
| **Total (Running)** | **~$610** | Full demo environment |
| **Total (Stopped)** | **~$160** | VM stopped, keep infra |

**Pro Tip:** Use for demos only, stop Hyper-V VM when not actively testing.

---

**Version:** 1.0  
**Last Updated:** January 2026  
**Status:** ✅ Production Ready
