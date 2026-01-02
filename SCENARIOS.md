# Azure Migrate Demo Scenarios

This guide walks through two Azure Migrate discovery scenarios included in this demo environment.

## 📋 Scenario 1: Custom Import with Sample Data

**Use Case:** Quickly populate Azure Migrate with sample server inventory without needing actual infrastructure.

### Automated Setup

The post-deployment hook automatically generates a sample CSV file with 10 servers representing a typical datacenter:

**Server Inventory:**
- **Web Tier:** 2x Windows Server 2016 (4 cores, 16 GB RAM, 500 GB storage)
- **Application Tier:** 2x Windows Server 2019 (8 cores, 32 GB RAM, 1 TB storage)
- **Database Tier:** 2x Windows Server 2019 (16 cores, 64 GB RAM, 2 TB storage)
- **Linux Workloads:** Ubuntu 20.04 + Red Hat 8 (4-8 cores, 8-16 GB RAM)
- **Infrastructure:** File Server + Domain Controller

**Total Capacity:** 64 cores, 256 GB RAM, 10 TB storage

### Automated Import (Default)

When you run `azd provision`, the setup script automatically:

✅ **Generates CSV** with 10 sample servers  
✅ **Imports to Azure Migrate** via REST API  
✅ **Creates server records** with complete metadata

**Result:** Servers appear in Portal within minutes, ready for assessment!

### Manual Import (Fallback)

If automated import fails or you prefer manual control:

1. **Locate the CSV file:** `.\data\sample-servers.csv`

