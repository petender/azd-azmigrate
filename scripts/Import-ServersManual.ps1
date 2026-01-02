# =====================================================
# Manual Import Guide for Azure Migrate
# =====================================================
# Azure Migrate CSV import requires using the Portal or creating an assessment project first
# This script provides step-by-step guidance

$ErrorActionPreference = "Stop"

# Load environment variables
$envName = $env:AZURE_ENV_NAME
if (-not $envName) {
    # Try to get from .azure directory
    $azureDir = Join-Path (Split-Path $PSScriptRoot -Parent) ".azure"
    if (Test-Path $azureDir) {
        $envDirs = Get-ChildItem -Path $azureDir -Directory
        if ($envDirs.Count -gt 0) {
            $envName = $envDirs[0].Name
        }
    }
}

if ($envName) {
    $envFile = Join-Path (Split-Path $PSScriptRoot -Parent) ".azure\$envName\.env"
    if (Test-Path $envFile) {
        Get-Content $envFile | ForEach-Object {
            if ($_ -match '^([^=]+)=(.*)$') {
                $key = $matches[1]
                $value = $matches[2].Trim('"')
                Set-Item -Path "env:$key" -Value $value
            }
        }
    }
}

$ResourceGroupName = "rg-$env:AZURE_ENV_NAME-hub"
$MigrateProjectName = $env:migrateProjectName

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Azure Migrate - Import Servers Guide" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "📋 CSV File Location:" -ForegroundColor Yellow
Write-Host "  $(Resolve-Path '.\data\sample-servers.csv')" -ForegroundColor White
Write-Host "`n10 servers ready to import:" -ForegroundColor Gray
$servers = Import-Csv -Path ".\data\sample-servers.csv"
foreach ($server in $servers) {
    Write-Host "  • $($server.ServerName) - $($server.OperatingSystem) - $($server.Cores)C/$($server.Memory)MB/$($server.Storage)GB" -ForegroundColor Gray
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Import Method 1: Azure Portal (Recommended)" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "1️⃣  Open Azure Portal and navigate to Azure Migrate:" -ForegroundColor White
$portalUrl = "https://portal.azure.com/#view/Microsoft_Azure_Migrate/MigrationMenuBlade/~/overview"
Write-Host "   $portalUrl" -ForegroundColor Cyan

Write-Host "`n2️⃣  Select your project:" -ForegroundColor White
Write-Host "   Project: $MigrateProjectName" -ForegroundColor Gray
Write-Host "   Resource Group: rg-mig1026am-hub" -ForegroundColor Gray

Write-Host "`n3️⃣  Import servers:" -ForegroundColor White
Write-Host "   a. Click 'Servers, databases and web apps'" -ForegroundColor Gray
Write-Host "   b. Click 'Discover' button" -ForegroundColor Gray
Write-Host "   c. Select 'Import using CSV'" -ForegroundColor Gray
Write-Host "   d. Download template CSV" -ForegroundColor Gray
Write-Host "   e. Upload our sample-servers.csv" -ForegroundColor Gray
Write-Host "   f. Click 'Import'" -ForegroundColor Gray

Write-Host "`n4️⃣  Wait for processing (5-10 minutes)" -ForegroundColor White
Write-Host "   Servers will appear in 'Discovered servers' list" -ForegroundColor Gray

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Import Method 2: Azure Migrate Appliance (Full Discovery)" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "For actual Hyper-V VM discovery (the 6 VMs you just created):" -ForegroundColor White
Write-Host "`n1️⃣  Run Option 4 from the menu to setup the appliance" -ForegroundColor Gray
Write-Host "2️⃣  The appliance will discover the 6 VMs on your Hyper-V host" -ForegroundColor Gray
Write-Host "3️⃣  Servers will appear automatically in Azure Migrate" -ForegroundColor Gray

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Alternative: Create Assessment Project via API" -ForegroundColor Yellow
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Would you like to:" -ForegroundColor White
Write-Host "  [1] Open Azure Portal now (launches browser)" -ForegroundColor Gray
Write-Host "  [2] Copy CSV path to clipboard" -ForegroundColor Gray
Write-Host "  [3] Continue to Option 4 (Setup Appliance)" -ForegroundColor Gray
Write-Host "  [0] Return to main menu" -ForegroundColor Gray
Write-Host ""

$choice = Read-Host "Enter choice"

switch ($choice) {
    "1" {
        Write-Host "`n🌐 Opening Azure Portal..." -ForegroundColor Cyan
        Start-Process $portalUrl
        Write-Host "  ✓ Portal opened in browser" -ForegroundColor Green
    }
    "2" {
        $csvPath = (Resolve-Path '.\data\sample-servers.csv').Path
        Set-Clipboard -Value $csvPath
        Write-Host "`n📋 CSV path copied to clipboard:" -ForegroundColor Green
        Write-Host "   $csvPath" -ForegroundColor White
    }
    "3" {
        Write-Host "`n➡️  Launching Setup Appliance..." -ForegroundColor Cyan
        # Pass values directly since we already loaded them
        $hypervIp = $env:hypervHostPublicIp
        $username = $env:ADMIN_USERNAME
        $password = ConvertTo-SecureString $env:ADMIN_PASSWORD -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential($username, $password)
        
        & "$PSScriptRoot\Setup-AzureMigrateAppliance.ps1" -HyperVHostIP $hypervIp -Credential $cred -ResourceGroupName $ResourceGroupName -MigrateProjectName $MigrateProjectName
    }
    "0" {
        Write-Host "`n↩️  Returning to menu..." -ForegroundColor Gray
    }
    default {
        Write-Host "`n❌ Invalid choice" -ForegroundColor Red
    }
}

Write-Host "`n💡 Note: The CSV import feature in Portal is the easiest method for demo purposes." -ForegroundColor Yellow
Write-Host "   For production scenarios, use the Azure Migrate Appliance (Option 4) instead." -ForegroundColor Gray
Write-Host ""
