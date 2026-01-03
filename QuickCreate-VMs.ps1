# ============================================================
# Copy and paste this ENTIRE block into PowerShell on the VM
# ============================================================

Write-Host "`nCreating 6 Sample VMs for Azure Migrate..." -ForegroundColor Cyan

# Check for virtual switch
Write-Host "`nChecking for virtual switch..." -ForegroundColor Cyan
$switches = Get-VMSwitch
if ($switches) {
    $switchName = $switches[0].Name
    Write-Host "Using existing switch: $switchName ($($switches[0].SwitchType))" -ForegroundColor Green
} else {
    Write-Host "No switch found, creating External switch..." -ForegroundColor Yellow
    
    # Find physical (non-virtual) network adapters
    $netAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
    
    if ($netAdapters -and $netAdapters.Count -gt 0) {
        $netAdapter = $netAdapters[0]
        $switchName = "External-Switch"
        
        try {
            New-VMSwitch -Name $switchName -NetAdapterName $netAdapter.Name -AllowManagementOS $true -ErrorAction Stop | Out-Null
            Write-Host "Created switch: $switchName (External - Internet access)" -ForegroundColor Green
        } catch {
            Write-Host "Failed to create External switch, using Internal instead" -ForegroundColor Yellow
            $switchName = "Internal-Switch"
            New-VMSwitch -Name $switchName -SwitchType Internal | Out-Null
            Write-Host "Created switch: $switchName (Internal - No internet)" -ForegroundColor Yellow
        }
    } else {
        $switchName = "Internal-Switch"
        New-VMSwitch -Name $switchName -SwitchType Internal | Out-Null
        Write-Host "Created switch: $switchName (Internal - No internet)" -ForegroundColor Yellow
    }
}

# VM configurations
$vms = @(
    @{ Name = "WIN-SQL-01"; Memory = 4GB; CPU = 2; Disk = 60GB }
    @{ Name = "WIN-WEB-01"; Memory = 2GB; CPU = 2; Disk = 40GB }
    @{ Name = "WIN-APP-01"; Memory = 4GB; CPU = 2; Disk = 50GB }
    @{ Name = "LIN-WEB-01"; Memory = 2GB; CPU = 2; Disk = 40GB }
    @{ Name = "LIN-DB-01"; Memory = 4GB; CPU = 2; Disk = 60GB }
    @{ Name = "LIN-APP-01"; Memory = 2GB; CPU = 2; Disk = 40GB }
)

$vmHost = Get-VMHost
$created = 0

foreach ($vmConfig in $vms) {
    Write-Host "`nCreating $($vmConfig.Name)..." -ForegroundColor Yellow
    
    try {
        # Check if exists
        if (Get-VM -Name $vmConfig.Name -ErrorAction SilentlyContinue) {
            Write-Host "  Already exists, skipping" -ForegroundColor Gray
            continue
        }
        
        # Create VM (use splatting to avoid backtick issues)
        $vmParams = @{
            Name = $vmConfig.Name
            MemoryStartupBytes = $vmConfig.Memory
            Generation = 2
            NewVHDPath = "$($vmHost.VirtualHardDiskPath)\$($vmConfig.Name).vhdx"
            NewVHDSizeBytes = $vmConfig.Disk
            SwitchName = $switchName
        }
        New-VM @vmParams | Out-Null
        
        # Configure
        Set-VMProcessor -VMName $vmConfig.Name -Count $vmConfig.CPU
        Set-VMMemory -VMName $vmConfig.Name -DynamicMemoryEnabled $true -MinimumBytes 512MB
        
        Write-Host "  ✅ Created" -ForegroundColor Green
        $created++
    } catch {
        Write-Host "  ❌ Failed: $_" -ForegroundColor Red
    }
}

Write-Host "`n✅ Created $created VMs" -ForegroundColor Green
Write-Host "`nVMs:" -ForegroundColor Cyan
Get-VM | Format-Table Name, State, CPUUsage, MemoryAssigned -AutoSize
