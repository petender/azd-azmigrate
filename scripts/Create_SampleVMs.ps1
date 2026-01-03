
# ==============================================
# Create 3 Windows VMs - No Sysprep (Verbose)
# ==============================================
# Based on your original script: internal NAT network (192.168.100.0/24),
# Windows Server 2022 Evaluation VHD download, but Windows-only and
# first-boot automation via offline unattend.xml + SetupComplete.cmd.
# (Adds logging, timers, progress, and detailed output.)
$ErrorActionPreference = "Stop"
$VerbosePreference     = "Continue"

# ---------- Logging & timing ----------
$logPath = "C:\Temp\Create_SampleVMs_verbose.log"
Start-Transcript -Path $logPath -Append
function Write-Stage { param([int]$n,[int]$total,[string]$msg)
  Write-Host ("`n[{0}/{1}] {2}" -f $n,$total,$msg) -ForegroundColor Cyan
}
function Start-Timer { New-Object System.Diagnostics.Stopwatch }
function Show-Duration { param($sw,[string]$what)
  $sw.Stop(); Write-Host ("{0} completed in {1:mm\:ss} (mm:ss)" -f $what,$sw.Elapsed) -ForegroundColor Gray
}

Write-Host "=== Windows Sample VMs - Automated First Boot (Verbose) ===" -ForegroundColor Cyan
Write-Host ("Log: {0}" -f $logPath) -ForegroundColor Gray

# ---------- Config ----------
$BaseImagesRoot = "E:\VMs\BaseImages"
$VMsRoot        = "E:\VMs\VirtualMachines"
$SwitchName     = "Internal-NAT"
$NatName        = "HyperV-NAT"
$NatCIDR        = "192.168.100.0/24"
$NatGatewayIP   = "192.168.100.1"
$DnsServers     = @("8.8.8.8")   # change if you have lab DNS

# Microsoft Windows Server 2022 Evaluation (≈10 GB)
# (Same link/logic as your original script.)
$WindowsVhdUrl  = "https://go.microsoft.com/fwlink/p/?linkid=2195166&clcid=0x409&culture=en-us&country=us"
$WindowsBaseVhd = Join-Path $BaseImagesRoot "WinServer2022-Eval.vhd"

# 3 VMs (edit to taste)
$vmSpecs = @(
    @{ VMName="WIN-SQL-01"; ComputerName="WINSQL01"; AdminPassword="P@ssw0rd!123"; IPAddress="192.168.100.10"; PrefixLength=24; Gateway=$NatGatewayIP; DnsServers=$DnsServers; MemoryMB=4096; CPUCount=2 },
    @{ VMName="WIN-WEB-01"; ComputerName="WINWEB01"; AdminPassword="P@ssw0rd!123"; IPAddress="192.168.100.11"; PrefixLength=24; Gateway=$NatGatewayIP; DnsServers=$DnsServers; MemoryMB=2048; CPUCount=2 },
    @{ VMName="WIN-APP-01"; ComputerName="WINAPP01"; AdminPassword="P@ssw0rd!123"; IPAddress="192.168.100.12"; PrefixLength=24; Gateway=$NatGatewayIP; DnsServers=$DnsServers; MemoryMB=4096; CPUCount=2 }
)

# ---------- Ensure folders ----------
Write-Stage 1 6 "Preparing folders"
New-Item -ItemType Directory -Path $BaseImagesRoot -Force | Out-Null
New-Item -ItemType Directory -Path $VMsRoot        -Force | Out-Null
Write-Host ("Base images: {0}" -f $BaseImagesRoot) -ForegroundColor Gray
Write-Host ("VMs root   : {0}" -f $VMsRoot)        -ForegroundColor Gray

# ---------- Ensure Internal switch + NAT ----------
Write-Stage 2 6 "Ensuring Internal switch & NAT"
$existingSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if (-not $existingSwitch) {
    Write-Host ("Creating internal switch: {0}" -f $SwitchName) -ForegroundColor Yellow
    New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
} else {
    Write-Host ("Using existing switch: {0}" -f $SwitchName) -ForegroundColor Green
}

