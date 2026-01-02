#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Creates sample VMs on the local Hyper-V host (run this script ON the Hyper-V VM).

.DESCRIPTION
    Creates 6 sample VMs for Azure Migrate testing - runs locally without PS remoting.
#>

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║        Creating Sample VMs on Local Hyper-V Host          ║" -ForegroundColor White
Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Verify Hyper-V is ready
Write-Host "🔍 Checking Hyper-V configuration..." -ForegroundColor Cyan
$vmHost = Get-VMHost
Write-Host "  VM Path: $($vmHost.VirtualMachinePath)" -ForegroundColor Gray
Write-Host "  VHD Path: $($vmHost.VirtualHardDiskPath)" -ForegroundColor Gray

# Check data disk
$volume = Get-Volume | Where-Object FileSystemLabel -eq 'VMs'
if ($volume) {
    Write-Host "  Data Disk: $($volume.DriveLetter):\ ($([math]::Round($volume.SizeRemaining/1GB, 2)) GB free)" -ForegroundColor Gray
} else {
    Write-Host "  ⚠️  Data disk 'VMs' not found, using C:\" -ForegroundColor Yellow
}

Write-Host ""

# Define sample VMs
$vms = @(
    @{ Name = "WIN-SQL-01"; OS = "Windows Server 2019"; Memory = 4GB; CPU = 2; Disk = 60GB }
    @{ Name = "WIN-WEB-01"; OS = "Windows Server 2019"; Memory = 2GB; CPU = 2; Disk = 40GB }
    @{ Name = "WIN-APP-01"; OS = "Windows Server 2016"; Memory = 4GB; CPU = 2; Disk = 50GB }
    @{ Name = "LIN-WEB-01"; OS = "Ubuntu 20.04"; Memory = 2GB; CPU = 2; Disk = 40GB }
    @{ Name = "LIN-DB-01"; OS = "Ubuntu 20.04"; Memory = 4GB; CPU = 2; Disk = 60GB }
    @{ Name = "LIN-APP-01"; OS = "CentOS 7"; Memory = 2GB; CPU = 2; Disk = 40GB }
)

$created = 0
$failed = 0

foreach ($vmConfig in $vms) {
    Write-Host "Creating VM: $($vmConfig.Name)" -ForegroundColor Cyan
    Write-Host "  OS: $($vmConfig.OS), Memory: $([math]::Round($vmConfig.Memory/1GB))GB, CPU: $($vmConfig.CPU), Disk: $([math]::Round($vmConfig.Disk/1GB))GB" -ForegroundColor Gray
    
    try {
        # Check if VM already exists
        $existingVM = Get-VM -Name $vmConfig.Name -ErrorAction SilentlyContinue
        if ($existingVM) {
            Write-Host "  ⚠️  VM already exists, skipping" -ForegroundColor Yellow
            continue
        }
        
        # Create VM
        $vm = New-VM -Name $vmConfig.Name `
                     -MemoryStartupBytes $vmConfig.Memory `
                     -Generation 2 `
                     -NewVHDPath "$($vmHost.VirtualHardDiskPath)\$($vmConfig.Name).vhdx" `
                     -NewVHDSizeBytes $vmConfig.Disk `
                     -SwitchName "Default Switch"
        
        # Configure CPU
        Set-VMProcessor -VMName $vmConfig.Name -Count $vmConfig.CPU
        
        # Configure dynamic memory
        Set-VMMemory -VMName $vmConfig.Name -DynamicMemoryEnabled $true -MinimumBytes 512MB -MaximumBytes $vmConfig.Memory
        
        # Add notes/tags
        Set-VM -Name $vmConfig.Name -Notes "Sample VM for Azure Migrate testing. OS: $($vmConfig.OS)"
        
        Write-Host "  ✅ Created successfully" -ForegroundColor Green
        $created++
        
    } catch {
        Write-Host "  ❌ Failed: $_" -ForegroundColor Red
        $failed++
    }
    
    Write-Host ""
}

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "📊 Summary:" -ForegroundColor Yellow
Write-Host "  ✅ Created: $created VMs" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "  ❌ Failed: $failed VMs" -ForegroundColor Red
}

Write-Host "`n📋 List of VMs:" -ForegroundColor Cyan
Get-VM | Select-Object Name, State, CPUUsage, @{N='Memory(GB)';E={[math]::Round($_.MemoryAssigned/1GB,2)}}, Uptime | Format-Table -AutoSize

Write-Host "`n💡 Next Steps:" -ForegroundColor Yellow
Write-Host "  • VMs are created but not started (no OS installed)" -ForegroundColor Gray
Write-Host "  • These appear as discovered servers in Azure Migrate" -ForegroundColor Gray
Write-Host "  • To start a VM: Start-VM -Name <VMName>" -ForegroundColor Gray
Write-Host "  • To view all VMs: Get-VM | Format-Table Name, State, CPUUsage, MemoryAssigned" -ForegroundColor Gray
Write-Host ""
