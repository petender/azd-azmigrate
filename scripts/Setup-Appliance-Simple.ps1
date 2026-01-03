# Azure Migrate Appliance Setup - No Escape Sequences Version
# Copy this entire script and paste into PowerShell in the VM

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host " Azure Migrate Appliance Setup" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$confirmation = Read-Host "Download and setup appliance? (Y/N)"
if ($confirmation -ne 'Y' -and $confirmation -ne 'y') {
    Write-Host "Cancelled" -ForegroundColor Yellow
    exit 0
}

# Get or create virtual switch
Write-Host ""
Write-Host "Checking virtual switch..." -ForegroundColor Cyan
$switches = Get-VMSwitch
if ($switches) {
    $switchName = $switches[0].Name
    Write-Host "  Using: $switchName" -ForegroundColor Green
} else {
    $switchName = "Internal-Switch"
    New-VMSwitch -Name $switchName -SwitchType Internal | Out-Null
    Write-Host "  Created: $switchName" -ForegroundColor Green
}

# Download appliance
Write-Host ""
Write-Host "Downloading appliance (10-15 minutes)..." -ForegroundColor Cyan
$url = "https://aka.ms/migrate/appliance/hyperv"
$zipPath = "E:\ISOs\AzureMigrateAppliance.zip"
$tempPath = "E:\VMs\Appliance_Temp"
$finalVhdx = "E:\VMs\AzureMigrateAppliance.vhdx"

$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
$ProgressPreference = 'Continue'

$sizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 0)
Write-Host "  Downloaded: $sizeMB MB" -ForegroundColor Green

# Extract
Write-Host ""
Write-Host "Extracting files..." -ForegroundColor Cyan
if (Test-Path $tempPath) {
    Remove-Item $tempPath -Recurse -Force
}
Expand-Archive -Path $zipPath -DestinationPath $tempPath -Force

# Find VHD or VHDX
Write-Host "  Searching for disk image..." -ForegroundColor Gray
$vhdFile = Get-ChildItem $tempPath -Filter "*.vhd" -Recurse -File | Select-Object -First 1
$vhdxFile = Get-ChildItem $tempPath -Filter "*.vhdx" -Recurse -File | Select-Object -First 1

if ($vhdxFile) {
    Write-Host "  Found VHDX: $($vhdxFile.Name)" -ForegroundColor Green
    Move-Item -Path $vhdxFile.FullName -Destination $finalVhdx -Force
} elseif ($vhdFile) {
    Write-Host "  Found VHD: $($vhdFile.Name)" -ForegroundColor Green
    Write-Host "  Converting to VHDX (2-3 minutes)..." -ForegroundColor Cyan
    Convert-VHD -Path $vhdFile.FullName -DestinationPath $finalVhdx -VHDType Dynamic
    Write-Host "  Converted successfully" -ForegroundColor Green
} else {
    Write-Host "  ERROR: No disk image found!" -ForegroundColor Red
    Write-Host "  Contents:" -ForegroundColor Yellow
    Get-ChildItem $tempPath -Recurse | Select-Object FullName
    exit 1
}

# Cleanup
Write-Host "  Cleaning up..." -ForegroundColor Gray
Remove-Item $tempPath -Recurse -Force
Remove-Item $zipPath -Force

# Create VM
Write-Host ""
Write-Host "Creating appliance VM..." -ForegroundColor Cyan
New-VM -Name "AzureMigrateAppliance" -MemoryStartupBytes 16GB -Generation 2 -VHDPath $finalVhdx -SwitchName $switchName | Out-Null
Set-VM -Name "AzureMigrateAppliance" -ProcessorCount 4 -DynamicMemory -MemoryMinimumBytes 8GB -MemoryMaximumBytes 16GB
Write-Host "  Created: AzureMigrateAppliance" -ForegroundColor Green

# Start VM
Write-Host ""
Write-Host "Starting appliance VM..." -ForegroundColor Cyan
Start-VM -Name "AzureMigrateAppliance"
Write-Host "  VM started" -ForegroundColor Green

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Setup Complete!" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Wait 5-10 minutes for first boot" -ForegroundColor White
Write-Host "  2. Connect to appliance VM:" -ForegroundColor White
Write-Host "     vmconnect localhost AzureMigrateAppliance" -ForegroundColor Cyan
Write-Host "  3. Inside appliance, open browser to:" -ForegroundColor White
Write-Host "     https://localhost:44368" -ForegroundColor Cyan
Write-Host "  4. Sign in with Azure credentials" -ForegroundColor White
Write-Host "  5. Register with Azure Migrate project" -ForegroundColor White
Write-Host "  6. Add Hyper-V credentials" -ForegroundColor White
Write-Host "  7. Start discovery" -ForegroundColor White
Write-Host ""

Get-VM "AzureMigrateAppliance" | Format-List Name, State, CPUUsage, MemoryAssigned
