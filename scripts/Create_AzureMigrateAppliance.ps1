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

Write-Host "IMPORTANT: Get the latest appliance:" -ForegroundColor Yellow
Write-Host "  This script will automatically download the latest appliance from:" -ForegroundColor White
Write-Host "  https://go.microsoft.com/fwlink/?linkid=2191848" -ForegroundColor Cyan
Write-Host "" -ForegroundColor White
Write-Host "  Note: You'll need to register the appliance with Azure Portal after setup" -ForegroundColor Gray
Write-Host "        Generate an appliance key from Azure Migrate > Discovery and Assessment" -ForegroundColor Gray
Write-Host "" -ForegroundColor White

Write-Host "Note: Make sure you have already created sample VMs" -ForegroundColor Yellow
Write-Host "      using the Create_SampleVMs.ps1 script`n" -ForegroundColor Gray

$confirmation = Read-Host "Continue? (Y/N)"
if ($confirmation -ne 'Y' -and $confirmation -ne 'y') {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

# =====================================================
# Configuration
# =====================================================

# Network configuration for appliance
$applianceIP = "192.168.100.50"
$appliancePrefix = 24
$applianceGateway = "192.168.100.1"
$applianceDNS = @("8.8.8.8")

# Network configuration script templates
$ConfigureNetworkPs1Template = @"
# ConfigureNetwork.ps1 - Configure static IP after first boot
`$logFile = "C:\Windows\Temp\network-config.log"
Start-Transcript -Path `$logFile -Append

try {
    Write-Host "Starting network configuration..."
    
    # Wait a bit for network adapter to be ready
    Start-Sleep -Seconds 5
    
    # Find the active network adapter
    `$nic = (Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' } | Select-Object -First 1).InterfaceAlias
    if (-not `$nic) {
        `$nic = (Get-NetAdapter | Select-Object -First 1).InterfaceAlias
    }
    
    Write-Host "Using network adapter: `$nic"
    
    # Remove existing IP configuration
    Write-Host "Removing existing IP configuration..."
    Remove-NetIPAddress -InterfaceAlias `$nic -Confirm:`$false -ErrorAction SilentlyContinue
    Remove-NetRoute -InterfaceAlias `$nic -Confirm:`$false -ErrorAction SilentlyContinue
    
    Start-Sleep -Seconds 2
    
    # Configure static IP
    Write-Host "Configuring static IP: {{IPAddress}}/{{PrefixLength}}, Gateway: {{Gateway}}"
    New-NetIPAddress -InterfaceAlias `$nic -IPAddress '{{IPAddress}}' -PrefixLength {{PrefixLength}} -DefaultGateway '{{Gateway}}' -ErrorAction Stop
    
    # Configure DNS
    Write-Host "Configuring DNS servers: {{DnsArray}}"
    Set-DnsClientServerAddress -InterfaceAlias `$nic -ServerAddresses {{DnsArray}} -ErrorAction Stop
    
    Write-Host "Network configuration completed successfully!"
    Get-NetIPAddress -InterfaceAlias `$nic | Format-Table
    Get-DnsClientServerAddress -InterfaceAlias `$nic | Format-Table
    
} catch {
    Write-Host "ERROR: `$(`$_.Exception.Message)"
    `$_ | Out-File -Append -FilePath `$logFile
} finally {
    Stop-Transcript
}
"@

$SetupCompleteCmdTemplate = @"
@echo off
REM SetupComplete.cmd - Schedule network configuration to run on first logon
echo Scheduling network configuration for first logon...
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce" /v ConfigureNetwork /t REG_SZ /d "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\ConfigureNetwork.ps1" /f
echo Network configuration scheduled.
exit /b 0
"@

# Check for virtual switch
Write-Host "`nChecking for virtual switch..." -ForegroundColor Cyan
$switches = Get-VMSwitch
if ($switches) {
    # Use existing switch
    $switchName = $switches[0].Name
    Write-Host "  Using switch: $switchName ($($switches[0].SwitchType))" -ForegroundColor Green
} else {
    # Create External switch for internet access
    Write-Host "  Creating External switch for internet access..." -ForegroundColor Gray
    
    # Find physical network adapters (not virtual)
    $netAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
    
    if ($netAdapters -and $netAdapters.Count -gt 0) {
        $netAdapter = $netAdapters[0]
        $switchName = "External-Switch"
        
        try {
            New-VMSwitch -Name $switchName -NetAdapterName $netAdapter.Name -AllowManagementOS $true -ErrorAction Stop | Out-Null
            Write-Host "  Created switch: $switchName (External - bound to $($netAdapter.Name))" -ForegroundColor Green
        } catch {
            Write-Host "  Failed to create External switch: $_" -ForegroundColor Yellow
            Write-Host "  Creating Internal switch instead..." -ForegroundColor Gray
            $switchName = "Internal-Switch"
            New-VMSwitch -Name $switchName -SwitchType Internal | Out-Null
            Write-Host "  Created switch: $switchName (Internal - no internet access)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Warning: No physical network adapter found" -ForegroundColor Yellow
        Write-Host "  Available adapters:" -ForegroundColor Gray
        Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {
            Write-Host "    - $($_.Name): $($_.InterfaceDescription) (Virtual: $($_.Virtual))" -ForegroundColor DarkGray
        }
        Write-Host "  Creating Internal switch..." -ForegroundColor Gray
        $switchName = "Internal-Switch"
        New-VMSwitch -Name $switchName -SwitchType Internal | Out-Null
        Write-Host "  Created switch: $switchName (Internal - no internet access)" -ForegroundColor Yellow
    }
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
$downloadPath = "$baseVhdPath\AzureMigrateAppliance.zip"

# Use latest appliance URL
$applianceZipUrl = "https://go.microsoft.com/fwlink/?linkid=2191848"

# Check if appliance file already exists
if (Test-Path $downloadPath) {
    Write-Host "Found existing appliance file: $downloadPath" -ForegroundColor Green
    $size = [math]::Round((Get-Item $downloadPath).Length / 1GB, 2)
    Write-Host "  Size: $size GB" -ForegroundColor Gray
    Write-Host "  Skipping download" -ForegroundColor Gray
} else {
    Write-Host "Appliance file not found, will download automatically" -ForegroundColor Yellow
}

# Create directories
if (-not (Test-Path $baseVhdPath)) {
    New-Item -ItemType Directory -Path $baseVhdPath -Force | Out-Null
}
$applianceDir = Split-Path $applianceBasePath
if (-not (Test-Path $applianceDir)) {
    New-Item -ItemType Directory -Path $applianceDir -Force | Out-Null
}

# Check if VM already exists
$existingVM = Get-VM -Name $applianceName -ErrorAction SilentlyContinue
if ($existingVM) {
    Write-Host "Appliance VM already exists" -ForegroundColor Green
    Write-Host "  VM Name: $applianceName" -ForegroundColor Gray
    $recreate = Read-Host "`nDelete and recreate? (Y/N)"
    
    if ($recreate -eq 'Y' -or $recreate -eq 'y') {
        # Remove existing VM and its VHDs
        Stop-VM -Name $applianceName -Force -ErrorAction SilentlyContinue
        
        # Get VM's VHD paths before removing
        $vmDisks = Get-VMHardDiskDrive -VMName $applianceName -ErrorAction SilentlyContinue
        
        Remove-VM -Name $applianceName -Force
        Write-Host "Removed existing VM" -ForegroundColor Green
        
        # Clean up old appliance VHDs if recreating
        if ($vmDisks) {
            Write-Host "  Removing old appliance VHD files..." -ForegroundColor Gray
            foreach ($disk in $vmDisks) {
                if ($disk.Path -and (Test-Path $disk.Path)) {
                    try {
                        Remove-Item -Path $disk.Path -Force -ErrorAction Stop
                        Write-Host "    Deleted: $(Split-Path -Leaf $disk.Path)" -ForegroundColor DarkGray
                    } catch {
                        Write-Host "    Warning: Could not delete $(Split-Path -Leaf $disk.Path)" -ForegroundColor Yellow
                    }
                }
            }
        }
        
        # Also clean up the appliance directory if it exists
        if (Test-Path $applianceBasePath) {
            try {
                Remove-Item -Path $applianceBasePath -Recurse -Force -ErrorAction Stop
                Write-Host "  Cleaned appliance directory" -ForegroundColor DarkGray
            } catch {
                Write-Host "  Warning: Could not clean appliance directory" -ForegroundColor Yellow
            }
        }
        
        $skipSetup = $false
    }
} else {
    $skipSetup = $false
}

if (-not $skipSetup) {
    # Initialize variables
    $vmConfigFile = $null
    $applianceExtractPath = $null
    # Initialize variables
    $vmConfigFile = $null
    $applianceExtractPath = $null
    
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
        
        Write-Host "  Searching for VM configuration..." -ForegroundColor DarkGray
        
        # Find the VM configuration files
        $vmcxFiles = Get-ChildItem -Path $extractPath -Filter "*.vmcx" -Recurse -ErrorAction SilentlyContinue
        $xmlFiles = Get-ChildItem -Path $extractPath -Filter "*.xml" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Directory.Name -eq "Virtual Machines" }
        
        $vmConfigFile = $null
        if ($vmcxFiles) {
            $vmConfigFile = $vmcxFiles[0].FullName
            Write-Host "  Found VM config: $($vmcxFiles[0].Name)" -ForegroundColor DarkGray
        } elseif ($xmlFiles) {
            $vmConfigFile = $xmlFiles[0].FullName
            Write-Host "  Found VM config: $($xmlFiles[0].Name)" -ForegroundColor DarkGray
        } else {
            Write-Host "`n  Error: No VM configuration file found!" -ForegroundColor Red
            Write-Host "  Contents of archive:" -ForegroundColor Yellow
            Get-ChildItem -Path $extractPath -Recurse | Select-Object FullName
            throw "No VM configuration file found in downloaded archive"
        }
        
        # Store the extract path for later use
        $applianceExtractPath = $extractPath
        
    } catch {
        Write-Host "`n  Extraction failed: $_" -ForegroundColor Red
        if (Test-Path $extractPath) {
            Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

# =====================================================
# Import Appliance VM
# =====================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Step 2: Import Appliance VM" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

if (-not $skipSetup) {
    if ($vmConfigFile) {
        Write-Host "  Importing VM from: $vmConfigFile" -ForegroundColor Gray
        
        try {
            # Ensure appliance directory exists and is empty
            if (-not (Test-Path $applianceBasePath)) {
                New-Item -ItemType Directory -Path $applianceBasePath -Force | Out-Null
                Write-Host "  Created appliance directory: $applianceBasePath" -ForegroundColor DarkGray
            }
            
            # Use Compare-VM to check for issues before importing
            Write-Host "  Checking VM compatibility..." -ForegroundColor DarkGray
            $vmReport = Compare-VM -Path $vmConfigFile -Copy -GenerateNewId -VhdDestinationPath $applianceBasePath
            
            # Check and fix incompatibilities
            if ($vmReport.Incompatibilities) {
                Write-Host "  Found $($vmReport.Incompatibilities.Count) compatibility issue(s), fixing..." -ForegroundColor Yellow
                
                foreach ($incompatibility in $vmReport.Incompatibilities) {
                    Write-Host "    Issue: $($incompatibility.Message)" -ForegroundColor DarkGray
                    
                    # Fix network switch issues
                    if ($incompatibility.Message -match "switch" -or $incompatibility.MessageId -eq 33012) {
                        $networkAdapter = $incompatibility.Source
                        if ($networkAdapter) {
                            # Clear static MAC if set, then connect to switch
                            Set-VMNetworkAdapter -VMNetworkAdapter $networkAdapter -DynamicMacAddress -ErrorAction SilentlyContinue
                            Connect-VMNetworkAdapter -VMNetworkAdapter $networkAdapter -SwitchName $switchName
                            Write-Host "    Fixed: Connected network adapter to '$switchName'" -ForegroundColor Green
                        }
                    }
                }
                
                # Refresh the compatibility report after fixes
                $vmReport = Compare-VM -CompatibilityReport $vmReport
                
                if ($vmReport.Incompatibilities) {
                    Write-Host "`n  Warning: Some issues could not be auto-fixed:" -ForegroundColor Yellow
                    foreach ($incompatibility in $vmReport.Incompatibilities) {
                        Write-Host "    - $($incompatibility.Message)" -ForegroundColor Gray
                    }
                }
            } else {
                Write-Host "  No compatibility issues found" -ForegroundColor Green
            }
            
            # Import the VM using the report
            Write-Host "  Importing VM..." -ForegroundColor DarkGray
            $importedVM = Import-VM -CompatibilityReport $vmReport
            
            # Rename the VM
            Rename-VM -VM $importedVM -NewName $applianceName
            
            Write-Host "  VM imported successfully" -ForegroundColor Green
            
            # Verify network adapter connection
            Write-Host "  Verifying network configuration..." -ForegroundColor Gray
            $vmNetAdapter = Get-VMNetworkAdapter -VMName $applianceName
            if ($vmNetAdapter) {
                if (-not $vmNetAdapter.SwitchName) {
                    Connect-VMNetworkAdapter -VMNetworkAdapter $vmNetAdapter -SwitchName $switchName
                }
                Write-Host "  Network adapter connected to: $switchName" -ForegroundColor Green
            }
            
            # Inject network configuration scripts
            Write-Host "  Injecting static IP configuration ($applianceIP)..." -ForegroundColor Yellow
            try {
                # Find the appliance VHD
                $applianceVHD = Get-VMHardDiskDrive -VMName $applianceName | Select-Object -First 1
                if (-not $applianceVHD) {
                    Write-Host "    Warning: Could not find appliance VHD" -ForegroundColor Yellow
                } else {
                    $vhdPath = $applianceVHD.Path
                    Write-Host "    Mounting VHD: $vhdPath" -ForegroundColor DarkGray
                    
                    # Mount the VHD
                    Mount-VHD -Path $vhdPath -ErrorAction Stop
                    Start-Sleep -Seconds 2
                    
                    # Find the mounted drive
                    $disk = Get-Disk | Where-Object { $_.FriendlyName -like "*Virtual Disk*" -and $_.OperationalStatus -eq 'Online' } | Sort-Object Number | Select-Object -Last 1
                    if (-not $disk) {
                        throw "Could not find mounted disk"
                    }
                    
                    $partition = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.DriveLetter } | Select-Object -First 1
                    if (-not $partition) {
                        throw "Could not find partition with drive letter"
                    }
                    
                    $drive = $partition.DriveLetter + ":"
                    Write-Host "    Mounted at: $drive" -ForegroundColor DarkGray
                    
                    # Create directories for scripts
                    $setupScripts = Join-Path $drive "Windows\Setup\Scripts"
                    New-Item -ItemType Directory -Force -Path $setupScripts -ErrorAction SilentlyContinue | Out-Null
                    
                    # Generate ConfigureNetwork.ps1 with appliance IP settings
                    $dnsArrayStr = ($applianceDNS | ForEach-Object { "'$_'" }) -join ','
                    $configNetPs1 = $ConfigureNetworkPs1Template.Replace("{{IPAddress}}", $applianceIP).
                                                                  Replace("{{PrefixLength}}", $appliancePrefix.ToString()).
                                                                  Replace("{{Gateway}}", $applianceGateway).
                                                                  Replace("{{DnsArray}}", $dnsArrayStr)
                    
                    Set-Content -Path (Join-Path $setupScripts "ConfigureNetwork.ps1") -Value $configNetPs1 -Encoding UTF8
                    Write-Host "    Created ConfigureNetwork.ps1" -ForegroundColor DarkGray
                    
                    # Generate SetupComplete.cmd that schedules the network configuration
                    Set-Content -Path (Join-Path $setupScripts "SetupComplete.cmd") -Value $SetupCompleteCmdTemplate -Encoding ASCII
                    Write-Host "    Created SetupComplete.cmd" -ForegroundColor DarkGray
                    
                    # Dismount the VHD
                    Start-Sleep -Seconds 1
                    Dismount-VHD -Path $vhdPath -ErrorAction Stop
                    Write-Host "    Network configuration injected successfully" -ForegroundColor Green
                    Write-Host "    Appliance will be configured with IP: $applianceIP on first boot" -ForegroundColor Green
                }
            } catch {
                Write-Host "    Warning: Failed to inject network configuration: $_" -ForegroundColor Yellow
                Write-Host "    You may need to configure networking manually" -ForegroundColor Yellow
                # Try to dismount if something went wrong
                if ($vhdPath -and (Test-Path $vhdPath)) {
                    Dismount-VHD -Path $vhdPath -ErrorAction SilentlyContinue
                }
            }
            
            # Cleanup extraction folder
            Write-Host "  Cleaning up temporary files..." -ForegroundColor DarkGray
            Start-Sleep -Seconds 2
            Remove-Item $applianceExtractPath -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
            
            if (Test-Path $applianceExtractPath) {
                Write-Host "  Note: Some temporary files couldn't be deleted" -ForegroundColor Yellow
                Write-Host "        You can manually delete: $applianceExtractPath" -ForegroundColor Gray
            }
            
        } catch {
            Write-Host "`n  VM import failed: $_" -ForegroundColor Red
            throw
        }
    } else {
        Write-Host "  Error: No VM configuration available for import" -ForegroundColor Red
    }
} else {
    Write-Host "  Using existing appliance VM" -ForegroundColor Yellow
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
    Write-Host "  Configured IP: $applianceIP (will be applied on first boot)" -ForegroundColor Gray
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
