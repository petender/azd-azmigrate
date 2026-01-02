#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Post-deployment guide for Azure Migrate demo setup.

.DESCRIPTION
    Provides instructions for manual setup steps after infrastructure deployment.
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$EnvironmentName
)

$ErrorActionPreference = "Continue"

# Get environment variables
if ([string]::IsNullOrEmpty($EnvironmentName)) {
    $EnvironmentName = $env:AZURE_ENV_NAME
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir

# Load environment variables
$envFile = Join-Path (Split-Path $scriptDir -Parent) ".azure\$EnvironmentName\.env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
        }
    }
}

$hypervHostPublicIp = $env:hypervHostPublicIp
$bastionName = $env:bastionName
$resourceGroup = $env:onpremResourceGroup
$adminUsername = $env:ADMIN_USERNAME

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Azure Migrate Demo - Next Steps" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "✅ Infrastructure deployment completed successfully!`n" -ForegroundColor Green

Write-Host "📋 Deployment Summary:" -ForegroundColor Yellow
Write-Host "  Resource Group: $resourceGroup" -ForegroundColor Gray
Write-Host "  Hyper-V Host: $hypervHostPublicIp" -ForegroundColor Gray
Write-Host "  Bastion: $bastionName" -ForegroundColor Gray
Write-Host "  Admin Username: $adminUsername`n" -ForegroundColor Gray

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " NEXT STEPS - Manual Setup Required" -ForegroundColor Yellow
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "📝 To complete the Azure Migrate demo setup:`n" -ForegroundColor White

Write-Host "STEP 1: Connect to Hyper-V Host via Azure Bastion" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Gray
Write-Host "  1. Open Azure Portal: https://portal.azure.com" -ForegroundColor White
Write-Host "  2. Navigate to: Resource Groups > $resourceGroup" -ForegroundColor White
Write-Host "  3. Click on the Hyper-V VM (vm-*-hyperv)" -ForegroundColor White
Write-Host "  4. Click 'Connect' > 'Bastion'" -ForegroundColor White
Write-Host "  5. Username: $adminUsername" -ForegroundColor White
Write-Host "  6. Password: <your admin password>" -ForegroundColor White
Write-Host "  7. Click 'Connect'`n" -ForegroundColor White

Write-Host "STEP 2: Run Setup Script Inside the VM" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Gray
Write-Host "  Once connected via Bastion:" -ForegroundColor White
Write-Host "  1. Open PowerShell as Administrator" -ForegroundColor White
Write-Host "  2. Run this command to copy the setup script:`n" -ForegroundColor White
Write-Host "     " -NoNewline
Write-Host "Invoke-WebRequest -Uri 'https://aka.ms/migrate/setup' -OutFile C:\temp\Setup-Simple.ps1" -ForegroundColor Yellow
Write-Host "`n     OR manually copy the script from:`n" -ForegroundColor White
Write-Host "     " -NoNewline
Write-Host "$scriptDir\Setup-Simple.ps1`n" -ForegroundColor Yellow
Write-Host "  3. Run the script:" -ForegroundColor White
Write-Host "     " -NoNewline
Write-Host "C:\temp\Setup-Simple.ps1`n" -ForegroundColor Yellow
Write-Host "  4. The script will:" -ForegroundColor White
Write-Host "     • Create 6 sample VMs (if not already created)" -ForegroundColor Gray
Write-Host "     • Download Azure Migrate appliance (~10-20 min)" -ForegroundColor Gray
Write-Host "     • Create and configure the appliance VM`n" -ForegroundColor Gray

