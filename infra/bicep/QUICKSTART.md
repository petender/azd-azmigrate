# Quick Deployment Guide

## Prerequisites Checklist
- [ ] Azure CLI installed
- [ ] Azure subscription with Owner/Contributor access
- [ ] PowerShell 7+ or Bash
- [ ] Regional quota for Standard_D16s_v5 VMs

## 5-Minute Quick Start

### 1. Login and Set Subscription
```powershell
az login
az account set --subscription "<your-subscription-id>"
```

### 2. Set Password
```powershell
$password = Read-Host -AsSecureString "Enter VM admin password"
$passwordText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
```

### 3. Deploy
```powershell
az deployment sub create `
  --name "migrate-demo-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
  --location eastus `
  --template-file main.bicep `
  --parameters environmentPrefix=migrate `
  --parameters adminUsername=azureadmin `
  --parameters "adminPassword=$passwordText" `
  --parameters deployHyperVHost=true `
  --parameters deployVpnGateway=true `
  --parameters deployBastion=true
```

### 4. Wait (45-60 minutes)
The deployment will complete automatically. VPN Gateway takes the longest.

### 5. Get Connection Info
```powershell
# Get deployment outputs
$outputs = az deployment sub show --name "migrate-demo-<timestamp>" --query properties.outputs -o json | ConvertFrom-Json

# Display Hyper-V host info
Write-Host "Hyper-V Host Public IP: $($outputs.hypervHostPublicIp.value)"
Write-Host "Hyper-V Host FQDN: $($outputs.hypervHostFqdn.value)"
Write-Host "Username: azureadmin"
```

### 6. Connect via Bastion
1. Open Azure Portal
2. Navigate to the Hyper-V VM
3. Click **Connect** → **Bastion**
4. Enter username and password

## Done! 🎉

Your Azure Migrate demo environment is ready.

## What's Included?
✅ Azure Migrate project  
✅ Hyper-V host (D16s_v5) with 512GB data disk  
✅ Hub VNet with 6 subnets  
✅ Azure Bastion for secure access  
✅ VPN Gateway for hybrid connectivity  
✅ Log Analytics workspace with VM Insights  
✅ Availability Sets for target VMs  
✅ Recovery Services Vault  
✅ Key Vault for secrets  

## Next Steps
1. [Deploy sample VMs on Hyper-V host](#)
2. [Configure Azure Migrate appliance](#)
3. [Run discovery and assessment](#)

See [README.md](README.md) for complete documentation.
