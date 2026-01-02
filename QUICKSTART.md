# Azure Migrate Demo - Quick Start Guide

This project provides a complete Azure Migrate demonstration environment with automated sample data and VM creation.

## 🚀 Quick Deploy

```powershell
# 1. Login to Azure
azd auth login

# 2. Deploy everything
azd provision

# 3. Access your environment
# - Use Azure Bastion to connect to Hyper-V host
# - Credentials: azureadmin / AzureMigrate2026!
```

**Deployment Time:** ~20-25 minutes  
**Region:** Central US (required for Azure Migrate)

---

## 📦 What Gets Deployed

### Infrastructure
- ✅ **5 Resource Groups** (hub, network, target, monitor, onprem)
- ✅ **Virtual Network** with 4 subnets + Azure Bastion
- ✅ **Hyper-V Host** (Standard_D16s_v5: 16 vCPU, 64GB RAM, 512GB data disk)
- ✅ **Azure Migrate Project** with Key Vault and Recovery Vault
- ✅ **3 Storage Accounts** (diagnostics, migrate, cache)
- ✅ **Log Analytics Workspace** with monitoring

### Automated Scenario Setup
- ✅ **Scenario 1: Custom Import** - CSV file with 10 sample servers
- ✅ **Scenario 2: Appliance Discovery** - 6 sample VMs created on Hyper-V host

---

## 📊 Sample Data Generated

### CSV Import (Scenario 1)
**File:** `data\sample-servers.csv`

| Server | OS | Cores | Memory | Storage |
|--------|-----|-------|--------|---------|
| SRV-WEB-01/02 | Win 2016 | 4 | 16 GB | 500 GB |
| SRV-APP-01/02 | Win 2019 | 8 | 32 GB | 1 TB |
| SRV-DB-01/02 | Win 2019 | 16 | 64 GB | 2 TB |
| SRV-LINUX-01 | Ubuntu 20.04 | 4 | 8 GB | 250 GB |
| SRV-LINUX-02 | RHEL 8 | 8 | 16 GB | 500 GB |
| SRV-FILE-01 | Win 2016 | 4 | 8 GB | 4 TB |
| SRV-DC-01 | Win 2019 | 2 | 8 GB | 250 GB |

**Total:** 10 servers, 64 cores, 256 GB RAM, 10 TB storage

### Sample VMs (Scenario 2)
**Location:** `E:\VMs` on Hyper-V host

6 VMs automatically created:
- SRV-WEB-01 & SRV-WEB-02
- SRV-APP-01 & SRV-APP-02
- SRV-DB-01
- SRV-LINUX-01

**Total:** 48 vCPUs, 168 GB RAM, 5 TB storage

---

## 🎯 Using the Demo

### Scenario 1: Custom Import (Fully Automated ✨)

**No manual steps required!** When you run `azd provision`:

✅ CSV file is generated with 10 sample servers  
✅ Servers are automatically imported to Azure Migrate  
✅ Ready for assessment immediately

**View Results:**
1. **Open Azure Portal** → Azure Migrate Project
2. **Click "Discovered servers"** → See all 10 imported servers
3. **Create Assessment:**
   - Select all servers
   - Choose target location
   - Review cost estimates and VM sizing

**Time:** Instant (automated during deployment)  
**Use Case:** Quick POC, high-level capacity planning

### Scenario 2: Appliance Discovery (Mostly Automated 🚀)

**No prerequisites required!** During `azd provision`:

**What Gets Automated:**
✅ Downloads Azure Migrate appliance VHD (~10 GB)  
✅ Transfers to Hyper-V host  
✅ Creates appliance VM (8 vCPU, 16 GB RAM)  
✅ Creates 6 sample VMs for discovery

**Manual Steps (5-10 minutes):**
1. Start appliance VM
2. Complete configuration wizard (browser-based)
3. Register with Azure Migrate project
4. Add Hyper-V host credentials
5. Start discovery

**Time:** 30-45 minutes total (20 min automated + 10 min manual)  
**Use Case:** Production migrations, dependency mapping, performance-based sizing

---

## ⚙️ PowerShell Remoting (Automatic)

✅ **PowerShell Remoting is automatically configured** during deployment via CustomScriptExtension.

The setup includes:
- Enable-PSRemoting
- WinRM configuration
- Firewall rules for ports 5985/5986
- TrustedHosts configuration

**No manual steps required!** The automation scripts can connect immediately after deployment.

---

## 🔍 Verification & Troubleshooting

### Check Deployment Status

