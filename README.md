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
- Azure Developer CLI (azd) or Azure CLI

### Deploy with Azure Developer CLI (Recommended)

```powershell
# Install azd (if not already installed)
winget install microsoft.azd

# Clone/navigate to repository
cd c:\azd-builds\azd-azmigrate

# Login and deploy
azd auth login
azd env new migrate-demo
azd env set AZURE_SUBSCRIPTION_ID "<your-subscription-id>"
azd env set ADMIN_PASSWORD "<secure-password>"
azd provision
```

**Deployment time:** 15-25 minutes

📚 **Full Documentation:** [AZD-DEPLOYMENT.md](AZD-DEPLOYMENT.md)

### Deploy with Azure CLI

```powershell
# Login
az login
az account set --subscription "<subscription-id>"

# Deploy
cd infra/bicep
az deployment sub create \
  --name "migrate-demo-$(Get-Date -Format 'yyyyMMdd-HHmmss')" \
  --location eastus \
  --template-file main.bicep \
  --parameters parameters.dev.json \
  --parameters adminPassword="<secure-password>"
```

📚 **Full Documentation:** [infra/bicep/README.md](infra/bicep/README.md)

## 📁 Project Structure

```
azd-azmigrate/
├── azure.yaml                      # Azure Developer CLI configuration
├── AZD-DEPLOYMENT.md              # Complete azd deployment guide
├── README.md                       # This file
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
        ├── QUICKSTART.md          # 5-minute deployment guide
        └── modules/
            ├── networking.bicep   # VNet, Bastion, VPN, NSGs
            ├── migrate-hub.bicep  # Azure Migrate resources
            ├── hyperv-host.bicep  # Hyper-V host VM
            ├── monitoring.bicep   # Log Analytics, diagnostics
            └── landing-zone.bicep # Availability Sets, PPG
```

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

### Configure Azure Migrate Appliance
1. Download appliance VHD from Azure Portal
2. Import to Hyper-V host
3. Register with Azure Migrate project
4. Start discovery

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

- [ ] **Phase 2:** Automated VM provisioning scripts for Hyper-V
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
