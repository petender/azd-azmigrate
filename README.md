# Azure Migrate Demo Environment

Complete end-to-end demonstration environment for Azure Migrate with semi-automated on-premises simulation using nested Hyper-V.

## 📖 Overview

This project deploys a **complete Azure Migrate demonstration** that simulates an on-premises datacenter using nested Hyper-V virtualization in Azure. It provides everything you need to demonstrate server discovery, assessment, and migration capabilities of Azure Migrate. Deployment of the Hyper-V host takes about 15-20 minutes, after which you need to run 2 manual scripts inside the Hyper-V Host to build the on-premises simulation VMs and the AzureMigrateAppliance VM.

### What You Get

**On Azure Side:**

- ✅ **Azure Migrate Hub** - Placeholder migration project
- ✅ **Hyper-V Host VM** - Standard_D16s_v5 (16 vCPU, 64GB RAM) with nested virtualization
- ✅ **Networking Infrastructure** - Hub VNet with Azure Bastion, NSGs, and multiple subnets
- ✅ **Landing Zone** - Target resource group with availability sets for migrated VMs
- ✅ **Monitoring & Security** - Log Analytics, Key Vault, Recovery Services Vault

**On Hyper-V Host (On-Premises Simulation):**

- ✅ **3 Windows Server VMs** - WIN-SQL-01, WIN-WEB-01, WIN-APP-01 (auto-configured with static IPs)
- ✅ **Azure Migrate Appliance** - Ready for starting registration and Hyper-V discovery
- ✅ **Internal Network** - NAT-based network (192.168.100.0/24) with internet connectivity

## 🚀 Complete Deployment Guide

### Prerequisites

- Azure subscription with Owner or Contributor access
- Azure Developer CLI (azd): `winget install microsoft.azd`
- 30 minutes for Azure infrastructure + 60 minutes for Hyper-V setup

### Phase 1: Deploy Azure Infrastructure (20-25 minutes)

```powershell
# 1. Azd Init the project artifacts (Clone or download this repository)
mkdir azd-azmigrate
azd init -t petender/azd-azmigrate

# 2. Login and initialize environment
azd auth login
azd env new migrate-demo

# 3. Deploy infrastructure
azd up
```

This will deploy:

- **5 Resource Groups** across your Azure subscription
- **Hyper-V Host VM** (Standard_D16s_v5) with Windows Server 2022
- **Networking**: Hub VNet (10.0.0.0/16), Azure Bastion, NSGs
- **Azure Migrate Project** with required storage and vault resources
- **Monitoring**: Log Analytics workspace with VM Insights
- **Landing Zone**: Target infrastructure for migrated VMs

### Phase 2: Access the Hyper-V Host (2 minutes)

**Via deployed Azure Bastion**

1. Navigate to Azure Portal → Resource Groups → `rg-migrate-onprem`
2. Open the Hyper-V host VM
3. Click **Connect** → **Bastion**
4. Enter credentials:
   - Username: `azureadmin`
   - Password: (the password you set during deployment)
5. From Server Manager, validate **Hyper-V** role is installed. You can also try to open Hyper-V Manager. 
**Note**: if Hyper-V seems missing, try rebooting the Hyper-V Host, which should fix the delay of installing the server role through DSC.

### Phase 3: Create Sample VMs on Hyper-V Host (30-45 minutes)

Once connected to the Hyper-V host:

1. Download this demo scenario's GitHub repo to the Hyper-V Host, and extract the zip. Navigate to the \scripts folder
2. Run the script (as Administrator)

```powershell
.\Create_SampleVMs.ps1
```

**What this script does:**

- Downloads Windows Server 2022 Evaluation VHD (~10 GB)
- Creates 3 Windows VMs with automatic configuration:
  - **WIN-SQL-01** (192.168.100.10) - 4GB RAM, 2 vCPU
  - **WIN-WEB-01** (192.168.100.11) - 2GB RAM, 2 vCPU  
  - **WIN-APP-01** (192.168.100.12) - 4GB RAM, 2 vCPU
- Skips OOBE (Out-of-Box Experience) automatically
- Configures Administrator account with password: `**P@ssw0rd!123**` (can be changed upfront in the PS1 file if you want to choose another password)
- Sets static IP addresses automatically
- Creates Internal NAT network (192.168.100.0/24) with internet access

**Note: The VMs are just Windows OS, no applications. The naming just looks cool to simulate a complex app**

**Script Features:**

- ✅ Fully automated - no manual OOBE configuration needed
- ✅ Progress monitoring with timers
- ✅ Detailed logging to `C:\Temp\Create_SampleVMs_verbose.log`
- ✅ VMs boot directly to desktop with pre-configured network

**Time:** 30-45 minutes (mainly downloading Windows Server VHD taking most of the time here)

