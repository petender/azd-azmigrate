# Azure Migrate Demo Setup - Simple Version
# Run this script INSIDE the Hyper-V VM via Bastion

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Azure Migrate Demo - Complete Setup" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script will:" -ForegroundColor Yellow
Write-Host "  1. Create 6 sample VMs" -ForegroundColor Gray
Write-Host "  2. Download and setup Azure Migrate appliance" -ForegroundColor Gray
Write-Host ""

$confirm = Read-Host "Continue? (Y/N)"
if ($confirm -ne 'Y') {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit
}

# Get Hyper-V host configuration
$vmHost = Get-VMHost

# Check for virtual switch
Write-Host ""
Write-Host "Checking for virtual switch..." -ForegroundColor Cyan
$switches = Get-VMSwitch
if ($switches) {
    $switchName = $switches[0].Name
    Write-Host "Using existing switch: $switchName" -ForegroundColor Green
}
else {
    Write-Host "Creating Internal switch..." -ForegroundColor Gray
    $switchName = "Internal-Switch"
    New-VMSwitch -Name $switchName -SwitchType Internal | Out-Null
    Write-Host "Created switch: $switchName" -ForegroundColor Green
}

# Create 6 sample VMs
Write-Host ""
Write-Host "Creating 6 sample VMs..." -ForegroundColor Cyan

$vms = @(
    @{ Name = "WIN-SQL-01"; Memory = 4GB; Disk = 60GB; CPUs = 2 }
    @{ Name = "WIN-WEB-01"; Memory = 2GB; Disk = 40GB; CPUs = 2 }
    @{ Name = "WIN-APP-01"; Memory = 4GB; Disk = 50GB; CPUs = 2 }
    @{ Name = "LIN-WEB-01"; Memory = 2GB; Disk = 40GB; CPUs = 2 }
    @{ Name = "LIN-DB-01"; Memory = 4GB; Disk = 60GB; CPUs = 2 }
    @{ Name = "LIN-APP-01"; Memory = 2GB; Disk = 40GB; CPUs = 2 }
)

$created = 0
foreach ($vm in $vms) {
    $exists = Get-VM -Name $vm.Name -ErrorAction SilentlyContinue
    if ($exists) {
        Write-Host "  $($vm.Name) already exists, skipping" -ForegroundColor Yellow
        continue
    }
    
    Write-Host "  Creating $($vm.Name)..." -ForegroundColor Gray
    
    $params = @{
        Name = $vm.Name
        MemoryStartupBytes = $vm.Memory
        Generation = 2
        NewVHDPath = "$($vmHost.VirtualHardDiskPath)\$($vm.Name).vhdx"
        NewVHDSizeBytes = $vm.Disk
        SwitchName = $switchName
    }
    
    New-VM @params | Out-Null
    Set-VM -Name $vm.Name -ProcessorCount $vm.CPUs
    Write-Host "  Created $($vm.Name)" -ForegroundColor Green
    $created++
}

Write-Host ""
Write-Host "Summary: Created $created VMs" -ForegroundColor Green
Write-Host "Total VMs: $((Get-VM).Count)" -ForegroundColor White

# Download and setup appliance
Write-Host ""
Write-Host "Setting up Azure Migrate Appliance..." -ForegroundColor Cyan

$applianceName = "AzureMigrateAppliance"
$applianceVhdPath = "E:\VMs\$applianceName.vhdx"
$applianceZipUrl = "https://aka.ms/migrate/appliance/hyperv"
$downloadPath = "E:\ISOs\AzureMigrateAppliance.zip"

# Check if appliance already exists
$existingAppliance = Get-VM -Name $applianceName -ErrorAction SilentlyContinue
if ($existingAppliance) {
    Write-Host "Appliance VM already exists!" -ForegroundColor Yellow
    $overwrite = Read-Host "Remove and recreate? (Y/N)"
    if ($overwrite -eq 'Y') {
        Stop-VM -Name $applianceName -Force -ErrorAction SilentlyContinue
        Remove-VM -Name $applianceName -Force
        if (Test-Path $applianceVhdPath) {
            Remove-Item $applianceVhdPath -Force
        }
        Write-Host "Removed existing appliance" -ForegroundColor Green
    }
    else {
        Write-Host "Skipping appliance setup" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Setup completed!" -ForegroundColor Green
        exit
    }
}

