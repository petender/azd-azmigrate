# ✅ Validated Deployment Scenario

This document confirms the tested and validated deployment workflow for the Azure Migrate demo environment.

## 🎯 Deployment Overview

The deployment consists of **2 phases**:

### Phase 1: Azure Infrastructure (azd provision)
- Deploys all Azure resources
- Takes 20-25 minutes
- Fully automated

### Phase 2: On-Premises Simulation (Manual scripts on Hyper-V)
- Creates sample VMs for discovery
- Imports Azure Migrate appliance
- Takes ~1.5-2 hours (mostly downloads)
- Semi-automated with 2 scripts

---

## 📝 Complete Deployment Steps

### Step 1: Deploy Azure Infrastructure

**On your local machine:**

```powershell
# Login and create environment
azd auth login
azd env new migrate-demo

# Set required variables
azd env set AZURE_SUBSCRIPTION_ID "<your-subscription-id>"
azd env set ADMIN_PASSWORD "<secure-password>"

# Deploy
azd provision
```

**Result:**
- ✅ 5 resource groups created
- ✅ Azure Migrate project configured
- ✅ Hyper-V host VM running
- ✅ Azure Bastion ready
- ✅ Networking configured

**Time:** 20-25 minutes

---

### Step 2: Access Hyper-V Host

**Option A: Azure Bastion (Recommended)**
1. Azure Portal → Resource Group `rg-migrate-onprem-*`
2. Click Hyper-V VM → Connect → Bastion
3. Username: `azureadmin`
4. Password: (your ADMIN_PASSWORD)

**Option B: RDP**
```powershell
azd env get-value HYPERVHOSTPUBLICIP
mstsc /v:<ip-address>
```

**Time:** 2-3 minutes

---

### Step 3: Copy Scripts to Hyper-V Host

**On Hyper-V host**, create working directory:
```powershell
New-Item -ItemType Directory -Path "C:\AzureMigrate" -Force
Set-Location C:\AzureMigrate
```

**Copy these 2 files** from your local `scripts` folder:

1. **`CreateActualVMs.ps1`**
   - Purpose: Creates 6 bootable sample VMs
   - Downloads: Windows Server 2022 (~10GB), Ubuntu 24.04 (~2GB)
   - Creates: WIN-SQL-01/02, WIN-WEB-01/02, WIN-APP-01, LIN-DB-01

2. **`Create_AzureMigrateAppliance.ps1`**
   - Purpose: Downloads and imports Azure Migrate appliance
   - Downloads: Official appliance from Microsoft (~12GB)
   - Creates: AzureMigrateAppliance VM

**Copy method:** Use RDP clipboard, Bastion file upload, or download from repository

**Time:** 2 minutes

---

### Step 4: Create Sample VMs

**On Hyper-V host:**

```powershell
Set-Location C:\AzureMigrate
.\CreateActualVMs.ps1
```

