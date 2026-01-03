# Azure Migrate Demo Environment

Complete demonstration environment for Azure Migrate with on-premises simulation using Hyper-V.

## 📖 Overview

This project provides Infrastructure-as-Code (Bicep) to deploy a comprehensive Azure Migrate demo environment, including:

- ✅ **Azure Migrate Hub** - Migration project, Recovery Services Vault, Key Vault
- ✅ **Hyper-V Host VM** - Standard_D16s_v5 with nested virtualization for on-premises simulation
- ✅ **Networking** - Hub VNet, Azure Bastion, NSGs
- ✅ **Landing Zone** - Availability Sets and infrastructure for migrated VMs
- ✅ **Monitoring** - Log Analytics workspace with VM Insights

## 🚀 Quick Start

### Prerequisites
- Azure subscription with Owner/Contributor access
- Azure Developer CLI (azd) installed: `winget install microsoft.azd`

### Complete End-to-End Deployment

```powershell
# 1. Deploy Azure Infrastructure (20-25 minutes)
azd auth login
azd env new migrate-demo
azd env set AZURE_SUBSCRIPTION_ID "<your-subscription-id>"
azd env set ADMIN_PASSWORD "<secure-password>"
azd provision

# 2. Access Hyper-V host via Azure Bastion
# 3. Copy scripts: CreateActualVMs.ps1 and Create_AzureMigrateAppliance.ps1
# 4. Run CreateActualVMs.ps1 to create 6 sample VMs (30-45 min)
# 5. Run Create_AzureMigrateAppliance.ps1 to import appliance (30-45 min)
# 6. Configure appliance and start discovery (10-15 min)
```

**Total time:** ~2 hours (mostly automated downloads)

📚 **Complete Step-by-Step Guide:** [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)  
📚 **Azure Developer CLI Details:** [AZD-DEPLOYMENT.md](AZD-DEPLOYMENT.md)

### Alternative: Deploy with Azure CLI

For Bicep-only deployment without azd:

```powershell
cd infra/bicep
az deployment sub create \
  --name "migrate-demo-$(Get-Date -Format 'yyyyMMdd-HHmmss')" \
  --location eastus \
  --template-file main.bicep \
  --parameters parameters.dev.json \
  --parameters adminPassword="<secure-password>"
```

📚 **Bicep Documentation:** [infra/bicep/README.md](infra/bicep/README.md)

## 📁 Project Structure

```
azd-azmigrate/
├── azure.yaml                      # Azure Developer CLI configuration
├── README.md                       # This file
├── DEPLOYMENT-GUIDE.md            # Complete step-by-step deployment guide
├── AZD-DEPLOYMENT.md              # azd-specific deployment documentation
├── QUICKSTART.md                  # Quick reference guide
├── scripts/
│   ├── CreateActualVMs.ps1        # Creates 6 bootable sample VMs on Hyper-V
│   └── Create_AzureMigrateAppliance.ps1  # Downloads and imports Azure Migrate appliance
├── data/
│   └── sample-servers.csv         # Sample server data for CSV import
├── .azure/
│   └── migrate-demo/              # Environment configuration
│       ├── .env                   # Environment variables
│       └── config.json            # Environment metadata
└── infra/
    └── bicep/
        ├── main.bicep             # Main orchestration template
        ├── main.parameters.json   # azd parameters with token substitution
        ├── parameters.json        # Production parameters
        ├── parameters.dev.json    # Development parameters
        ├── README.md              # Bicep deployment guide
        └── modules/
            ├── networking.bicep   # VNet, Bastion, NSGs
            ├── migrate-hub.bicep  # Azure Migrate resources
            ├── hyperv-host.bicep  # Hyper-V host VM
            ├── monitoring.bicep   # Log Analytics, diagnostics
            └── landing-zone.bicep # Availability Sets, PPG
```

### Key Scripts

**CreateActualVMs.ps1** - Run on Hyper-V host to create sample VMs
- Downloads Windows Server 2022 and Ubuntu 24.04 images
- Creates 6 bootable VMs (3 Windows, 3 Linux)
- Includes progress monitoring and automatic retry
- Time: 30-45 minutes

**Create_AzureMigrateAppliance.ps1** - Run on Hyper-V host to setup appliance
- Downloads official Azure Migrate appliance (~12GB)
- Imports VM with compatibility fixes
- Connects to Hyper-V network
- Time: 30-45 minutes

## 💰 Cost Estimates

| Configuration | Monthly Cost | Details |
|---------------|--------------|---------|
| **Full Demo** | $450-550 | Includes D16s_v5 Hyper-V host, Bastion |
| **No Hyper-V** | $150-250 | External Hyper-V environment |
| **Cost-Optimized** | $300-400 | D8s_v5 VM, basic monitoring |
| **Minimal** | $50-100 | Network and migrate hub only |

### Cost Savings
- **Stop Hyper-V VM** when not in use: **Save ~$450/month**
- **Use smaller VM** (D8s_v5): **Save ~$225/month**
- **Remove Bastion**: **Save ~$135/month**

## 🎯 Demo Features

### Discovery & Assessment
- ✅ Agentless VM discovery
- ✅ Performance-based sizing
- ✅ Dependency visualization
- ✅ TCO analysis
- ✅ Migration readiness assessment

### Migration Capabilities
- ✅ Test migrations with isolated networks
- ✅ Agentless replication
- ✅ Orchestrated cutover
- ✅ Azure Hybrid Benefit
- ✅ Database migration support

### Hybrid Connectivity
- ✅ Azure Bastion for secure access
- ✅ Multiple isolated subnets
- ✅ NSGs with application-aware rules

## 📊 What Gets Deployed