### Phase 4: Deploy Azure Migrate Appliance (30-45 minutes)

Still on the Hyper-V host:

1. Copy the appliance deployment script

# 2. Run the script (as Administrator)
```powershell
.\Create_AzureMigrateAppliance.ps1
```

**What this script does:**

- Downloads official Azure Migrate appliance from Microsoft (~12 GB)
- Extracts and imports the appliance VM
- Connects to the Internal-NAT switch
- Configures with 8GB RAM and 4 vCPUs

**Time:** 30-45 minutes (mainly downloading appliance VHD taking up this time)

### Phase 5: Configure Azure Migrate Project

1. From the Azure Portal, search for **Azure Migrate** and select your project (migrate-project-%azdenv%)

2. Click the **Start-Discovery** button, selecting Using Appliance / For Azure

3. Select **Yes, with Hyper-V** in the **Are your servers virtualized** question.

4. Generate the project key; your Azure Migrate Appliance needs this key during the registration process later

5. You can skip the download step

### Phase 5b: Configure Azure Migrate Appliance (10-15 minutes)

1. Start the appliance VM 

2. Wait 2-3 minutes for the appliance to boot

3. Connect via Hyper-V Manager - Right-click the VM → Connect

4. Accept the initial License Terms and provide the appliance credentials of your choice

5. **Access Appliance Configuration Manager**
   - open Edge and navigate to: `https://localhost:44368`
   - Accept the certificate warning

6. **Register Appliance**
   - Click "Set up prerequisites"
   - Accept license terms
   - Wait for any Appliance Updates to get installed and refresh browser 
   - Connect to Azure:
     - Authenticate with your Azure Admin credentials
     - Select your Azure Migrate project
     - Provide the generated registration key

3. **Add Hyper-V Credentials**
   - Click "Manage credentials"
   - Add credentials for Hyper-V host:
     - Username: `azureadmin`
     - Password: (your azd deployment provided password)
     - Domain: Leave blank (local account)