# vNIC for the internal switch becomes gateway
$netAdapter = Get-NetAdapter | Where-Object { $_.Name -like "*$SwitchName*" }
if ($netAdapter) {
    $hasIP = Get-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Where-Object { $_.IPAddress -eq $NatGatewayIP }
    if (-not $hasIP) {
        Write-Host ("Assigning host gateway {0}/24 on vNIC {1}" -f $NatGatewayIP,$netAdapter.Name) -ForegroundColor Yellow
        New-NetIPAddress -IPAddress $NatGatewayIP -PrefixLength 24 -InterfaceIndex $netAdapter.ifIndex | Out-Null
    } else {
        Write-Host ("Host gateway already set on {0}" -f $netAdapter.Name) -ForegroundColor Green
    }
} else {
    Write-Warning "Could not find vNIC for the internal switch. Listing adapters:"
    Get-NetAdapter | ft Name, Status
}

# NAT
$existingNat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
if (-not $existingNat) {
    Write-Host ("Creating NAT {0} for {1}" -f $NatName,$NatCIDR) -ForegroundColor Yellow
    New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $NatCIDR | Out-Null
} else {
    Write-Host ("Using existing NAT: {0}" -f $NatName) -ForegroundColor Green
}
Write-Host ("Network: {0} | Gateway: {1} | DNS: {2}" -f $NatCIDR,$NatGatewayIP,($DnsServers -join ', ')) -ForegroundColor Gray
# (Matches your original internal NAT design) 〔Create_SampleVMs.txt〕 [1](https://microsoft-my.sharepoint.com/personal/petender_microsoft_com/Documents/Microsoft%20Copilot%20Chat%20Files/Create_SampleVMs.txt)

# ---------- Download/locate base VHD ----------
Write-Stage 3 6 "Downloading / locating Windows Server 2022 base VHD (~10 GB)"
if (Test-Path $WindowsBaseVhd) {
    $sizeGB = [math]::Round((Get-Item $WindowsBaseVhd).Length / 1GB, 2)
    Write-Host ("Base VHD already present: {0} ({1} GB)" -f $WindowsBaseVhd,$sizeGB) -ForegroundColor Green
} else {
    Write-Host ("Downloading from: {0}" -f $WindowsVhdUrl) -ForegroundColor Yellow
    $tempFile = Join-Path $BaseImagesRoot "WinServer2022-Download.tmp"
    $dl = Start-Timer; $dl.Start()

    try {
        Import-Module BitsTransfer -ErrorAction Stop
        Start-BitsTransfer -Source $WindowsVhdUrl -Destination $tempFile -Description "WS2022 Eval VHD"
    } catch {
        Write-Warning "BITS failed; switching to Invoke-WebRequest"
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $WindowsVhdUrl -OutFile $tempFile -UseBasicParsing -TimeoutSec 7200
        $ProgressPreference = 'Continue'
    }
    Show-Duration $dl "Download"

    if (-not (Test-Path $tempFile)) { throw "Download failed: $tempFile not found." }

    $header = Get-Content $tempFile -Encoding Byte -TotalCount 2
    $isZip  = ($header[0] -eq 0x50 -and $header[1] -eq 0x4B) # 'PK'
    if ($isZip) {
        Write-Host "Payload is ZIP → extracting..." -ForegroundColor Yellow
        $tempZip = Join-Path $BaseImagesRoot "WinServer2022.zip"
        Move-Item $tempFile $tempZip -Force
        Expand-Archive -Path $tempZip -DestinationPath (Join-Path $BaseImagesRoot "Temp") -Force
        $vhdInZip = Get-ChildItem -Path (Join-Path $BaseImagesRoot "Temp") -Filter "*.vhd*" -Recurse | Select-Object -First 1
        if (-not $vhdInZip) { throw "No VHD found in archive." }
        Move-Item -Path $vhdInZip.FullName -Destination $WindowsBaseVhd -Force
        Remove-Item $tempZip -Force
        Remove-Item (Join-Path $BaseImagesRoot "Temp") -Recurse -Force
    } else {
        Write-Host "Payload is VHD → moving to final location..." -ForegroundColor Yellow
        Move-Item $tempFile $WindowsBaseVhd -Force
    }
    $sizeGB = [math]::Round((Get-Item $WindowsBaseVhd).Length / 1GB, 2)
    Write-Host ("Base VHD saved: {0} ({1} GB)" -f $WindowsBaseVhd,$sizeGB) -ForegroundColor Green
}
# (Keeps your original MSFT eval workflow.) 〔Create_SampleVMs.txt〕 [1](https://microsoft-my.sharepoint.com/personal/petender_microsoft_com/Documents/Microsoft%20Copilot%20Chat%20Files/Create_SampleVMs.txt)