2. **Import via Portal:**
   - Navigate to [Azure Portal](https://portal.azure.com)
   - Go to **Azure Migrate** → **Servers, databases and web apps**
   - Click **Discover** → **Import using .csv**
   - Upload `sample-servers.csv`

### Create Assessment

1. **View Discovered Servers:**
   - Portal → Azure Migrate → Discovered servers
   - Should show 10 imported servers

2. **Start Assessment:**
   - Select all servers
   - Click **Assess** → **Azure VM**
   - Configure settings:
     - Target location: Same as deployment
     - VM series: Standard
     - Pricing tier: Standard
   - Run assessment

3. **Review Results:**
   - View monthly cost estimates
   - See recommended VM sizes
   - Analyze readiness and potential issues

---

## 🖥️ Scenario 2: Azure Migrate Appliance with Hyper-V

**Use Case:** Full-featured discovery with dependency mapping and performance-based sizing using the Azure Migrate appliance.

### Prerequisites

✅ **Remote PowerShell:** Automatically configured during deployment

**Download Azure Migrate Appliance:**
   - Go to Azure Migrate project in Portal
   - Click **Discover** → **Are your servers virtualized?** → **Yes, with Hyper-V**
   - Download the VHD (approximately 10 GB)

### Automated Appliance Setup

During `azd provision`, the script automatically:

✅ **Downloads appliance VHD** (~10 GB, takes 10-20 minutes)  
✅ **Transfers to Hyper-V host** at `E:\VMs\AzureMigrateAppliance\`  
✅ **Creates appliance VM** (8 vCPU, 16 GB RAM)  
✅ **Creates 6 sample VMs** for discovery  
✅ **Generates setup instructions**

**Note:** Large file download may take time. Progress shown in script output.

### Complete Appliance Configuration

After automated setup, you need to complete the appliance wizard:

1. **Start Appliance VM:**
   ```powershell
   # Connect to Hyper-V host via Bastion
   Start-VM -Name "AzureMigrateAppliance"
   ```

2. **Access Appliance Console:**
   - Open Hyper-V Manager
   - Connect to AzureMigrateAppliance VM
   - Follow on-screen setup wizard

3. **Configure Appliance:**
   - Set administrator password
   - Configure network (DHCP)
   - Open browser: `https://localhost:44368`

4. **Register with Azure:**
   - Login with Azure credentials
   - Select your subscription and migrate project
   - Generate and apply registration key from Portal

5. **Add Hyper-V Host:**
   - In appliance configuration portal
   - Add Hyper-V host: Use your Hyper-V VM's IP
   - Credentials: `azureadmin` / `AzureMigrate2026!`
   - Start discovery

### Manual Appliance Setup (Fallback)

If automated download fails:

1. **Transfer VHD to Hyper-V Host:**
   - Upload the downloaded VHD to E:\VMs via:
     - Azure Bastion file transfer
     - Azure Storage Explorer
     - Direct RDP with drive mapping

2. **Create Appliance VM:**
   ```powershell
   # On Hyper-V host
   $vmName = "AzureMigrateAppliance"
   $vhdPath = "E:\VMs\AzureMigrateAppliance.vhdx"
   
   New-VM -Name $vmName -MemoryStartupBytes 16GB -Generation 1 -VHDPath $vhdPath
   Set-VM -Name $vmName -ProcessorCount 8
   Connect-VMNetworkAdapter -VMName $vmName -SwitchName "Default Switch"
   Start-VM -Name $vmName
   ```

3. **Configure Appliance:**
   - Connect to appliance VM via Hyper-V Manager
   - Complete initial setup wizard
   - Register with Azure Migrate project: `migrate-project-mig1026am-cnvki6qz7s5d6`
   - Configure Hyper-V host credentials (azureadmin)

4. **Start Discovery:**
   - Add Hyper-V host: Internal IP from E:\VMs\README.txt
   - Validate credentials
   - Enable dependency analysis (optional)
   - Start discovery

5. **Monitor Progress:**
   - Discovery takes 15-30 minutes for initial scan
   - Performance data collected over 7-30 days for accurate sizing
   - View discovered servers in Azure Portal

---

## 📊 Comparison: Custom Import vs. Appliance

| Feature | Custom Import | Appliance-based |
|---------|--------------|-----------------|
| **Setup Time** | 5 minutes (fully automated) | 30-45 minutes (mostly automated) |
| **Automation Level** | Full (CSV + API import) | Partial (VHD download + VM setup) |
| **Discovery Method** | Manual CSV | Automated |
| **Data Points** | Basic inventory | 30+ metrics |
| **Performance Data** | No | Yes (historical) |
| **Dependency Mapping** | No | Yes (optional) |
| **Assessment Accuracy** | Basic sizing | High (performance-based) |
| **Best For** | Quick demos, POCs | Production migrations |
| **Ongoing Maintenance** | Manual updates | Automatic refresh |

---

## 🎮 Managing Sample VMs

The automated setup creates 6 sample VMs on your Hyper-V host. Here's how to work with them:

### View All VMs

```powershell
Get-VM | Select-Object Name, State, CPUUsage, MemoryAssigned, Uptime | Format-Table
```

### View VM Details

```powershell
Get-VM -Name "SRV-WEB-01" | Select-Object *
```

### Start/Stop VMs (Optional)

```powershell
# Start a VM (not required for discovery)
Start-VM -Name "SRV-WEB-01"

# Stop a VM
Stop-VM -Name "SRV-WEB-01"

# Start all sample VMs
Get-VM | Where-Object Name -like "SRV-*" | Start-VM
```

### Recreate VMs

If you need to recreate the VMs:

```powershell
# Remove existing VMs
Get-VM | Where-Object Name -like "SRV-*" | Remove-VM -Force

# Recreate them
cd E:\VMs
.\Create-SampleVMs.ps1
```

### VM Inventory

Location: `E:\VMs\VM-Inventory.txt` contains complete details of all sample VMs.

**Important**: Sample VMs don't need to be running for Azure Migrate to discover them. The appliance reads VM metadata from Hyper-V even when VMs are powered off.

---

## 🔗 Quick Links

- **Azure Migrate Project:** [Portal Link](https://portal.azure.com/#resource/subscriptions/{subscriptionId}/resourceGroups/rg-mig1026am-hub/providers/Microsoft.Migrate/migrateProjects/migrate-project-mig1026am-cnvki6qz7s5d6/overview)
- **Hyper-V Host:** Use Azure Bastion from Portal
- **Documentation:** [Azure Migrate Docs](https://learn.microsoft.com/azure/migrate/)

---

## 🛠️ Troubleshooting

### Custom Import Issues

**CSV format errors:**
- Ensure UTF-8 encoding
- No extra commas or quotes
- Required columns: ServerName, OperatingSystem, Cores, Memory

**Import fails:**
- Check CSV has < 20,000 rows
- Verify project is in correct region
- Ensure BIOS GUIDs are unique

### Appliance Setup Issues

**Cannot connect to Hyper-V host:**
- Verify NSG allows internal traffic
- Check host firewall settings
- Confirm credentials are correct

**Appliance registration fails:**
- Verify internet connectivity from appliance
- Check Azure credentials have Contributor role
- Ensure correct project selected

**Discovery shows no VMs:**
- Verify Hyper-V host credentials
- Check host has running VMs
- Review appliance logs in Portal

---

## 📚 Next Steps

1. ✅ Complete Scenario 1: Import sample CSV
2. ✅ Create initial assessment
3. ✅ Review cost estimates and sizing
4. ✅ Set up appliance (Scenario 2)
5. ✅ Compare results between scenarios
6. ✅ Create migration plan
7. ✅ Test migration with sample VM

For detailed migration steps, see [MIGRATION-GUIDE.md](./MIGRATION-GUIDE.md) (coming soon).