4. **Start Discovery**
   - Click "Start discovery"
   - Enter Hyper-V host IP: `192.168.100.1` (the host's internal NAT IP)
   - Or enter the host's actual IP address
   - Wait 10-15 minutes for initial discovery

### Phase 6: Explore & Demonstrate (Ongoing)

**In Azure Portal → Azure Migrate:**

1. **View Discovered Servers**
   - See all 3 Windows VMs
   - Review server specifications

2. **Create Assessment**
   - Select discovered servers
   - Choose sizing criteria (performance-based or as-is)
   - Review cost estimates and readiness

3. **Configure Replication**
   - Select servers for migration
   - Configure target settings (region, VM size, disk type)
   - Start replication

4. **Perform Test Migration**
   - Create isolated test network
   - Migrate VMs to test environment
   - Validate functionality

5. **Complete Migration**
   - Finalize migration
   - Cutover to Azure
   - Clean up on-premises

## 📊 Detailed Azure Deployment Architecture

### Resource Groups (5 Total)

| Resource Group | Purpose | Key Resources |
|----------------|---------|---------------|
| `rg-migrate-hub` | Migration tooling | Azure Migrate project, Storage accounts |
| `rg-migrate-network` | Networking | VNet, Bastion, Public IPs, NSGs |
| `rg-migrate-target` | Landing zone | Availability sets, Proximity placement groups |
| `rg-migrate-monitor` | Observability | Log Analytics, Diagnostic storage |
| `rg-migrate-onprem` | On-prem simulation | Hyper-V host VM, Data disk |

### Networking (Hub VNet: 10.0.0.0/16)

| Subnet | CIDR | Purpose |
|--------|------|---------|
| `snet-bastion` | 10.0.0.0/26 | Azure Bastion (requires /26 or larger) |
| `snet-migrate` | 10.0.1.0/24 | Azure Migrate appliance (if deployed in Azure) |
| `snet-onprem` | 10.0.10.0/24 | Hyper-V host VM |
| `snet-target` | 10.0.20.0/24 | Target for migrated VMs |

**Azure Bastion:** Secure RDP/SSH access without exposing public IPs

### Hyper-V Host Configuration

- **VM Size:** Standard_D16s_v5
- **vCPUs:** 16
- **RAM:** 64 GB
- **OS Disk:** 127 GB Premium SSD
- **Data Disk:** 512 GB Premium SSD (for VM storage)
- **Nested Virtualization:** Enabled
- **OS:** Windows Server 2022 Datacenter Azure Edition

- **Hyper-V Internal Network:**
- **Switch Name:** Internal-NAT
- **CIDR:** 192.168.100.0/24
- **Gateway:** 192.168.100.1 (on Hyper-V host)
- **NAT:** Configured for internet access from guest VMs
- **DNS:** 8.8.8.8 (configurable)

### Sample VM Specifications

**Windows VMs (3 Total):**

| VM Name | IP Address | RAM | vCPU | Role |
|---------|------------|-----|------|------|
| WIN-SQL-01 | 192.168.100.10 | 4 GB | 2 | SQL Server simulation |
| WIN-WEB-01 | 192.168.100.11 | 2 GB | 2 | Web server |
| WIN-APP-01 | 192.168.100.12 | 4 GB | 2 | Application server |

- **OS:** Windows Server 2022 Evaluation
- **Admin Account:** Administrator
- **Password:** `P@ssw0rd!123`
- **OOBE:** Skipped automatically
- **Network:** Static IP, pre-configured

### Migration & Security Resources

**Azure Migrate Project:**
- Assessment tools
- Server Migration tools (Azure Migrate: Server Migration)
- Database assessment tools (optional)

**Recovery Services Vault:**
- Type: Standard
- Redundancy: Locally Redundant Storage (LRS)
- Purpose: Replication data storage

**Key Vault:**
- SKU: Standard
- RBAC: Enabled
- Purpose: Secure credential storage

**Storage Accounts:**
- Migration storage account (replication data)
- Cache storage account (temporary replication cache)

### Monitoring & Diagnostics

**Log Analytics Workspace:**
- VM Insights solution
- Change Tracking solution
- Security Center integration
- Retention: 30 days (configurable)

**Diagnostic Settings:**
- VM boot diagnostics
- NSG flow logs
- Azure Migrate activity logs

## 📁 Project Structure

```
azd-azmigrate/
├── azure.yaml                          # Azure Developer CLI configuration
├── README.md                           # This comprehensive guide
├── scripts/
│   ├── Create_SampleVMs.ps1           # ⭐ Creates Windows VMs with auto-config
│   ├── Create_AzureMigrateAppliance.ps1  # Downloads & imports migrate appliance
│   ├── AzureMigrateInstaller.ps1      # Alternative appliance setup
│   ├── Import-ServersManual.ps1       # Manually import server data
│   └── Setup-AzureMigrateMenu.ps1     # Interactive setup menu
├── data/
│   ├── sample-servers.csv             # Sample server inventory data
│   └── AzureMigrateimporttemplate.csv # Import template
├── .azure/
│   └── <environment-name>/            # azd environment configuration
│       ├── .env                       # Environment variables
│       └── config.json                # Environment metadata
└── infra/
    └── bicep/
        ├── main.bicep                 # Main orchestration template
        ├── main.parameters.json       # azd parameters with token substitution
        ├── parameters.json            # Production parameters
        ├── parameters.dev.json        # Development parameters
        ├── README.md                  # Bicep-specific documentation
        ├── QUICKSTART.md              # Bicep quick reference
        └── modules/
            ├── networking.bicep       # VNet, Bastion, NSGs
            ├── migrate-hub.bicep      # Azure Migrate project & resources
            ├── hyperv-host.bicep      # Hyper-V host VM configuration
            ├── monitoring.bicep       # Log Analytics, diagnostics
            └── landing-zone.bicep     # Target availability sets, PPG
```

### Key Scripts Explained

| Script | Purpose | Runtime | Run From |
|--------|---------|---------|----------|
| `Create_SampleVMs.ps1` | Creates 3 Windows VMs with full automation - no OOBE, auto-configured IPs | 30-45 min | Hyper-V host |
| `Create_AzureMigrateAppliance.ps1` | Downloads and imports official Azure Migrate appliance | 30-45 min | Hyper-V host |
| `Import-ServersManual.ps1` | Manually import server inventory to Azure Migrate | 5 min | Local machine |
| `Setup-AzureMigrateMenu.ps1` | Interactive menu for all setup tasks | Variable | Hyper-V host |

## 📚 Additional Documentation

- **[Azure Migrate Documentation](https://learn.microsoft.com/azure/migrate/)** - Official Microsoft docs
- **[Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)** - azd documentation
- **[Hyper-V Nested Virtualization](https://learn.microsoft.com/virtualization/hyper-v-on-windows/user-guide/nested-virtualization)** - Nested virtualization guide
- **[Azure Migrate Overview](https://learn.microsoft.com/azure/migrate/migrate-services-overview)** - Main documentation
- **[Hyper-V Assessment](https://learn.microsoft.com/azure/migrate/tutorial-assess-hyper-v)** - Assessment guide
- **[Hyper-V Migration](https://learn.microsoft.com/azure/migrate/tutorial-migrate-hyper-v)** - Migration guide
- **[Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)** - azd documentation
- **[Bicep Language](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)** - Infrastructure as Code
- **[Azure Migrate FAQ](https://learn.microsoft.com/azure/migrate/resources-faq)** - Common questions
- **[Appliance Troubleshooting](https://learn.microsoft.com/azure/migrate/troubleshoot-appliance)** - Appliance issues
- **[Discovery Issues](https://learn.microsoft.com/azure/migrate/troubleshoot-discovery)** - Discovery problems
- **[Assessment Issues](https://learn.microsoft.com/azure/migrate/troubleshoot-assessment)** - Assessment errors
- **[Azure Migrate Q&A](https://learn.microsoft.com/answers/tags/146/azure-migrate)** - Community forum
- **[Azure Support](https://azure.microsoft.com/support/options/)** - Official support options

## 🧹 Cleanup & Cost Management

### Estimated Costs

**During Demo (Running):**

- Hyper-V Host (Standard_D16s_v5): ~$0.75/hour (~$550/month if left running)
- Azure Bastion (Basic): ~$0.19/hour (~$140/month)
- Storage & Networking: ~$20-50/month
- **Total: ~$1-2/hour or $710-740/month if left running continuously**

**Cost Saving Tips:**

- Stop Hyper-V host when not demoing: Saves ~$550/month
- Delete Bastion if not needed: Saves ~$140/month
- Use B-series burst VMs for testing (not production demos)

### Remove All Resources

**Option 1: Using Azure Developer CLI (Recommended)**

```powershell
# Remove everything including purging Key Vault and recoverable resources
azd down --purge --force
```

**Option 2: Manual Cleanup via Azure CLI**

```powershell
# List all resource groups
az group list --query "[?starts_with(name, 'rg-migrate')].name" -o tsv

# Delete all resource groups (parallel)
az group list --query "[?starts_with(name, 'rg-migrate')].name" -o tsv | ForEach-Object {
    az group delete --name $_ --yes --no-wait
}

# Monitor deletion progress
az group list --query "[?starts_with(name, 'rg-migrate')].[name, properties.provisioningState]" -o table
```

## 🎓 Demo Script & Walkthrough

### 30-Minute Demo Flow

**Phase 1: Show Infrastructure (5 minutes)**
1. Azure Portal → Resource Groups
2. Show the 5 resource groups and their purpose
3. Navigate to Hyper-V host → Connect via Bastion
4. Show Hyper-V Manager with running VMs

**Phase 2: Azure Migrate Discovery (5 minutes)**
1. Azure Portal → Azure Migrate
2. Show discovered servers
3. Explain agentless discovery process
4. Show server details (CPU, RAM, disk usage)

**Phase 3: Assessment (10 minutes)**
1. Create new assessment
2. Select discovered servers
3. Show sizing recommendations
4. Review cost estimates
5. Discuss Azure Hybrid Benefit savings
6. Show readiness reports

**Phase 4: Migration Planning (5 minutes)**
1. Select servers for migration
2. Configure replication settings
3. Show target configuration options
4. Explain test migration process
5. Discuss cutover strategy

**Phase 5: Q&A (5 minutes)**
- Answer questions about the process
- Discuss real-world scenarios
- Share best practices

### Key Demo Talking Points

**Infrastructure as Code:**
- "Everything deployed via Bicep - repeatable and version-controlled"
- "Azure Developer CLI makes deployment simple"

**Nested Virtualization:**
- "Simulates on-premises Hyper-V in Azure for demos"
- "No physical hardware needed"

**Agentless Discovery:**
- "No software installation on source VMs"
- "WMI-based discovery for Hyper-V"
- "Minimal performance impact"

**Assessment Capabilities:**
- "Performance-based sizing prevents over-provisioning"
- "Azure Hybrid Benefit provides significant savings"
- "Dependency mapping shows application relationships"

**Migration Process:**
- "Test migrations validate before production cutover"
- "Incremental replication minimizes downtime"
- "Rollback capability maintains business continuity"

## 🤝 Contributing & Feedback

This is a demonstration project designed to showcase Azure Migrate capabilities. Feel free to:

- Fork and customize for your scenarios
- Submit issues for bugs or improvements
- Share feedback on the deployment experience
- Contribute enhancements via pull requests

---

## 📌 Quick Reference

### Important Credentials
- **Hyper-V Host:** Username: `azureadmin`, Password: (deployment parameter)
- **Windows VMs:** Username: `Administrator`, Password: `P@ssw0rd!123`
- **Network:** 192.168.100.0/24 (Internal NAT)

## Ultimate Future scenario requested

When talking about and showing this scenario to other trainers, some asked why they have to go through some manual PowerShell scripting steps. Well, for the following reason:

- This could be used as an Azure VM demo environment, without focusing on Hyper-V, so no need for Guest VMs;
- The guestVM creation takes up a serious amount of time (downloading VHD resources being the biggest part), which
conflicts with Azure Resource Manager time-outs; this would potentially break the Azure deployment
- Not everything needs to be 100% automated;
- Flexibility to tweak and tune the Guest VM setup for your own needs and wants; 