# ---------- Templates ----------
$UnattendXmlTemplate = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage><UILanguage>en-US</UILanguage></SetupUILanguage>
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <UserData>
        <AcceptEula>true</AcceptEula>
      </UserData>
    </component>
  </settings>
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ComputerName>{{ComputerName}}</ComputerName>
      <TimeZone>Pacific Standard Time</TimeZone>
      <RegisteredOrganization>Lab</RegisteredOrganization>
      <RegisteredOwner>Admin</RegisteredOwner>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <NetworkLocation>Work</NetworkLocation>
        <ProtectYourPC>3</ProtectYourPC>
        <SkipUserOOBE>true</SkipUserOOBE>
        <SkipMachineOOBE>true</SkipMachineOOBE>
      </OOBE>
      <UserAccounts>
        <AdministratorPassword>
          <Value>{{AdminPassword}}</Value>
          <PlainText>true</PlainText>
        </AdministratorPassword>
      </UserAccounts>
      <AutoLogon>
        <Username>Administrator</Username>
        <Password>
          <Value>{{AdminPassword}}</Value>
          <PlainText>true</PlainText>
        </Password>
        <Enabled>true</Enabled>
        <LogonCount>1</LogonCount>
      </AutoLogon>
    </component>
  </settings>
</unattend>
"@

$SetupCompleteCmdTemplate = @"
@echo off
REM SetupComplete.cmd - Runs automatically after Windows setup completes
echo Configuring network settings...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { \$nic = (Get-NetAdapter | Where-Object { \$_.Status -eq 'Up' } | Select-Object -First 1).InterfaceAlias; if (-not \$nic) { \$nic = 'Ethernet' }; Remove-NetIPAddress -InterfaceAlias \$nic -Confirm:\$false -ErrorAction SilentlyContinue; Remove-NetRoute -InterfaceAlias \$nic -Confirm:\$false -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2; New-NetIPAddress -InterfaceAlias \$nic -IPAddress '{{IPAddress}}' -PrefixLength {{PrefixLength}} -DefaultGateway '{{Gateway}}'; Set-DnsClientServerAddress -InterfaceAlias \$nic -ServerAddresses {{DnsArray}}; Get-NetIPAddress | Out-File C:\Windows\Temp\network-config.log }"
echo Network configuration complete.
exit /b 0
"@

# ---------- Helper functions ----------
function New-DiffVHD {
    param([string]$ChildPath,[string]$ParentPath)
    if (Test-Path $ChildPath) { Remove-Item $ChildPath -Force }
    New-VHD -Path $ChildPath -ParentPath $ParentPath -Differencing | Out-Null
}
function Mount-VhdAndGetDriveLetter {
    param([string]$VhdPath)
    Mount-VHD -Path $VhdPath -PassThru | Out-Null
    $disk = Get-Disk | Where-Object { $_.FriendlyName -like "*Virtual Disk*" -and $_.OperationalStatus -eq 'Online' } |
            Sort-Object Number | Select-Object -Last 1
    if (-not $disk) { throw "Mounted VHD disk not found." }
    $part = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.DriveLetter } | Select-Object -First 1
    if (-not $part) { throw "Partition with drive letter not found on mounted VHD." }
    return ($part.DriveLetter + ":")
}