# Download appliance
Write-Host ""
Write-Host "Downloading Azure Migrate Appliance..." -ForegroundColor Gray
Write-Host "This will take 10-20 minutes..." -ForegroundColor Gray

$downloadDir = Split-Path $downloadPath -Parent
if (-not (Test-Path $downloadDir)) {
    New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
}

$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri $applianceZipUrl -OutFile $downloadPath -UseBasicParsing
$ProgressPreference = 'Continue'

$size = (Get-Item $downloadPath).Length / 1GB
Write-Host "Downloaded: $([math]::Round($size, 2)) GB" -ForegroundColor Green

# Extract appliance
Write-Host ""
Write-Host "Extracting appliance files..." -ForegroundColor Gray

$extractPath = "E:\VMs\AzureMigrateAppliance_Temp"
if (Test-Path $extractPath) {
    Remove-Item $extractPath -Recurse -Force
}

Expand-Archive -Path $downloadPath -DestinationPath $extractPath -Force

Write-Host "Searching for VHD/VHDX file..." -ForegroundColor Gray
$vhdFile = Get-ChildItem -Path $extractPath -Filter "*.vhd" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
$vhdxFile = Get-ChildItem -Path $extractPath -Filter "*.vhdx" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $vhdFile -and -not $vhdxFile) {
    Write-Host "Error: No VHD or VHDX file found in $extractPath" -ForegroundColor Red
    Write-Host "Contents of extraction directory:" -ForegroundColor Yellow
    Get-ChildItem -Path $extractPath -Recurse | Select-Object FullName | Format-Table -AutoSize
    Write-Host "`nPlease check the directory structure above." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit
}

if ($vhdxFile) {
    Write-Host "Found VHDX: $($vhdxFile.Name)" -ForegroundColor Gray
    Move-Item -Path $vhdxFile.FullName -Destination $applianceVhdPath -Force
} elseif ($vhdFile) {
    Write-Host "Found VHD: $($vhdFile.Name)" -ForegroundColor Gray
    Write-Host "Converting VHD to VHDX format..." -ForegroundColor Gray
    Convert-VHD -Path $vhdFile.FullName -DestinationPath $applianceVhdPath -VHDType Dynamic
    Write-Host "Conversion completed" -ForegroundColor Green
}
Remove-Item $extractPath -Recurse -Force
Remove-Item $downloadPath -Force

Write-Host "Extracted appliance VHDX" -ForegroundColor Green

# Create appliance VM
Write-Host ""
Write-Host "Creating appliance VM..." -ForegroundColor Gray

$appParams = @{
    Name = $applianceName
    MemoryStartupBytes = 16GB
    Generation = 2
    VHDPath = $applianceVhdPath
    SwitchName = $switchName
}

New-VM @appParams | Out-Null
Set-VM -Name $applianceName -ProcessorCount 4 -DynamicMemory -MemoryMinimumBytes 8GB -MemoryMaximumBytes 16GB

Write-Host "Appliance VM created" -ForegroundColor Green

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Setup Completed Successfully!" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

Write-Host "Sample VMs:" -ForegroundColor Cyan
$allVMs = Get-VM | Where-Object { $_.Name -ne $applianceName }
foreach ($vm in $allVMs) {
    Write-Host "  $($vm.Name) - $($vm.State)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Appliance:" -ForegroundColor Cyan
Write-Host "  $applianceName - $((Get-VM -Name $applianceName).State)" -ForegroundColor Gray

Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Start the appliance:" -ForegroundColor White
Write-Host "     Start-VM -Name '$applianceName'" -ForegroundColor Cyan
Write-Host ""
Write-Host "  2. Connect to the appliance:" -ForegroundColor White
Write-Host "     Use Hyper-V Manager to connect to the VM" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Configure the appliance:" -ForegroundColor White
Write-Host "     - Open browser to https://localhost:44368" -ForegroundColor Gray
Write-Host "     - Sign in with Azure credentials" -ForegroundColor Gray
Write-Host "     - Register with your Azure Migrate project" -ForegroundColor Gray
Write-Host "     - Add Hyper-V host credentials" -ForegroundColor Gray
Write-Host "     - Start discovery" -ForegroundColor Gray
Write-Host ""
