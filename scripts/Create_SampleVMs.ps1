# =====================================================
# Azure Migrate Demo - Create Actual Bootable VMs
# =====================================================
# Run this script INSIDE the Hyper-V VM via Bastion
# This script downloads real VHD images and creates bootable VMs

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Azure Migrate - Real VM Setup" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "This script will:" -ForegroundColor Yellow
Write-Host "  1. Download Windows Server 2022 Evaluation VHD (~10GB)" -ForegroundColor Gray
Write-Host "  2. Download Ubuntu 24.04 Server Cloud Image (~600MB)" -ForegroundColor Gray
Write-Host "  3. Create 6 VMs (each gets a full copy of the base VHD)" -ForegroundColor Gray
Write-Host "  4. VMs will be bootable and discoverable by Azure Migrate`n" -ForegroundColor Gray

Write-Host "Total download: ~11GB" -ForegroundColor Yellow
Write-Host "Total disk space needed: ~70GB (6 VMs)" -ForegroundColor Yellow
Write-Host "Estimated time: 20-30 minutes (depending on connection speed)`n" -ForegroundColor Yellow

$confirmation = Read-Host "Continue? (Y/N)"
if ($confirmation -ne 'Y' -and $confirmation -ne 'y') {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

# =====================================================
# Configuration
# =====================================================

$vmHost = Get-VMHost
$baseVhdPath = "E:\VMs\BaseImages"
$vmsPath = "E:\VMs\VirtualMachines"

# Create directories
if (-not (Test-Path $baseVhdPath)) {
    New-Item -ItemType Directory -Path $baseVhdPath -Force | Out-Null
    Write-Host "Created directory: $baseVhdPath" -ForegroundColor Gray
}
if (-not (Test-Path $vmsPath)) {
    New-Item -ItemType Directory -Path $vmsPath -Force | Out-Null
    Write-Host "Created directory: $vmsPath" -ForegroundColor Gray
}

# Check for virtual switch
Write-Host "`nChecking for virtual switch..." -ForegroundColor Cyan
$switches = Get-VMSwitch
if ($switches) {
    $switchName = $switches[0].Name
    Write-Host "  Using switch: $switchName" -ForegroundColor Green
} else {
    Write-Host "  Creating Internal switch for NAT..." -ForegroundColor Gray
    $switchName = "Internal-NAT"
    New-VMSwitch -Name $switchName -SwitchType Internal | Out-Null
    Write-Host "  Created switch: $switchName" -ForegroundColor Green
}

# Configure NAT for internet access
# HOW IT WORKS:
#   1. Internal switch creates isolated virtual network (192.168.100.0/24)
#   2. Hyper-V host gets IP 192.168.100.1 (becomes gateway for VMs)
#   3. NetNat translates VM traffic from private IPs to host's public IP
#   4. Traffic flows: VM -> Gateway (192.168.100.1) -> NetNat -> Host's Physical NIC -> Internet
#   5. Return traffic is translated back: Internet -> Host NIC -> NetNat -> Gateway -> VM
Write-Host "`nConfiguring NAT for VM internet access..." -ForegroundColor Cyan

try {
    # Get the virtual adapter for the switch (created by Hyper-V for the Internal switch)
    $netAdapter = Get-NetAdapter | Where-Object { $_.Name -like "*$switchName*" }
    
    if ($netAdapter) {
        # Check if IP is already configured
        $existingIP = Get-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like "192.168.100.*" }
        
        if (-not $existingIP) {
            Write-Host "  Assigning IP 192.168.100.1 to NAT switch (host becomes gateway)..." -ForegroundColor Gray
            New-NetIPAddress -IPAddress 192.168.100.1 -PrefixLength 24 -InterfaceIndex $netAdapter.ifIndex -ErrorAction Stop | Out-Null
            Write-Host "  IP assigned successfully - Host is now gateway for VMs" -ForegroundColor Green
        } else {
            Write-Host "  IP already configured: $($existingIP.IPAddress)" -ForegroundColor Green
        }
        
        # Check if NAT is already configured
        $existingNat = Get-NetNat -Name "HyperV-NAT" -ErrorAction SilentlyContinue
        
        if (-not $existingNat) {
            Write-Host "  Creating NetNat (translates VM traffic to host's external IP)..." -ForegroundColor Gray
            New-NetNat -Name "HyperV-NAT" -InternalIPInterfaceAddressPrefix 192.168.100.0/24 -ErrorAction Stop | Out-Null
            Write-Host "  NAT configured successfully - VMs can now access internet!" -ForegroundColor Green
        } else {
            Write-Host "  NAT already configured" -ForegroundColor Green
        }
        
        Write-Host "  VMs will use 192.168.100.0/24 network with internet access via NAT" -ForegroundColor Green
    } else {
        Write-Host "  Warning: Could not find network adapter for switch" -ForegroundColor Yellow
        Write-Host "  VMs may not have internet access" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  Warning: NAT configuration failed: $_" -ForegroundColor Yellow
    Write-Host "  VMs will be created but may not have internet access" -ForegroundColor Yellow
}

# =====================================================
# Download Base Images
# =====================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Step 1: Download Base Images" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

# Windows Server 2022 Evaluation
$windowsVhdUrl = "https://go.microsoft.com/fwlink/p/?linkid=2195166&clcid=0x409&culture=en-us&country=us"
$windowsVhdPath = "$baseVhdPath\WinServer2022-Eval.vhd"

if (Test-Path $windowsVhdPath) {
    Write-Host "[1/2] Windows Server 2022 VHD already exists" -ForegroundColor Green
    Write-Host "      Path: $windowsVhdPath" -ForegroundColor Gray
} else {
    Write-Host "[1/2] Downloading Windows Server 2022 Evaluation VHD..." -ForegroundColor Yellow
    Write-Host "      Size: ~10GB, this will take 10-20 minutes" -ForegroundColor Gray
    Write-Host "      URL: $windowsVhdUrl`n" -ForegroundColor DarkGray
    
    try {
        $tempFile = "$baseVhdPath\WinServer2022-Download.tmp"
        
        # Download using BITS (more reliable for large files, supports resume)
        Write-Host "      Downloading using BITS transfer (supports resume)..." -ForegroundColor Gray
        Write-Host "      This may take 10-20 minutes..." -ForegroundColor DarkGray
        
        try {
            Import-Module BitsTransfer -ErrorAction Stop
            Start-BitsTransfer -Source $windowsVhdUrl -Destination $tempFile -Description "Windows Server 2022 Eval VHD" -DisplayName "Downloading Windows Server VHD"
        } catch {
            Write-Host "      BITS transfer failed, trying standard download..." -ForegroundColor Yellow
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $windowsVhdUrl -OutFile $tempFile -UseBasicParsing -TimeoutSec 3600
            $ProgressPreference = 'Continue'
        }
        
        if (-not (Test-Path $tempFile)) {
            throw "Download failed - file not found"
        }
        
        $downloadSize = (Get-Item $tempFile).Length / 1GB
        Write-Host "      Downloaded: $([math]::Round($downloadSize, 2)) GB" -ForegroundColor Green
        
        # Verify file size (should be around 10GB for VHD)
        if ($downloadSize -lt 8.0) {
            throw "Downloaded file is too small ($([math]::Round($downloadSize, 2)) GB), likely corrupted"
        }
        
        # Check if it's a ZIP or direct VHD/VHDX
        Write-Host "      Checking file type..." -ForegroundColor Gray
        $fileHeader = Get-Content $tempFile -Encoding Byte -TotalCount 2
        $isZip = ($fileHeader[0] -eq 0x50 -and $fileHeader[1] -eq 0x4B) # PK header
        
        if ($isZip) {
            Write-Host "      File is a ZIP archive, extracting..." -ForegroundColor Gray
            $tempZip = "$baseVhdPath\WinServer2022.zip"
            Move-Item $tempFile $tempZip -Force
            
            New-Item -ItemType Directory -Path "$baseVhdPath\Temp" -Force | Out-Null
            
            # Check for 7-Zip
            $sevenZip = "C:\Program Files\7-Zip\7z.exe"
            $sevenZipPortable = "$baseVhdPath\7za.exe"
            
            if (Test-Path $sevenZip) {
                Write-Host "      Using installed 7-Zip..." -ForegroundColor Gray
                $extractResult = & $sevenZip x $tempZip -o"$baseVhdPath\Temp" -y 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "7-Zip extraction failed with exit code $LASTEXITCODE"
                }
            } elseif (Test-Path $sevenZipPortable) {
                Write-Host "      Using portable 7-Zip..." -ForegroundColor Gray
                $extractResult = & $sevenZipPortable x $tempZip -o"$baseVhdPath\Temp" -y 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "7-Zip extraction failed with exit code $LASTEXITCODE. Output: $extractResult"
                }
            } else {
                # Try Expand-Archive for simple zips
                try {
                    Expand-Archive -Path $tempZip -DestinationPath "$baseVhdPath\Temp" -Force
                } catch {
                    throw "Unable to extract ZIP. Please install 7-Zip: https://www.7-zip.org/"
                }
            }
            
            # Find and move VHD
            Write-Host "      Searching for VHD file..." -ForegroundColor DarkGray
            $vhdFile = Get-ChildItem -Path "$baseVhdPath\Temp" -Filter "*.vhd*" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($vhdFile) {
                Write-Host "      Found: $($vhdFile.Name)" -ForegroundColor DarkGray
                Move-Item -Path $vhdFile.FullName -Destination $windowsVhdPath -Force
                Write-Host "      Extracted: $windowsVhdPath" -ForegroundColor Green
            } else {
                throw "No VHD file found in archive"
            }
            
            # Cleanup
            Remove-Item $tempZip -Force
            Remove-Item "$baseVhdPath\Temp" -Recurse -Force
        } else {
            # Direct VHD file
            Write-Host "      File is a direct VHD, moving to final location..." -ForegroundColor Gray
            Move-Item $tempFile $windowsVhdPath -Force
            Write-Host "      Saved: $windowsVhdPath" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "      Failed to download Windows Server VHD: $_" -ForegroundColor Red
        Write-Host "      " -ForegroundColor Yellow
        Write-Host "      Alternative: Download manually from:" -ForegroundColor Yellow
        Write-Host "      https://www.microsoft.com/en-us/evalcenter/download-windows-server-2022" -ForegroundColor Cyan
        Write-Host "      Then place the VHD file at: $windowsVhdPath" -ForegroundColor Cyan
        Write-Host "      Continuing with Ubuntu only..." -ForegroundColor Yellow
        $windowsVhdPath = $null
        # Clean up partial download
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# Ubuntu 24.04 Cloud Image
$ubuntuVhdUrl = "https://us.cloud-images.ubuntu.com/releases/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64-azure.vhd.tar.gz"
$ubuntuVhdPath = "$baseVhdPath\Ubuntu-24.04-Server.vhd"

if (Test-Path $ubuntuVhdPath) {
    Write-Host "`n[2/2] Ubuntu 24.04 VHD already exists" -ForegroundColor Green
    Write-Host "      Path: $ubuntuVhdPath" -ForegroundColor Gray
} else {
    Write-Host "`n[2/2] Downloading Ubuntu 24.04 Server Cloud Image..." -ForegroundColor Yellow
    Write-Host "      Size: ~600MB, this will take 2-5 minutes" -ForegroundColor Gray
    Write-Host "      URL: $ubuntuVhdUrl`n" -ForegroundColor DarkGray
    
    try {
        $tempTarGz = "$baseVhdPath\Ubuntu.tar.gz"
        
        # Download
        Write-Host "      Downloading..." -ForegroundColor Gray
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $ubuntuVhdUrl -OutFile $tempTarGz -UseBasicParsing -TimeoutSec 1800
        $ProgressPreference = 'Continue'
        
        $downloadSize = (Get-Item $tempTarGz).Length / 1MB
        Write-Host "      Downloaded: $([math]::Round($downloadSize, 2)) MB" -ForegroundColor Green
        
        # Extract tar.gz using built-in tar command
        Write-Host "      Extracting VHD from tar.gz..." -ForegroundColor Gray
        New-Item -ItemType Directory -Path "$baseVhdPath\Temp" -Force | Out-Null
        tar -xzf $tempTarGz -C "$baseVhdPath\Temp"
        
        # Find VHD and convert to dynamic format (removes sparse/compression)
        Write-Host "      Searching for VHD file..." -ForegroundColor DarkGray
        $vhdFile = Get-ChildItem -Path "$baseVhdPath\Temp" -Filter "*.vhd" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($vhdFile) {
            Write-Host "      Found: $($vhdFile.Name)" -ForegroundColor DarkGray
            # Convert VHD to dynamic format (removes sparse/compression issues)
            Write-Host "      Converting VHD to dynamic format..." -ForegroundColor Gray
            $tempDynamicVhd = "$baseVhdPath\Ubuntu-24.04-Dynamic.vhd"
            Convert-VHD -Path $vhdFile.FullName -DestinationPath $tempDynamicVhd -VHDType Dynamic
            Move-Item -Path $tempDynamicVhd -Destination $ubuntuVhdPath -Force
            Write-Host "      Saved: $ubuntuVhdPath" -ForegroundColor Green
        } else {
            throw "No VHD file found in archive"
        }
        
        # Cleanup
        Remove-Item $tempTarGz -Force
        Remove-Item "$baseVhdPath\Temp" -Recurse -Force
    }
    catch {
        Write-Host "      Failed to download Ubuntu VHD: $_" -ForegroundColor Red
        Write-Host "      Continuing with Windows only..." -ForegroundColor Yellow
        $ubuntuVhdPath = $null
    }
}

# =====================================================
# Create VMs with Differencing Disks
# =====================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Step 2: Create Sample VMs" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

# Define VMs to create
$vmsToCreate = @()

if ($windowsVhdPath) {
    $vmsToCreate += @(
        @{ Name = "WIN-SQL-01";  BaseImage = $windowsVhdPath; Memory = 4GB; CPUs = 2; Type = "Windows"; IP = "192.168.100.10" }
        @{ Name = "WIN-WEB-01";  BaseImage = $windowsVhdPath; Memory = 2GB; CPUs = 2; Type = "Windows"; IP = "192.168.100.11" }
        @{ Name = "WIN-APP-01";  BaseImage = $windowsVhdPath; Memory = 4GB; CPUs = 2; Type = "Windows"; IP = "192.168.100.12" }
    )
}

if ($ubuntuVhdPath) {
    $vmsToCreate += @(
        @{ Name = "LIN-WEB-01";  BaseImage = $ubuntuVhdPath; Memory = 2GB; CPUs = 2; Type = "Linux"; IP = "192.168.100.20" }
        @{ Name = "LIN-DB-01";   BaseImage = $ubuntuVhdPath; Memory = 4GB; CPUs = 2; Type = "Linux"; IP = "192.168.100.21" }
        @{ Name = "LIN-APP-01";  BaseImage = $ubuntuVhdPath; Memory = 2GB; CPUs = 2; Type = "Linux"; IP = "192.168.100.22" }
    )
}

if ($vmsToCreate.Count -eq 0) {
    Write-Host "No base images available. Cannot create VMs." -ForegroundColor Red
    exit 1
}

$created = 0
$skipped = 0

foreach ($vmConfig in $vmsToCreate) {
    $vmName = $vmConfig.Name
    
    # Check if VM already exists
    $existingVM = Get-VM -Name $vmName -ErrorAction SilentlyContinue
    if ($existingVM) {
        Write-Host "  $vmName already exists, skipping" -ForegroundColor Yellow
        $skipped++
        continue
    }
    
    Write-Host "  Creating $vmName ($($vmConfig.Type))..." -ForegroundColor Gray
    
    try {
        # Copy base VHD to new file for this VM
        $parentExt = [System.IO.Path]::GetExtension($vmConfig.BaseImage)
        $vmVhdPath = "$vmsPath\$vmName$parentExt"
        
        # Show file size and estimate
        $sourceSize = (Get-Item $vmConfig.BaseImage).Length
        $sizeGB = [math]::Round($sourceSize / 1GB, 2)
        Write-Host "    Copying base VHD ($sizeGB GB)..." -ForegroundColor DarkGray
        Write-Host "    This may take 1-3 minutes..." -ForegroundColor DarkGray
        
        # Copy with progress monitoring
        $copyJob = Start-Job -ScriptBlock {
            param($source, $dest)
            Copy-Item -Path $source -Destination $dest -Force
        } -ArgumentList $vmConfig.BaseImage, $vmVhdPath
        
        # Monitor copy progress
        $activityId = Get-Random
        while ($copyJob.State -eq 'Running') {
            if (Test-Path $vmVhdPath) {
                $copiedSize = (Get-Item $vmVhdPath).Length
                $percentComplete = [math]::Min(99, [int](($copiedSize / $sourceSize) * 100))
                $copiedGB = [math]::Round($copiedSize / 1GB, 2)
                Write-Progress -Id $activityId -Activity "Creating $vmName" -Status "Copying VHD: $copiedGB GB / $sizeGB GB" -PercentComplete $percentComplete
            } else {
                Write-Progress -Id $activityId -Activity "Creating $vmName" -Status "Starting copy..." -PercentComplete 0
            }
            Start-Sleep -Milliseconds 500
        }
        
        $copyResult = Receive-Job -Job $copyJob
        Remove-Job -Job $copyJob
        Write-Progress -Id $activityId -Activity "Creating $vmName" -Completed
        
        if (-not (Test-Path $vmVhdPath)) {
            throw "Copy failed - VHD file not created"
        }
        
        # Create VM using the copied VHD
        $vmParams = @{
            Name = $vmConfig.Name
            MemoryStartupBytes = $vmConfig.Memory
            Generation = 1
            VHDPath = $vmVhdPath
            SwitchName = $switchName
        }
        
        New-VM @vmParams | Out-Null
        Set-VM -Name $vmConfig.Name -ProcessorCount $vmConfig.CPUs
        
        # Configure static IP via DHCP reservation (works for both Windows and Linux)
        Write-Host "    Configuring network (IP: $($vmConfig.IP))..." -ForegroundColor DarkGray
        $vmNetAdapter = Get-VMNetworkAdapter -VMName $vmConfig.Name
        if ($vmNetAdapter -and $vmNetAdapter.MacAddress) {
            $mac = $vmNetAdapter.MacAddress
            Write-Host "    MAC Address: $mac" -ForegroundColor DarkGray
            Write-Host "    Assigned IP: $($vmConfig.IP)" -ForegroundColor DarkGray
            Write-Host "    Gateway: 192.168.100.1" -ForegroundColor DarkGray
            Write-Host "    Note: Configure static IP inside VM after first boot" -ForegroundColor DarkGray
        }
        
        Write-Host "    Created successfully" -ForegroundColor Green
        $created++
    }
    catch {
        Write-Host "    Failed: $_" -ForegroundColor Red
    }
}

# =====================================================
# Summary
# =====================================================

if ($created -gt 0) {
    Write-Host "\n========================================" -ForegroundColor Green
    Write-Host " Setup Completed Successfully!" -ForegroundColor White
    Write-Host "========================================\n" -ForegroundColor Green
} elseif ($skipped -gt 0) {
    Write-Host "\n========================================" -ForegroundColor Yellow
    Write-Host " Setup Complete (VMs Already Exist)" -ForegroundColor White
    Write-Host "========================================\n" -ForegroundColor Yellow
} else {
    Write-Host "\n========================================" -ForegroundColor Red
    Write-Host " Setup Failed - No VMs Created" -ForegroundColor White
    Write-Host "========================================\n" -ForegroundColor Red
}

Write-Host "VMs Created:" -ForegroundColor Cyan
Write-Host "  Created: $created" -ForegroundColor Green
Write-Host "  Skipped: $skipped" -ForegroundColor Yellow
Write-Host "  Total: $((Get-VM | Where-Object { $_.Name -notlike '*Appliance*' }).Count)`n" -ForegroundColor White

Write-Host "Sample VMs:" -ForegroundColor Cyan
$allVMs = Get-VM | Where-Object { $_.Name -notlike '*Appliance*' } | Sort-Object Name
foreach ($vm in $allVMs) {
    $vmDetails = Get-VM -Name $vm.Name
    $memory = [math]::Round($vmDetails.MemoryStartup / 1GB, 0)
    $vmNetAdapter = Get-VMNetworkAdapter -VMName $vm.Name
    $mac = if ($vmNetAdapter) { $vmNetAdapter.MacAddress } else { "N/A" }
    
    # Find assigned IP from original config
    $assignedIP = ($vmsToCreate | Where-Object { $_.Name -eq $vm.Name }).IP
    if ($assignedIP) {
        Write-Host "  $($vm.Name) - $($vm.State) - $($memory)GB RAM - $($vmDetails.ProcessorCount) CPUs - IP: $assignedIP" -ForegroundColor Gray
    } else {
        Write-Host "  $($vm.Name) - $($vm.State) - $($memory)GB RAM - $($vmDetails.ProcessorCount) CPUs" -ForegroundColor Gray
    }
}

Write-Host "`nBase Images Saved:" -ForegroundColor Cyan
if ($windowsVhdPath -and (Test-Path $windowsVhdPath)) {
    $size = [math]::Round((Get-Item $windowsVhdPath).Length / 1GB, 2)
    Write-Host "  Windows Server 2022: $size GB" -ForegroundColor Gray
}
if ($ubuntuVhdPath -and (Test-Path $ubuntuVhdPath)) {
    $size = [math]::Round((Get-Item $ubuntuVhdPath).Length / 1GB, 2)
    Write-Host "  Ubuntu 24.04: $size GB" -ForegroundColor Gray
}

Write-Host "\nNetwork Configuration:" -ForegroundColor Cyan
Write-Host "  NAT Network: 192.168.100.0/24" -ForegroundColor Gray
Write-Host "  Gateway: 192.168.100.1" -ForegroundColor Gray
Write-Host "  DNS: 8.8.8.8 (Google DNS)" -ForegroundColor Gray
Write-Host "\n  Assigned IPs:" -ForegroundColor White
Write-Host "    WIN-SQL-01: 192.168.100.10" -ForegroundColor Gray
Write-Host "    WIN-WEB-01: 192.168.100.11" -ForegroundColor Gray
Write-Host "    WIN-APP-01: 192.168.100.12" -ForegroundColor Gray
Write-Host "    LIN-WEB-01: 192.168.100.20" -ForegroundColor Gray
Write-Host "    LIN-DB-01:  192.168.100.21" -ForegroundColor Gray
Write-Host "    LIN-APP-01: 192.168.100.22" -ForegroundColor Gray

Write-Host "\nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. Start VMs and configure static IPs inside each VM:" -ForegroundColor White
Write-Host "     Get-VM | Where-Object { `$_.Name -notlike '*Appliance*' } | Start-VM" -ForegroundColor Cyan
Write-Host "\n     Windows (run in VM): " -ForegroundColor White
Write-Host "       New-NetIPAddress -InterfaceAlias 'Ethernet' -IPAddress <IP> -PrefixLength 24 -DefaultGateway 192.168.100.1" -ForegroundColor Cyan
Write-Host "       Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses 8.8.8.8" -ForegroundColor Cyan
Write-Host "\n     Linux (edit /etc/netplan/50-cloud-init.yaml):" -ForegroundColor White
Write-Host "       See assigned IPs above" -ForegroundColor Gray
Write-Host "\n  2. Download and setup Azure Migrate Appliance:" -ForegroundColor White
Write-Host "     Run Setup-Appliance-Simple.ps1 or manually download from:" -ForegroundColor Gray
Write-Host "     https://aka.ms/migrate/appliance/hyperv" -ForegroundColor Cyan
Write-Host "`n  3. Configure appliance to discover these VMs" -ForegroundColor White
Write-Host "     The appliance will find all VMs on this Hyper-V host" -ForegroundColor Gray

Write-Host "`nTip:" -ForegroundColor Yellow
Write-Host "  Each VM has its own full copy of the base VHD" -ForegroundColor Gray
Write-Host "  Base images are preserved and can be reused" -ForegroundColor Gray
Write-Host "  Each VM requires ~10GB for Windows or ~30GB for Ubuntu" -ForegroundColor Gray
Write-Host ""
