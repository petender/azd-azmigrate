# =====================================================
# Azure Migrate Demo - Appliance Setup
# =====================================================
# Run this script INSIDE the Hyper-V VM via Bastion
# Use CreateActualVMs.ps1 to create sample VMs first

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Azure Migrate Appliance Setup" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "This script will:" -ForegroundColor Yellow
Write-Host "  1. Download Azure Migrate Appliance VHD (~12GB)" -ForegroundColor Gray
Write-Host "  2. Extract and setup the appliance VM" -ForegroundColor Gray
Write-Host "  3. Configure networking and requirements`n" -ForegroundColor Gray

Write-Host "Note: Make sure you have already created sample VMs" -ForegroundColor Yellow
Write-Host "      using the CreateActualVMs.ps1 script`n" -ForegroundColor Gray

$confirmation = Read-Host "Continue? (Y/N)"
if ($confirmation -ne 'Y' -and $confirmation -ne 'y') {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

# =====================================================
# Configuration
# =====================================================

# Check for virtual switch
Write-Host "`nChecking for virtual switch..." -ForegroundColor Cyan
$switches = Get-VMSwitch
if ($switches) {
    $switchName = $switches[0].Name
    Write-Host "  Using switch: $switchName" -ForegroundColor Green
} else {
    Write-Host "  Creating Internal switch..." -ForegroundColor Gray
    $switchName = "Internal-Switch"
    New-VMSwitch -Name $switchName -SwitchType Internal | Out-Null
    Write-Host "  Created switch: $switchName" -ForegroundColor Green
}

# Check for existing sample VMs
# $sampleVMs = Get-VM | Where-Object { $_.Name -match '^(WIN|LIN)-(SQL|WEB|APP|DB)-\d+$' }
# if ($sampleVMs.Count -eq 0) {
#     Write-Host "`nWarning: No sample VMs found!" -ForegroundColor Yellow
#     Write-Host "  Run CreateActualVMs.ps1 first to create sample VMs" -ForegroundColor Yellow
#     Write-Host "  The appliance needs VMs to discover`n" -ForegroundColor Gray
#     $continue = Read-Host "Continue anyway? (Y/N)"
#     if ($continue -ne 'Y' -and $continue -ne 'y') {
#         exit 0
#     }
# } else {
#     Write-Host "  Found $($sampleVMs.Count) sample VMs" -ForegroundColor Green
# }

# =====================================================
# Download and Setup Appliance
# =====================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Step 1: Download Appliance" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

$applianceName = "AzureMigrateAppliance"
$baseVhdPath = "E:\VMs\BaseImages"
$applianceBasePath = "E:\VMs\VirtualMachines\$applianceName"
$applianceZipUrl = "https://aka.ms/migrate/appliance/hyperv"
$downloadPath = "$baseVhdPath\AzureMigrateAppliance.zip"

# Create directories
if (-not (Test-Path $baseVhdPath)) {
    New-Item -ItemType Directory -Path $baseVhdPath -Force | Out-Null
}
$applianceDir = Split-Path $applianceBasePath
if (-not (Test-Path $applianceDir)) {
    New-Item -ItemType Directory -Path $applianceDir -Force | Out-Null
}

# Check for existing appliance disk
$existingVhdx = "$applianceBasePath.vhdx"
$existingVhd = "$applianceBasePath.vhd"
$applianceDiskPath = $null

if (Test-Path $existingVhdx) {
    $applianceDiskPath = $existingVhdx
    Write-Host "Appliance VHDX already exists" -ForegroundColor Green
    Write-Host "  Path: $applianceDiskPath" -ForegroundColor Gray
} elseif (Test-Path $existingVhd) {
    $applianceDiskPath = $existingVhd
    Write-Host "Appliance VHD already exists" -ForegroundColor Green
    Write-Host "  Path: $applianceDiskPath" -ForegroundColor Gray
}

if ($applianceDiskPath) {
    $overwrite = Read-Host "`nDelete and re-download? (Y/N)"
    if ($overwrite -ne 'Y' -and $overwrite -ne 'y') {
        Write-Host "Using existing appliance file" -ForegroundColor Yellow
    } else {
        Remove-Item $applianceDiskPath -Force
        if (Test-Path $downloadPath) {
            Remove-Item $downloadPath -Force
        }
        $applianceDiskPath = $null
    }
}

if (-not $applianceDiskPath) {
    if (-not (Test-Path $downloadPath)) {
        Write-Host "Downloading Azure Migrate Appliance (~12GB)..." -ForegroundColor Yellow
        Write-Host "  This will take 10-30 minutes depending on connection" -ForegroundColor Gray
        Write-Host "  URL: $applianceZipUrl`n" -ForegroundColor DarkGray
        
        try {
            # Try BITS transfer first
            Import-Module BitsTransfer -ErrorAction Stop
            Start-BitsTransfer -Source $applianceZipUrl -Destination $downloadPath -Description "Azure Migrate Appliance" -DisplayName "Downloading Azure Migrate Appliance"
        } catch {
            Write-Host "  BITS transfer failed, trying standard download..." -ForegroundColor Yellow
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $applianceZipUrl -OutFile $downloadPath -UseBasicParsing -TimeoutSec 3600
            $ProgressPreference = 'Continue'
        }
        
        $size = (Get-Item $downloadPath).Length / 1GB
        Write-Host "  Downloaded: $([math]::Round($size, 2)) GB" -ForegroundColor Green
    } else {
        Write-Host "Using existing download: $downloadPath" -ForegroundColor Green
    }

    Write-Host "`n  Extracting appliance files..." -ForegroundColor Gray
    Write-Host "  This may take 5-10 minutes..." -ForegroundColor DarkGray
    
    $extractPath = "$baseVhdPath\Temp"
    if (Test-Path $extractPath) {
        Remove-Item $extractPath -Recurse -Force
    }
    
    try {
        Expand-Archive -Path $downloadPath -DestinationPath $extractPath -Force
        
        Write-Host "  Searching for VHD/VHDX file..." -ForegroundColor DarkGray
        $vhdxFile = Get-ChildItem -Path $extractPath -Filter "*.vhdx" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        $vhdFile = Get-ChildItem -Path $extractPath -Filter "*.vhd" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if (-not $vhdFile -and -not $vhdxFile) {
            Write-Host "`n  Error: No VHD/VHDX file found!" -ForegroundColor Red
            Write-Host "  Contents of archive:" -ForegroundColor Yellow
            Get-ChildItem -Path $extractPath -Recurse | Select-Object FullName
            throw "No appliance disk image found in downloaded archive"
        }
        
        if ($vhdxFile) {
            Write-Host "  Found VHDX: $($vhdxFile.Name)" -ForegroundColor DarkGray
            $applianceDiskPath = "$applianceBasePath.vhdx"
            Write-Host "  Copying to final location..." -ForegroundColor DarkGray
            Copy-Item -Path $vhdxFile.FullName -Destination $applianceDiskPath -Force
        } elseif ($vhdFile) {
            Write-Host "  Found VHD: $($vhdFile.Name)" -ForegroundColor DarkGray
            $applianceDiskPath = "$applianceBasePath.vhd"
            Write-Host "  Copying to final location..." -ForegroundColor DarkGray
            Copy-Item -Path $vhdFile.FullName -Destination $applianceDiskPath -Force
        }
        
        Write-Host "  Saved: $applianceDiskPath" -ForegroundColor Green
        
        # Cleanup - use SilentlyContinue for locked files
        Write-Host "  Cleaning up temporary files..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 1
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
        
        if (Test-Path $extractPath) {
            Write-Host "  Note: Some temporary files couldn't be deleted (files in use)" -ForegroundColor Yellow
            Write-Host "        You can manually delete: $extractPath" -ForegroundColor Gray
        }
        
    } catch {
        Write-Host "`n  Extraction failed: $_" -ForegroundColor Red
        if (Test-Path $extractPath) {
            Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

# =====================================================
# Create Appliance VM
# =====================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Step 2: Create Appliance VM" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

# Check if VM already exists
$existingVM = Get-VM -Name $applianceName -ErrorAction SilentlyContinue
if ($existingVM) {
    Write-Host "  Appliance VM already exists, skipping" -ForegroundColor Yellow
} else {
    Write-Host "  Creating VM with disk: $applianceDiskPath" -ForegroundColor Gray
    
    $appParams = @{
        Name = $applianceName
        MemoryStartupBytes = 16GB
        Generation = 2
        VHDPath = $applianceDiskPath
        SwitchName = $switchName
    }
    
    New-VM @appParams | Out-Null
    Set-VM -Name $applianceName -ProcessorCount 4 -DynamicMemory -MemoryMinimumBytes 8GB -MemoryMaximumBytes 16GB
    
    Write-Host "  Appliance VM created" -ForegroundColor Green
}

# =====================================================
# Summary
# =====================================================

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " Setup Completed Successfully!" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "Sample VMs Available for Discovery:" -ForegroundColor Cyan
$allVMs = Get-VM | Where-Object { $_.Name -match '^(WIN|LIN)-(SQL|WEB|APP|DB)-\d+$' } | Sort-Object Name
if ($allVMs.Count -eq 0) {
    Write-Host "  None - Run CreateActualVMs.ps1 first" -ForegroundColor Yellow
} else {
    foreach ($vm in $allVMs) {
        $memory = [math]::Round($vm.MemoryStartup / 1GB, 0)
        Write-Host "  $($vm.Name) - $($vm.State) - $($memory)GB RAM" -ForegroundColor Gray
    }
}

Write-Host "`nAppliance VM:" -ForegroundColor Cyan
$appliance = Get-VM -Name $applianceName -ErrorAction SilentlyContinue
if ($appliance) {
    $appMemory = [math]::Round($appliance.MemoryStartup / 1GB, 0)
    Write-Host "  $applianceName - $($appliance.State) - $($appMemory)GB RAM" -ForegroundColor Gray
}

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. Start the appliance VM:" -ForegroundColor White
Write-Host "     Start-VM -Name '$applianceName'" -ForegroundColor Cyan
Write-Host "`n  2. Connect to appliance via Hyper-V Manager" -ForegroundColor White
Write-Host "     Wait for VM to boot (2-3 minutes)" -ForegroundColor Gray
Write-Host "`n  3. Access appliance configuration:" -ForegroundColor White
Write-Host "     - On the appliance VM, open browser" -ForegroundColor Gray
Write-Host "     - Navigate to: https://localhost:44368" -ForegroundColor Cyan
Write-Host "     - Accept prerequisites and license terms" -ForegroundColor Gray
Write-Host "`n  4. Register with Azure:" -ForegroundColor White
Write-Host "     - Sign in with your Azure credentials" -ForegroundColor Gray
Write-Host "     - Select your Azure Migrate project" -ForegroundColor Gray
Write-Host "     - Generate and enter appliance key from Azure Portal" -ForegroundColor Gray
Write-Host "`n  5. Configure discovery:" -ForegroundColor White
Write-Host "     - Add Hyper-V host credentials" -ForegroundColor Gray
Write-Host "     - Provide this host's IP or FQDN" -ForegroundColor Gray
Write-Host "     - Start discovery to find the sample VMs" -ForegroundColor Gray
Write-Host "`nFor detailed instructions, see: QUICKSTART.md`n" -ForegroundColor Cyan
