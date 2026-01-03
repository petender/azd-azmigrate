# =====================================================
# Hyper-V Host Initial Setup Script
# =====================================================
# This script runs during Azure VM deployment via CustomScriptExtension
# Configures: Hyper-V role, data disk, virtual switch with NAT

$ErrorActionPreference = "Continue"
$VerbosePreference = "Continue"

# Log file
$logFile = "C:\HyperVSetup.log"
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message
}

Write-Log "=========================================="
Write-Log "Starting Hyper-V Host Setup"
Write-Log "=========================================="

try {
    # =====================================================
    # Install Hyper-V Role
    # =====================================================
    Write-Log "Installing Hyper-V role..."
    $hypervFeature = Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -ErrorAction Stop
    Write-Log "Hyper-V installed: $($hypervFeature.Success)"

    # =====================================================
    # Configure Data Disk (E: drive for VMs)
    # =====================================================
    Write-Log "Configuring data disk..."
    $disk = Get-Disk | Where-Object PartitionStyle -eq 'RAW' | Select-Object -First 1
    
    if ($disk) {
        Write-Log "Found RAW disk: $($disk.Number)"
        $disk | Initialize-Disk -PartitionStyle GPT -PassThru | 
            New-Partition -AssignDriveLetter -UseMaximumSize | 
            Format-Volume -FileSystem NTFS -NewFileSystemLabel 'VMs' -Confirm:$false
        
        Start-Sleep -Seconds 5
        
        $volume = Get-Volume | Where-Object FileSystemLabel -eq 'VMs'
        $driveLetter = $volume.DriveLetter
        
        if ($driveLetter) {
            Write-Log "Data disk formatted as ${driveLetter}:"
            
            # Create folder structure
            New-Item -Path "${driveLetter}:\VMs" -ItemType Directory -Force | Out-Null
            New-Item -Path "${driveLetter}:\VMs\BaseImages" -ItemType Directory -Force | Out-Null
            New-Item -Path "${driveLetter}:\VMs\VirtualMachines" -ItemType Directory -Force | Out-Null
            New-Item -Path "${driveLetter}:\ISOs" -ItemType Directory -Force | Out-Null
            
            # Set Hyper-V default paths
            Set-VMHost -VirtualHardDiskPath "${driveLetter}:\VMs\VirtualMachines" `
                       -VirtualMachinePath "${driveLetter}:\VMs\VirtualMachines" `
                       -ErrorAction SilentlyContinue
            
            Write-Log "Created folder structure on ${driveLetter}:"
        }
    } else {
        Write-Log "No RAW disk found, using C: drive"
    }

    # =====================================================
    # Create Internal Virtual Switch with NAT
    # =====================================================
    Write-Log "Configuring virtual switch with NAT..."
    
    $switchName = "Internal-Switch"
    $natNetwork = "192.168.100.0/24"
    $natGatewayIP = "192.168.100.1"
    $natName = "HyperVNAT"
    
    # Create Internal switch
    if (-not (Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue)) {
        Write-Log "Creating Internal switch: $switchName"
        New-VMSwitch -Name $switchName -SwitchType Internal -ErrorAction Stop | Out-Null
        Start-Sleep -Seconds 3
    } else {
        Write-Log "Switch $switchName already exists"
    }
    
    # Get the virtual network adapter
    $netAdapter = Get-NetAdapter | Where-Object Name -like "vEthernet ($switchName)"
    
    if ($netAdapter) {
        Write-Log "Found virtual adapter: $($netAdapter.Name)"
        $ifIndex = $netAdapter.ifIndex
        
        # Assign gateway IP to the host's virtual adapter
        $existingIP = Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if (-not $existingIP -or $existingIP.IPAddress -ne $natGatewayIP) {
            Write-Log "Configuring IP $natGatewayIP on adapter"
            New-NetIPAddress -IPAddress $natGatewayIP -PrefixLength 24 -InterfaceIndex $ifIndex -ErrorAction SilentlyContinue | Out-Null
        } else {
            Write-Log "IP $natGatewayIP already configured"
        }
        
        # Create NAT for internet access
        if (-not (Get-NetNat -Name $natName -ErrorAction SilentlyContinue)) {
            Write-Log "Creating NAT: $natName with network $natNetwork"
            New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix $natNetwork -ErrorAction Stop | Out-Null
        } else {
            Write-Log "NAT $natName already exists"
        }
        
        Write-Log "NAT configuration complete"
        Write-Log "  Gateway IP: $natGatewayIP"
        Write-Log "  Network: $natNetwork"
        Write-Log "  VMs should use IPs: 192.168.100.10 - 192.168.100.254"
    } else {
        Write-Log "Warning: Could not find virtual adapter for switch"
    }

    # =====================================================
    # Enable PowerShell Remoting
    # =====================================================
    Write-Log "Enabling PowerShell Remoting..."
    Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction SilentlyContinue
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force -ErrorAction SilentlyContinue
    Restart-Service WinRM -ErrorAction SilentlyContinue
    Write-Log "PowerShell Remoting enabled"

    # =====================================================
    # Configure Windows Firewall
    # =====================================================
    Write-Log "Configuring firewall rules..."
    
    # Allow WinRM
    New-NetFirewallRule -DisplayName "WinRM HTTP" -Direction Inbound -LocalPort 5985 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "WinRM HTTPS" -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue
    
    # Allow Hyper-V management
    New-NetFirewallRule -DisplayName "Hyper-V Management" -Direction Inbound -Protocol TCP -Action Allow -Program "%SystemRoot%\System32\vmms.exe" -ErrorAction SilentlyContinue
    
    Write-Log "Firewall rules configured"

    # =====================================================
    # Summary
    # =====================================================
    Write-Log "=========================================="
    Write-Log "Hyper-V Host Setup Complete"
    Write-Log "=========================================="
    Write-Log "Configuration Summary:"
    Write-Log "  - Hyper-V role: Installed"
    Write-Log "  - Data disk: Configured"
    Write-Log "  - Virtual switch: $switchName (Internal with NAT)"
    Write-Log "  - NAT gateway: $natGatewayIP"
    Write-Log "  - NAT network: $natNetwork"
    Write-Log "  - PowerShell Remoting: Enabled"
    Write-Log "  - Firewall: Configured"
    Write-Log ""
    Write-Log "Next steps:"
    Write-Log "  1. Reboot required for Hyper-V role"
    Write-Log "  2. Copy VM creation scripts"
    Write-Log "  3. VMs will get IPs from 192.168.100.10 onwards"
    Write-Log "=========================================="

    exit 0

} catch {
    Write-Log "ERROR: $_"
    Write-Log $_.Exception.Message
    Write-Log $_.ScriptStackTrace
    exit 0  # Don't fail deployment on setup errors
}