**What happens:**
1. ✅ Downloads Windows Server 2022 VHD from evaluation center
2. ✅ Downloads Ubuntu 24.04 image and extracts
3. ✅ Creates base VHD files in `E:\VMs\BaseImages\`
4. ✅ Creates 6 VMs with full VHD copies in `E:\VMs\VirtualMachines\`
5. ✅ Shows progress bars for all operations
6. ✅ Automatic retry on failures

**Sample VMs created:**
| VM Name | OS | Memory | vCPU | Disk |
|---------|-----|--------|------|------|
| WIN-SQL-01 | Windows Server 2022 | 8GB | 2 | 127GB |
| WIN-SQL-02 | Windows Server 2022 | 8GB | 2 | 127GB |
| WIN-WEB-01 | Windows Server 2022 | 4GB | 2 | 127GB |
| WIN-WEB-02 | Windows Server 2022 | 4GB | 2 | 127GB |
| WIN-APP-01 | Windows Server 2022 | 8GB | 4 | 127GB |
| LIN-DB-01 | Ubuntu 24.04 | 4GB | 2 | 30GB |

**Time:** 30-45 minutes (depending on internet speed)

**Verify:**
```powershell
Get-VM | Where-Object { $_.Name -match '^(WIN|LIN)' } | Format-Table Name, State, MemoryStartup, ProcessorCount
```

---

### Step 5: Import Azure Migrate Appliance

**On Hyper-V host:**

```powershell
Set-Location C:\AzureMigrate
.\Create_AzureMigrateAppliance.ps1
```

**What happens:**
1. ✅ Downloads appliance ZIP from https://aka.ms/migrate/appliance/hyperv (~12GB)
2. ✅ Extracts and locates VM configuration file (.vmcx or .xml)
3. ✅ Runs Compare-VM to check compatibility
4. ✅ Fixes network adapter issues:
   - Clears static MAC address (uses dynamic)
   - Connects to Hyper-V virtual switch
5. ✅ Imports VM with `-Copy -GenerateNewId`
6. ✅ Renames VM to "AzureMigrateAppliance"
7. ✅ Verifies network configuration
8. ✅ Cleans up temporary files

**Appliance VM specs:**
- Name: AzureMigrateAppliance
- Memory: 16GB
- vCPU: 8
- State: Stopped (ready to start)

**Time:** 30-45 minutes (depending on internet speed)

**Verify:**
```powershell
Get-VM -Name AzureMigrateAppliance | Format-Table Name, State, MemoryStartup, ProcessorCount
Get-VMNetworkAdapter -VMName AzureMigrateAppliance | Format-Table VMName, SwitchName, MacAddress
```

---

### Step 6: Configure Appliance and Start Discovery

**Start appliance:**
```powershell
Start-VM -Name AzureMigrateAppliance
```

**Wait 2-3 minutes** for boot, then:

1. **Connect via Hyper-V Manager** (double-click VM)
2. **Open browser** on appliance → https://localhost:44368
3. **Accept prerequisites** and license terms
4. **Register with Azure:**
   - Sign in with Azure credentials
   - Select subscription and resource group
   - Select Azure Migrate project
5. **Generate appliance key** in Azure Portal:
   - Azure Migrate → Discovery and assessment → Discover
   - Copy key and paste in appliance
6. **Add Hyper-V credentials:**
   - Username: `azureadmin`
   - Password: (your ADMIN_PASSWORD)
7. **Add Hyper-V host:**
   - Get host IP: `(Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*")[0].IPAddress`
   - Enter IP and validate
8. **Start discovery** - Click "Start discovery"

**Time:** 10-15 minutes configuration + 15-30 minutes discovery

---

## ✅ Deployment Complete!

### What You Have Now

**Azure Infrastructure:**
- ✅ Azure Migrate project configured
- ✅ Recovery Services Vault and Key Vault
- ✅ Virtual Network with Bastion
- ✅ Hyper-V host with nested virtualization
- ✅ Log Analytics workspace

**On-Premises Simulation:**
- ✅ 6 bootable sample VMs (3 Windows, 3 Linux)
- ✅ Azure Migrate appliance configured
- ✅ Active discovery running
- ✅ Ready for assessment and migration testing

**Total Time:**
- Infrastructure: 20-25 minutes
- Setup scripts: 2 minutes
- Sample VMs: 30-45 minutes
- Appliance: 30-45 minutes
- Configuration: 25-45 minutes
- **Grand Total: ~2-2.5 hours**

---

## 🎯 Next Steps

### View Discovered Servers
1. Azure Portal → Azure Migrate
2. Click "Servers, databases and web apps"
3. Under "Azure Migrate: Discovery and assessment" → Discovered servers
4. You should see all 6 VMs

### Create Assessment
1. Click "Assess" → "Azure VM"
2. Select all 6 servers
3. Configure target region and settings
4. View TCO and cost estimates

### Test Migration
1. Select a small VM (WIN-WEB-01)
2. Start test migration
3. Verify in isolated test network
4. Clean up test resources

---

## 💾 Scripts Reference

### CreateActualVMs.ps1

**Purpose:** Creates bootable sample VMs with real OS images

**Key Features:**
- ✅ BITS transfer for reliable downloads
- ✅ Progress bars for all operations
- ✅ Full VHD copies (not differencing disks)
- ✅ Generation 1 VMs for compatibility
- ✅ Proper folder structure (BaseImages, VirtualMachines)
- ✅ File type detection (ZIP vs direct VHD)
- ✅ Convert-VHD for Ubuntu (removes sparse format)

**Downloads:**
- Windows Server 2022: 10GB evaluation VHD
- Ubuntu 24.04: 2GB cloud image (tar.gz)

**Storage:**
- Base images: E:\VMs\BaseImages\
- VM disks: E:\VMs\VirtualMachines\{VMName}\

**Status:** ✅ Fully working and tested

---

### Create_AzureMigrateAppliance.ps1

**Purpose:** Downloads and imports Azure Migrate appliance

**Key Features:**
- ✅ BITS transfer for reliable download
- ✅ Automatic VM config file detection (.vmcx or .xml)
- ✅ Compare-VM compatibility checking
- ✅ Network adapter fixes:
  - Set-VMNetworkAdapter with -DynamicMacAddress
  - Connect-VMNetworkAdapter to switch
- ✅ Import-VM with -Copy -GenerateNewId
- ✅ Automatic cleanup of temp files
- ✅ Duplicate VM detection and recreation option

**Latest Fix:**
- Changed from `-StaticMacAddress $null` (error) to `-DynamicMacAddress` (working)

**Status:** ✅ Fully working and tested

---

## 🧪 Testing Checklist

Use this checklist to validate your deployment:

### Infrastructure
- [ ] All 5 resource groups created
- [ ] Azure Migrate project visible in portal
- [ ] Hyper-V VM running and accessible via Bastion
- [ ] Virtual network and subnets created
- [ ] Azure Bastion functioning

### Hyper-V Host
- [ ] Can connect via Bastion or RDP
- [ ] E: drive visible with 512GB capacity
- [ ] Hyper-V role installed and running
- [ ] Virtual switch created (Internal-Switch)
- [ ] Scripts copied to C:\AzureMigrate

### Sample VMs
- [ ] 6 VMs created (3 Windows, 3 Linux)
- [ ] All VMs in "Off" state initially
- [ ] VHD files exist in E:\VMs\VirtualMachines\
- [ ] Base images in E:\VMs\BaseImages\
- [ ] Can start VMs successfully
- [ ] VMs have network adapters connected to switch

### Appliance
- [ ] AzureMigrateAppliance VM imported
- [ ] VM has 16GB RAM and 8 vCPU
- [ ] Network adapter connected to switch
- [ ] Can start appliance VM
- [ ] Can access https://localhost:44368 on appliance
- [ ] Successfully registered with Azure
- [ ] Hyper-V host added and validated
- [ ] Discovery started successfully

### Discovery
- [ ] All 6 VMs discovered in Azure Portal
- [ ] Operating systems identified correctly
- [ ] Can create assessment
- [ ] Assessment shows cost estimates
- [ ] Can start test migration

---

## 📚 Documentation Map

| Document | Purpose | Audience |
|----------|---------|----------|
| [README.md](README.md) | Overview and quick start | Everyone |
| [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) | Complete step-by-step guide | First-time users |
| [VALIDATED-DEPLOYMENT.md](VALIDATED-DEPLOYMENT.md) | Tested workflow reference | This document |
| [AZD-DEPLOYMENT.md](AZD-DEPLOYMENT.md) | azd-specific details | azd users |
| [QUICKSTART.md](QUICKSTART.md) | Quick reference | Experienced users |
| [infra/bicep/README.md](infra/bicep/README.md) | Bicep template details | Developers |

---

## ✨ Success Criteria

Your deployment is successful when:

1. ✅ `azd provision` completes without errors
2. ✅ Can access Hyper-V host via Bastion
3. ✅ `CreateActualVMs.ps1` creates all 6 VMs
4. ✅ `Create_AzureMigrateAppliance.ps1` imports appliance
5. ✅ Appliance registers with Azure Migrate project
6. ✅ Discovery completes and shows 6 servers in portal
7. ✅ Can create and view assessment with cost estimates

---

**Last Validated:** January 2, 2026  
**Status:** ✅ All steps tested and working  
**Scripts Version:** 1.0 (production ready)