# ---------- Create, inject, boot ----------
Write-Stage 4 6 "Creating Windows VMs (differencing disks) & injecting answer files"
$created = 0
$vmIndex = 0
foreach ($spec in $vmSpecs) {
    $vmIndex++
    $activityId = 200 + $vmIndex
    $vmFolder   = Join-Path $VMsRoot $spec.VMName
    New-Item -ItemType Directory -Path $vmFolder -Force | Out-Null

    # Child must match parent container: eval often ships .vhd (Gen-1)
    $childVhd = Join-Path $vmFolder "$($spec.VMName).vhd"
    Write-Progress -Id $activityId -Activity "Preparing $($spec.VMName)" -Status "Creating differencing disk" -PercentComplete 10
    $swCreate = Start-Timer; $swCreate.Start()
    New-DiffVHD -ChildPath $childVhd -ParentPath $WindowsBaseVhd
    Show-Duration $swCreate "Differencing disk"

    Write-Progress -Id $activityId -Activity "Preparing $($spec.VMName)" -Status "Mounting child disk" -PercentComplete 30
    $swMount = Start-Timer; $swMount.Start()
    $drive = Mount-VhdAndGetDriveLetter -VhdPath $childVhd
    Show-Duration $swMount "Mount"

    Write-Progress -Id $activityId -Activity "Preparing $($spec.VMName)" -Status "Injecting unattend.xml" -PercentComplete 50
    $panther      = Join-Path $drive "Windows\Panther"
    $setupScripts = Join-Path $drive "Windows\Setup\Scripts"
    New-Item -ItemType Directory -Force -Path $panther      | Out-Null
    New-Item -ItemType Directory -Force -Path $setupScripts | Out-Null

    # Generate unattend.xml with only ComputerName and AdminPassword
    $unattend = $UnattendXmlTemplate.Replace("{{ComputerName}}", $spec.ComputerName).
                                     Replace("{{AdminPassword}}", $spec.AdminPassword)
    Set-Content -Path (Join-Path $panther "unattend.xml") -Value $unattend -Encoding UTF8
    # Optional copy to Sysprep folder as well
    Copy-Item (Join-Path $panther "unattend.xml") (Join-Path $drive "Windows\System32\Sysprep\unattend.xml") -Force

    Write-Progress -Id $activityId -Activity "Preparing $($spec.VMName)" -Status "Injecting SetupComplete.cmd" -PercentComplete 65
    # Generate SetupComplete.cmd with network configuration
    $dnsArrayStr = ($spec.DnsServers | ForEach-Object { "'$_'" }) -join ','
    $setupCmd = $SetupCompleteCmdTemplate.Replace("{{IPAddress}}",    $spec.IPAddress).
                                          Replace("{{PrefixLength}}", $spec.PrefixLength.ToString()).
                                          Replace("{{Gateway}}",      $spec.Gateway).
                                          Replace("{{DnsArray}}",     $dnsArrayStr)
    Set-Content -Path (Join-Path $setupScripts "SetupComplete.cmd") -Value $setupCmd -Encoding ASCII

    Write-Progress -Id $activityId -Activity "Preparing $($spec.VMName)" -Status "Dismounting child disk" -PercentComplete 75
    $swDismount = Start-Timer; $swDismount.Start()
    Dismount-VHD -Path $childVhd
    Show-Duration $swDismount "Dismount"

    Write-Progress -Id $activityId -Activity "Preparing $($spec.VMName)" -Status "Creating & starting VM" -PercentComplete 90
    Write-Host ("Creating VM: {0} | Memory: {1} MB | CPUs: {2} | Switch: {3}" -f $spec.VMName,$spec.MemoryMB,$spec.CPUCount,$SwitchName) -ForegroundColor Yellow
    New-VM -Name $spec.VMName -MemoryStartupBytes ($spec.MemoryMB * 1MB) -Generation 1 -VHDPath $childVhd -SwitchName $SwitchName | Out-Null
    Set-VM -Name $spec.VMName -ProcessorCount $spec.CPUCount
    Start-VM -Name $spec.VMName | Out-Null

    Write-Progress -Id $activityId -Activity "Preparing $($spec.VMName)" -Completed
    Write-Host ("Started {0} (expected IP: {1})" -f $spec.VMName,$spec.IPAddress) -ForegroundColor Green
    $created++
}

# ---------- Optional: light wait to let OOBE run ----------
Write-Stage 5 6 "Brief wait for first-boot specialization (OOBE + SetupComplete)"
Start-Sleep -Seconds 10
Get-VM | Where-Object { $_.Name -like "WIN-*" } | Sort-Object Name |
  Select-Object Name, State, Status, ProcessorCount, @{n="MemoryMB";e={ $_.MemoryStartup / 1MB }} |
  Format-Table -AutoSize

# ---------- Summary ----------
Write-Stage 6 6 "Summary"
Write-Host ("Created: {0}" -f $created) -ForegroundColor Green
Write-Host ("Switch : {0}" -f $SwitchName) -ForegroundColor Gray
Write-Host ("NAT    : {0} (gateway {1})" -f $NatCIDR,$NatGatewayIP) -ForegroundColor Gray
Write-Host ("Base VHD: {0}" -f $WindowsBaseVhd) -ForegroundColor Gray

$allVMs = Get-VM | Where-Object { $_.Name -like "WIN-*" } | Sort-Object Name
foreach ($vm in $allVMs) {
    $spec = $vmSpecs | Where-Object { $_.VMName -eq $vm.Name }
    Write-Host (" {0} - {1} - {2}MB - CPUs:{3} - IP:{4}" -f $vm.Name,$vm.State,$spec.MemoryMB,$spec.CPUCount,$spec.IPAddress) -ForegroundColor Gray
}

Stop-Transcript