### Resource Groups (5)
1. **rg-migrate-hub** - Migration tooling
2. **rg-migrate-network** - Networking infrastructure
3. **rg-migrate-target** - Landing zone for migrated VMs
4. **rg-migrate-monitor** - Monitoring and logging
5. **rg-migrate-onprem** - On-premises simulation (Hyper-V)

### Networking (10.0.0.0/16)
- Hub VNet with 4 subnets
- Azure Bastion (Basic SKU)
- Network Security Groups with appropriate rules

### Compute
- **Hyper-V Host**: Standard_D16s_v5 (16 vCPU, 64GB RAM)
  - Windows Server 2022 Datacenter Azure Edition
  - 512GB Premium SSD data disk
  - Nested virtualization enabled
  - Public IP with DNS name

### Migration & Security
- Azure Migrate project
- Recovery Services Vault (LRS)
- Key Vault with RBAC
- Storage accounts (migrate + cache)

### Monitoring
- Log Analytics workspace
- VM Insights, Change Tracking, Security solutions
- Data Collection Rules
- Diagnostic storage account

## 🔐 Post-Deployment

### Access Hyper-V Host

**Via Azure Bastion:**
1. Open Azure Portal
2. Navigate to the Hyper-V VM
3. Click **Connect** → **Bastion**
4. Username: `azureadmin`
5. Password: (from deployment parameters)

**Via RDP:**
```powershell
# Get public IP
azd env get-value HYPERVHOSTPUBLICIP
# Connect with mstsc
```

### Setup Sample VMs and Appliance

After infrastructure deployment, configure the on-premises simulation:

**Step 1: Copy setup scripts to Hyper-V host**
```powershell
# On your local machine, copy scripts to the Hyper-V host
# (Use Azure Bastion file upload or RDP clipboard)
```

Copy these two scripts:
- `scripts/CreateActualVMs.ps1` - Creates 6 bootable sample VMs (3 Windows, 3 Ubuntu)
- `scripts/Create_AzureMigrateAppliance.ps1` - Downloads and imports Azure Migrate appliance

**Step 2: Create sample VMs**

On the Hyper-V host, run:
```powershell
.\CreateActualVMs.ps1
```

This will:
- Download Windows Server 2022 VHD (~10GB)
- Download Ubuntu 24.04 VHD (~2GB)
- Create 6 VMs: WIN-SQL-01/02, WIN-WEB-01/02, WIN-APP-01, LIN-DB-01
- Time: 30-45 minutes

**Step 3: Setup Azure Migrate Appliance**

On the Hyper-V host, run:
```powershell
.\Create_AzureMigrateAppliance.ps1
```

This will:
- Download appliance from https://aka.ms/migrate/appliance/hyperv (~12GB)
- Import VM with proper configuration
- Connect to network switch
- Time: 30-45 minutes

**Step 4: Configure and Start Discovery**

1. Start the appliance VM: `Start-VM -Name AzureMigrateAppliance`
2. Connect via Hyper-V Manager (wait 2-3 minutes for boot)
3. Open browser on appliance: https://localhost:44368
4. Register with your Azure Migrate project
5. Add Hyper-V host credentials and start discovery

## 🧹 Cleanup

### Remove All Resources

```powershell
# With azd
azd down --purge

# Or manually
az group list --query "[?starts_with(name, 'rg-migrate')].name" -o tsv | ForEach-Object {
    az group delete --name $_ --yes --no-wait
}
```

## 📚 Documentation

- **[AZD-DEPLOYMENT.md](AZD-DEPLOYMENT.md)** - Complete Azure Developer CLI guide
- **[infra/bicep/README.md](infra/bicep/README.md)** - Detailed Bicep documentation
- **[infra/bicep/QUICKSTART.md](infra/bicep/QUICKSTART.md)** - 5-minute quick start

## 🛠️ Customization

### Deployment Options

Configure via environment variables (azd) or parameters file:

```powershell
# Hyper-V Host
DEPLOY_HYPERV_HOST=true        # Deploy on-premises simulation
HYPERV_VM_SIZE=Standard_D16s_v5  # VM size for Hyper-V host

# Networking
DEPLOY_VPN_GATEWAY=true        # VPN Gateway for hybrid connectivity
DEPLOY_BASTION=true            # Azure Bastion for secure access

# Location
AZURE_LOCATION=eastus          # Azure region
```

### Supported Regions
- eastus
- westeurope
- westus2
- northeurope

### Supported VM Sizes (Hyper-V Host)
- Standard_D16s_v5 (recommended)
- Standard_D16s_v4
- Standard_E16s_v5
- Standard_D8s_v5 (cost-optimized)

## 🔧 Troubleshooting

### Common Issues

**Deployment timeout:** VPN Gateway takes 30-45 minutes - this is normal.

**Quota exceeded:**
```powershell
az vm list-usage --location eastus --query "[?name.value=='standardDSv5Family']"
```

**Nested virtualization not working:** Ensure you're using a supported VM size (DSv5 or ESv5 series).

## 📖 Next Steps (Roadmap)

- [x] **Phase 2:** Automated VM provisioning scripts for Hyper-V ✅
- [ ] **Phase 3:** Sample application deployment
- [ ] **Phase 4:** Migration orchestration scripts
- [ ] **Phase 5:** Performance testing and optimization

## 🤝 Contributing

This is a demo project. Feel free to customize and extend for your scenarios.

## 📄 License

This project is provided as-is for demonstration purposes.

## 🆘 Support

- [Azure Migrate Documentation](https://learn.microsoft.com/azure/migrate/)
- [Azure Developer CLI Documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)

---

**Version:** 1.0.0  
**Last Updated:** January 2026  
**Status:** ✅ Ready for Deployment