```powershell
# View all resource groups
az group list --query "[?contains(name, 'mig')].{Name:name, Location:location}" -o table

# Get Hyper-V VM details
az vm show --resource-group rg-*-onprem --name vm-*-hyperv --query "{Name:name, Size:hardwareProfile.vmSize, State:provisioningState}" -o table

# Get outputs
azd env get-values
```

### Connect to Hyper-V Host

```powershell
# Get public IP
$ip = azd env get-values | Select-String "HYPERV_HOST_IP" | ForEach-Object { $_ -replace '.*=(.*)','$1' }
Write-Host "Hyper-V IP: $ip"

# Use Azure Bastion from Portal (recommended)
# Or RDP directly: mstsc /v:$ip
```

### Verify Sample VMs

```powershell
# After connecting to Hyper-V host
Get-VM | Select-Object Name, State, CPUUsage, MemoryAssigned | Format-Table

# View VM inventory
Get-Content E:\VMs\VM-Inventory.txt

# Check disk space
Get-Volume -DriveLetter E
```

### Common Issues

**Issue:** Sample VMs not created  
**Solution:** Enable PSRemoting and rerun `azd provision`, or manually run:
```powershell
cd E:\VMs
.\Create-SampleVMs.ps1
```

**Issue:** Can't connect to Hyper-V VM  
**Solution:** Use Azure Bastion (native client from Portal). Password is `AzureMigrate2026!`

**Issue:** CSV import fails  
**Solution:** Ensure file is UTF-8, no extra spaces, all required columns present

---

## 📁 Project Structure

```
azd-azmigrate/
├── infra/
│   └── bicep/
│       ├── main.bicep                    # Main deployment orchestration
│       └── modules/
│           ├── networking.bicep          # VNet, Bastion, NSGs
│           ├── migrate-hub.bicep         # Azure Migrate resources
│           ├── hyperv-host.bicep         # Hyper-V VM with extensions
│           ├── monitoring.bicep          # Log Analytics, diagnostics
│           └── landing-zone.bicep        # Target landing zone
├── scripts/
│   ├── Setup-AzureMigrateScenarios.ps1  # Main automation script
│   ├── Create-SampleVMs.ps1             # VM creation on Hyper-V
│   └── Enable-RemotePS.ps1              # Remote PowerShell enabler
├── data/
│   └── sample-servers.csv               # Generated sample data
├── SCENARIOS.md                          # Detailed walkthrough
├── QUICKSTART.md                         # This file
└── azure.yaml                            # azd configuration
```

---

## 💰 Cost Estimate

Monthly costs (Central US, pay-as-you-go):

| Resource | SKU/Size | Est. Cost |
|----------|----------|-----------|
| Hyper-V VM | D16s_v5 | ~$620 |
| Storage (3 accounts) | Standard LRS | ~$15 |
| Azure Bastion | Standard | ~$140 |
| Log Analytics | Pay-as-you-go | ~$10 |
| **Total** | | **~$785/month** |

**Cost Saving Tips:**
- Stop Hyper-V VM when not in use: Saves ~$620/month
- Delete entire environment: `azd down`
- Use for demos only, not production

---

## 🎓 Learning Resources

- **Azure Migrate Documentation:** https://learn.microsoft.com/azure/migrate/
- **Hyper-V Discovery Tutorial:** https://learn.microsoft.com/azure/migrate/tutorial-discover-hyper-v
- **Assessment Best Practices:** https://learn.microsoft.com/azure/migrate/best-practices-assessment

---

## 🔗 Quick Links

After deployment, access your resources:

- **Azure Migrate Project:** Portal → Resource Groups → rg-*-hub → migrate-project-*
- **Hyper-V Host:** Use Azure Bastion (search for "bastion-*")
- **Key Vault:** Search for "kv-*" in Portal
- **Sample Data:** Local folder `data\sample-servers.csv`

---

## 🛠️ Cleanup

### Option 1: Keep Infrastructure, Remove VMs
```powershell
# On Hyper-V host
Get-VM | Where-Object Name -like "SRV-*" | Remove-VM -Force
```

### Option 2: Remove Everything
```powershell
azd down
```

This removes all resource groups, VMs, storage, and data. Cannot be undone.

---

## 📞 Support

For issues or questions:
1. Check `SCENARIOS.md` for detailed troubleshooting
2. Review Azure Migrate documentation
3. Check deployment logs: `azd provision --debug`

**Current Deployment:**
- Resource Suffix: `mig1026am-cnvki6qz7s5d6`
- Region: Central US
- Admin User: `azureadmin`
- Admin Password: `AzureMigrate2026!`

---

**Happy Migrating! 🚀**