Write-Host "STEP 3: Configure the Azure Migrate Appliance" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Gray
Write-Host "  After the setup script completes:" -ForegroundColor White
Write-Host "  1. Start the appliance VM:" -ForegroundColor White
Write-Host "     " -NoNewline
Write-Host "Start-VM -Name 'AzureMigrateAppliance'`n" -ForegroundColor Yellow
Write-Host "  2. Wait 5-10 minutes for first boot" -ForegroundColor White
Write-Host "  3. Connect via Hyper-V Manager or:" -ForegroundColor White
Write-Host "     " -NoNewline
Write-Host "vmconnect localhost 'AzureMigrateAppliance'`n" -ForegroundColor Yellow
Write-Host "  4. In the appliance VM, open browser to:" -ForegroundColor White
Write-Host "     " -NoNewline
Write-Host "https://localhost:44368`n" -ForegroundColor Yellow
Write-Host "  5. Follow the configuration wizard:" -ForegroundColor White
Write-Host "     • Accept license terms" -ForegroundColor Gray
Write-Host "     • Sign in with Azure credentials" -ForegroundColor Gray
Write-Host "     • Register with Azure Migrate project" -ForegroundColor Gray
Write-Host "     • Add Hyper-V credentials (username: $adminUsername)" -ForegroundColor Gray
Write-Host "     • Start discovery (discovers the 6 sample VMs)`n" -ForegroundColor Gray

Write-Host "STEP 4: (Optional) Import Additional Sample Servers" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Gray
Write-Host "  To import 10 additional sample servers:" -ForegroundColor White
Write-Host "  1. Open Azure Portal: https://portal.azure.com" -ForegroundColor White
Write-Host "  2. Navigate to: Azure Migrate > Servers, databases and web apps" -ForegroundColor White
Write-Host "  3. Click 'Discover' > 'Import using CSV'" -ForegroundColor White
Write-Host "  4. Upload the CSV file from:`n" -ForegroundColor White
Write-Host "     " -NoNewline
Write-Host "$rootDir\data\sample-servers.csv`n" -ForegroundColor Yellow
Write-Host "  5. Wait 5-10 minutes for processing`n" -ForegroundColor White

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Quick Actions" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Choose an action:`n" -ForegroundColor Yellow
Write-Host "  1. Open Azure Portal to Resource Group" -ForegroundColor White
Write-Host "  2. Copy Setup Script to Clipboard" -ForegroundColor White
Write-Host "  3. View Setup Script" -ForegroundColor White
Write-Host "  4. Copy CSV Import File Path" -ForegroundColor White
Write-Host "  0. Exit`n" -ForegroundColor White

$choice = Read-Host "Select option (0-4)"

switch ($choice) {
    "1" {
        $portalUrl = "https://portal.azure.com/#@/resource/subscriptions/$($env:AZURE_SUBSCRIPTION_ID)/resourceGroups/$resourceGroup/overview"
        Write-Host "`nOpening Azure Portal..." -ForegroundColor Cyan
        Start-Process $portalUrl
    }
    "2" {
        $setupScript = Join-Path $scriptDir "Setup-Simple.ps1"
        if (Test-Path $setupScript) {
            Get-Content $setupScript -Raw | Set-Clipboard
            Write-Host "`n✅ Setup script copied to clipboard!" -ForegroundColor Green
            Write-Host "   Paste it into PowerShell in the Bastion session" -ForegroundColor Gray
        } else {
            Write-Host "`n❌ Setup script not found: $setupScript" -ForegroundColor Red
        }
    }
    "3" {
        $setupScript = Join-Path $scriptDir "Setup-Simple.ps1"
        if (Test-Path $setupScript) {
            Write-Host "`nOpening setup script..." -ForegroundColor Cyan
            code $setupScript
        } else {
            Write-Host "`n❌ Setup script not found: $setupScript" -ForegroundColor Red
        }
    }
    "4" {
        $csvFile = Join-Path $rootDir "data\sample-servers.csv"
        $csvFile | Set-Clipboard
        Write-Host "`n✅ CSV file path copied to clipboard:" -ForegroundColor Green
        Write-Host "   $csvFile" -ForegroundColor Gray
    }
    "0" {
        Write-Host "`nExiting..." -ForegroundColor Gray
    }
    default {
        Write-Host "`n❌ Invalid option" -ForegroundColor Red
    }
}

Write-Host "`n💡 Tip: Run this menu anytime with:" -ForegroundColor Yellow
Write-Host "   .\scripts\Setup-AzureMigrateMenu.ps1`n" -ForegroundColor Cyan
