# -------------------------------------------------------------------------------------------------
#  <copyright file="AzureMigrateInstaller.ps1" company="Microsoft">
#      Copyright (c) Microsoft Corporation. All rights reserved.
#  </copyright>
#
#  Description: This script prepares the host machine for various Azure Migrate Scenarios.

#  Version: 10.3.0.0

#  Requirements:
#       Refer Readme.html for machine requirements
#       Following files should be placed in the same folder as this script before execution:
#            Scripts : WebBinding.ps1 and SetRegistryForTrustedSites.ps1
#            MSIs    : Microsoft Azure Hyper-V\Server\VMware Assessment Service.msi
#                      Microsoft Azure Hyper-V\Server\VMware Discovery Service.msi
#                      Microsoft Azure SQL Discovery and Assessment Service.msi
#                      MicrosoftAzureApplianceConfigurationManager.msi
#                      Microsoft Azure Web App Discovery and Assessment Service.msi
#                      MicrosoftAzureAutoUpdate.msi
#                      MicrosoftAzureDraService.msi     (VMware Migration only)
#                      MicrosoftAzureGatewayService.exe (VMware Migration only)
#                      AzureConnectedMachineAgent.msi
#                      Dra.Setup.Windows.msi (ASRv2 DRA)
#            Config  : Scenario.json
#                      {
#                           "Scenario"        : "HyperV|Physical|VMware",
#                           "Cloud"           : "Public|USGov",
#                           "ScaleOut"        : "True|False",
#                           "PrivateEndpoint" : "True|False"
#                      }
# -------------------------------------------------------------------------------------------------

#Requires -RunAsAdministrator

[CmdletBinding(DefaultParameterSetName="NewInstall")]
param(
    [Parameter(Mandatory = $false, ParameterSetName = "NewInstall")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('HyperV','Physical','VMware','AzureStackHCI','AzureLocalTarget')]
    [string]
    $Scenario,

    [Parameter(Mandatory = $false, ParameterSetName = "NewInstall")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('Public','USGov')]
    [string]
    $Cloud,

    [Parameter(Mandatory = $false, ParameterSetName = "NewInstall")]
    [Parameter(Mandatory = $false, ParameterSetName = "Upgrade")]
    [switch]
    $SkipSettingTrustedHost,

    [Parameter(Mandatory = $false, ParameterSetName = "Upgrade")]
    [switch]
    $UpgradeAgents,

    [Parameter(Mandatory = $false, ParameterSetName = "NewInstall")]
    [switch]
    $ScaleOut,

    [Parameter(Mandatory = $false, ParameterSetName = "NewInstall")]
    [switch]
    $PrivateEndpoint,

    [Parameter(Mandatory = $false, ParameterSetName = "NewInstall")]
    [switch]
    $EnableAzureStackHCITarget,

    [Parameter(Mandatory = $false, ParameterSetName = "NewInstall")]
    [switch]
    $EnableAzureLocalTarget,

    [Parameter(Mandatory = $false, ParameterSetName = "Uninstall")]
    [switch]
    $RemoveAzMigrate,

    [Parameter(Mandatory = $false, ParameterSetName = "NewInstall")]
    [switch]
    $Repurpose,

    [Parameter(Mandatory = $false, ParameterSetName = "NewInstall")]
    [Parameter(Mandatory = $false, ParameterSetName = "Upgrade")]
    [switch]
    $DisableAutoUpdate
)

#region - These routines writes the output string to the console and also to the log file.
function Log-Info([string] $OutputText)
{
    Write-Host $OutputText -ForegroundColor White
    $OutputText = [string][DateTime]::Now + " " + $OutputText
    $OutputText | %{ Out-File -filepath $InstallerLog -inputobject $_ -append -encoding "ASCII" }
}

function Log-InfoHighLight([string] $OutputText)
{
    Write-Host $OutputText -ForegroundColor Cyan
    $OutputText = [string][DateTime]::Now + " " + $OutputText
    $OutputText | %{ Out-File -filepath $InstallerLog -inputobject $_ -append -encoding "ASCII" }
}

function Log-Input([string] $OutputText)
{
    Write-Host $OutputText -ForegroundColor White -BackgroundColor DarkGray -NoNewline
    $OutputText = [string][DateTime]::Now + " " + $OutputText
    $OutputText | %{ Out-File -filepath $InstallerLog -inputobject $_ -append -encoding "ASCII" }
    Write-Host " " -NoNewline
}

function Log-Success([string] $OutputText)
{
    Write-Host $OutputText -ForegroundColor Green
    $OutputText = [string][DateTime]::Now + " " + $OutputText
    $OutputText | %{ Out-File -filepath $InstallerLog -inputobject $_ -append -encoding "ASCII" }
}

function Log-Warning([string] $OutputText)
{
    Write-Host $OutputText -ForegroundColor Yellow
    $OutputText = [string][DateTime]::Now + " " + $OutputText
    $OutputText | %{ Out-File -filepath $InstallerLog -inputobject $_ -append -encoding "ASCII"  }
}

function Log-Error([string] $OutputText)
{
    Write-Host $OutputText -ForegroundColor Red
    $OutputText = [string][DateTime]::Now + " " + $OutputText
    $OutputText | %{ Out-File -filepath $InstallerLog -inputobject $_ -append -encoding "ASCII" }
}
#endregion

#region - Global Initialization
$global:DefaultStringVal  = "Unknown"
$global:WarningCount      = 0
$global:ReuseScenario     = 0
$global:SelectedFabricType= $global:DefaultStringVal
$global:SelectedCloud     = $global:DefaultStringVal
$global:SelectedScaleOut  = "False"
$global:SelectedPEEnabled = "False"
$global:SelectedEnableAzureStackHCITarget = "False"
$global:ParameterList     = $PSBoundParameters
$global:AzureLocalTarget     = "AzureLocalTarget"

$machineHostName          = (Get-WmiObject win32_computersystem).DNSHostName
$DefaultURL               = "https://" + $machineHostName + ":44368"
$TimeStamp                = [DateTime]::Now.ToString("yyyy-MM-dd-HH-mm-ss")
$BackupDir                = "$env:ProgramData`\Microsoft Azure"
$BackupDestination        = "$env:windir`\Temp\MicrosoftAzure"
$LogFileDir               = "$env:ProgramData`\Microsoft Azure\Logs"
$ConfigFileDir            = "$env:ProgramData`\Microsoft Azure\Config"
# TODO: Move reading this path from registry if it exists
$CredFileDir              = "$env:ProgramData`\Microsoft Azure\CredStore"
$ApplianceVersionFilePath = "$Env:SystemDrive`\Users\Public\Desktop\ApplianceVersion.txt"

$HyperVAssessmentServiceMSI    = "Microsoft Azure Hyper-V Assessment Service.msi"
$HyperVDiscoveryServiceMSI     = "Microsoft Azure Hyper-V Discovery Service.msi"
$ServerAssessmentServiceMSI    = "Microsoft Azure Server Assessment Service.msi"
$ServerDiscoveryServiceMSI     = "Microsoft Azure Server Discovery Service.msi"
$VMWareAssessmentServiceMSI    = "Microsoft Azure VMware Assessment Service.msi"
$VMWareDiscoveryServiceMSI     = "Microsoft Azure VMware Discovery Service.msi"
$SQLServiceMSI                 = "Microsoft Azure SQL Discovery and Assessment Service.msi"
$WebAppMSI                     = "Microsoft Azure Web App Discovery and Assessment Service.msi"
$AppCompatMSI                  = "Microsoft Azure Application Compatibility Assessment Service.msi"
$AzureConnectedMachineAgentMSI = "AzureConnectedMachineAgent.msi"

$AssessmentServiceMSILog = "$LogFileDir\AssessmentInstaller_$TimeStamp.log"
$DiscoveryServiceMSILog  = "$LogFileDir\DiscoveryInstaller_$TimeStamp.log"
$SQLServiceMSILog        = "$LogFileDir\SQLInstaller_$TimeStamp.log"
$WebAppMSILog            = "$LogFileDir\WebAppInstaller_$TimeStamp.log"
$AppCompatMSILog         = "$LogFileDir\AppCompatInstaller_$TimeStamp.log"
$AzureConnectedMachineAgentMSILog = "$LogFileDir\AzureConnectedMachineAgent_$TimeStamp.log"

$GatewayExeName          = "MicrosoftAzureGatewayService.exe"

# Old SRS DRA
$DraMsiName              = "MicrosoftAzureDRAService.msi"
$DraMsiLog               = "$LogFileDir\DRAInstaller_$TimeStamp.log"

# New ASRv2 DRA
$DraV2MsiName              = "Dra.Setup.Windows.msi"
$DraV2MsiLog               = "$LogFileDir\DRAV2Installer_$TimeStamp.log"

$ConfigManagerMSI        = "MicrosoftAzureApplianceConfigurationManager.msi"
$ConfigManagerMSILog     = "$LogFileDir\ConfigurationManagerInstaller_$TimeStamp.log"
$ApplianceJsonFilePath   = "$ConfigFileDir\appliance.json"
$ApplianceJsonFileData   = @{
    "Cloud"="$global:SelectedCloud";
    "ComponentVersion"="26.0.0.1";
    "FabricType"="$global:SelectedFabricType";
    "ScaleOut"=$global:SelectedScaleOut;
    "PrivateEndpointEnabled"=$global:SelectedPEEnabled;
    "VddkInstallerFolder"="";
    "IsApplianceRegistered"="false";
    "DiscoveryInitiated"="false";
    "EnableProxyBypassList"="true";
    "ProviderId"="8416fccd-8af8-466e-8021-79db15038c87";
    "EnableAzureStackHCITarget"=$global:SelectedEnableAzureStackHCITarget;
}

$AutoUpdaterMSI          = "MicrosoftAzureAutoUpdate.msi"
$AutoUpdaterMSILog       = "$LogFileDir\AutoUpdateInstaller_$TimeStamp.log"
$AutoUpdaterJsonFilePath = "$ConfigFileDir\AutoUpdater.json"
$AutoUpdaterJsonFileData = @{
    "Cloud"="$global:SelectedCloud";
    "ComponentVersion"="26.0.0.0";
    "AutoUpdateEnabled"="True";
    "ProviderId"="8416fccd-8af8-466e-8021-79db15038c87";
    "AutoUpdaterDownloadLink"="https://aka.ms/latestapplianceservices"
}

$RegAzureAppliancePath = "HKLM:\SOFTWARE\Microsoft\Azure Appliance"
$RegAzureCredStorePath = "HKLM:\Software\Microsoft\AzureAppliance"
#endregion

## Creating the logfile
New-Item -ItemType Directory -Force -Path $LogFileDir | Out-Null
$InstallerLog = "$LogFileDir\AzureMigrateScenarioInstaller_$TimeStamp.log"
Log-InfoHighLight "Log file created `"$InstallerLog`" for troubleshooting purpose.`n"

#region - Cleanup
<#
.SYNOPSIS
Create JsonFile
Usage:
    DetectAndCleanupPreviousInstallation
#>
function DetectAndCleanupPreviousInstallation
{
    [int]$maxRetryLimit = 3
    [int]$retryCount    = 0

    if ($global:ReuseScenario -eq 1)
    {
        $ZipFilePath = "$BackupDestination`\Backup_$TimeStamp.zip"
        Log-Info "Zip and backup the configuration to the path: $ZipFilePath"
        [void](New-Item -ItemType "Directory" -Path $BackupDestination -Force)

        ## Compress file.
        [void][Reflection.Assembly]::LoadWithPartialName( "System.IO.Compression.FileSystem" )
        [void]([System.IO.Compression.ZipFile]::CreateFromDirectory($BackupDir, $ZipFilePath) | Out-File -FilePath $InstallerLog -NoClobber -Append)
        Log-Success "[OK]`n"
    }

    Log-InfoHighLight "Removing any previously installed agents in the next 5 seconds..."
    Start-Sleep -Seconds 5
    Log-Info "This cleanup process can take up to 2-3 minutes.`n"

    UnInstallProgram("Microsoft Azure Server Assessment Service")
    UnInstallProgram("Microsoft Azure Server Discovery Service")
    UnInstallProgram("Microsoft Azure Hyper-V Assessment Service")
    UnInstallProgram("Microsoft Azure Hyper-V Discovery Service")
    UnInstallProgram("Microsoft Azure VMware Assessment Service")
    UnInstallProgram("Microsoft Azure VMware Discovery Service")
    UnInstallProgram("Microsoft Azure Appliance Auto Update")
    UnInstallProgram("Microsoft Azure Appliance Configuration Manager")
    UnInstallProgram("Microsoft Azure Dra Service")
    UnInstallProgram("Microsoft Azure Gateway Service")
    UnInstallProgram("Microsoft Azure SQL Discovery and Assessment Service")
    UnInstallProgram("Microsoft Azure Web App Discovery and Assessment Service")

    try
    {
        $found = Get-ChildItem -Path $env:ProgramW6432 -Recurse -Filter "azcmagent.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found)
        {
            $arcAgentPath = $found.FullName
            Log-Info "Deboarding machine from Azure Arc..."
            $process = Start-Process -FilePath $arcAgentPath -ArgumentList "disconnect --force-local-only" -Wait -Passthru -NoNewWindow
            if ($process.ExitCode -eq 0)
            {
                Log-Success "[OK]`n"
            }
            else
            {
                Log-Warning "Failed to deboard machine from Azure Arc. Exit code: $($process.ExitCode). Continuing..."
            }
        }
    }
    catch
    {
        Log-Warning "Failed to deboard machine from Azure Arc. Exception: $_.Exception."
        Log-Warning "Manually deboard the machine from Azure Arc to re-use the machine as an Azure Migrate Appliance. Continuing..."
    }

    UnInstallProgram("Azure Connected Machine Agent")
    #UnInstallProgram("Microsoft Azure Application Compatibility Assessment Service")

    # Uninstall new ASRv2 DRA
    UnInstallProgram("Azure Site Recovery Management Service")

    #Restart IIS
    "iisreset.exe /restart" | Out-Null

    CleanupPerformanceCounter

    if ($UpgradeAgents -eq $false)
    {
        while($maxRetryLimit -gt $retryCount)
        {
            $Error.Clear()
            Log-info "Cleaning up previous configuration files and settings..."

            if([System.IO.File]::Exists($ApplianceVersionFilePath))
            {
                Remove-Item -path $ApplianceVersionFilePath -Force
            }

            if([System.IO.File]::Exists($AutoUpdaterJsonFilePath))
            {
                Remove-Item –path $AutoUpdaterJsonFilePath -Force
            }

            if (Test-Path $RegAzureCredStorePath)
            {
                Remove-Item -Path $RegAzureCredStorePath -Force -Recurse
            }

            if (Test-Path $ApplianceJsonFilePath)
            {
                Remove-Item –Path $ApplianceJsonFilePath -Force
            }

            if (Test-Path $ConfigFileDir -PathType Any)
            {
                Remove-Item -Path $ConfigFileDir -Force -Recurse
            }

            if (Test-Path $CredFileDir -PathType Container)
            {
                Remove-Item $CredFileDir -Force -Recurse
            }

            if (Test-Path $LogFileDir -PathType Container)
            {
                # Remove all folders under Log folder.
                Get-ChildItem -Recurse $LogFileDir | Where { $_.PSIsContainer } | Remove-Item -Recurse -Force
            }

            if(Test-Path $RegAzureAppliancePath)
            {
                Remove-Item $RegAzureAppliancePath -Force -Recurse
            }

            if ($Error.Count -eq 0)
            {
                break
            }
            else
            {
                $retryCount++
                Log-InfoHighLight $Error
                Log-Warning "Retry attempt #$retryCount of #$maxRetryLimit : Make sure that none of the files at the folder location '$BackupDir' are currently open.`n"
                Start-Sleep -Seconds 10
            }
        }
    }

    if ($Error.Count -eq 0)
    {
        Log-Success "[OK]`n"
    }
    else
    {
        Log-Error $Error
        Log-Error "Cleanup attempt failed. Aborting..."
        Log-Warning "To resolve the issue, try running the script again. If the issue persists, contact Microsoft Support."
        exit -2
    }

    if ($RemoveAzMigrate -eq $true)
    {
        Log-Success "Cleanup completed successfully. Exiting..."
        exit 0
    }
}

<#
.SYNOPSIS
Cleans up Performance monitor data collector set
Usage:
    CleanupPerformanceCounter
#>

function CleanupPerformanceCounter
{
    param(
        [string]$CollectorSetName = "AzureAppliancePerfMonitor"
    )

    try{
        $collectorset = New-Object -COM Pla.DataCollectorSet
        $collectorset.Query($CollectorSetName, $null)

        if ($collectorset.name -eq $CollectorSetName) {
            if ($collectorset.Status -eq 1)
            {
               $collectorset.Stop($false);
            }

            $null = $collectorset.Delete()
        }

        $PerfFileDir = "$env:windir`\Temp\MicrosoftAzure\" + $CollectorSetName
        if (Test-Path $PerfFileDir -PathType Container)
        {
           # Remove all folders under perf data folder.
           Get-ChildItem -Recurse $PerfFileDir | Where { $_.PSIsContainer } | Remove-Item -Recurse -Force
        }

    }
    catch [Exception]
    {
        $OutputText = [string][DateTime]::Now + " " + "Unable to delete performance counter successfully. $_.Exception Please manually delete $CollectorSetName from PerfMon under User Defined collector sets. Continuing..."
        $OutputText | %{ Out-File -filepath $InstallerLog -inputobject $_ -append -encoding "ASCII"  }
    }

    $Error.Clear()
}

<#
.SYNOPSIS
Install MSI
Usage:
    UnInstallProgram -ProgramCaption $ProgramCaption
#>

function UnInstallProgram
{
    param(
        [string] $ProgramCaption
        )
    $tryUsingWmiObject = $true
    if (Get-Module -ListAvailable -Name PackageManagement)
    {
        $tryUsingWmiObject = $false # we don't need to try using wmi if package management is present
        # The module gets imported automatically when Get-Package is called. Adding this to ensure it is loaded
        Import-Module PackageManagement
        $app = Get-Package -Name $ProgramCaption -ErrorAction SilentlyContinue
        if ($app)
        {
            Log-Info "$ProgramCaption found installed. Proceeding with uninstallation using package management."
            Start-Sleep -Seconds 2
            try {
                [void]($app | Uninstall-Package -Force -ErrorAction Stop -WarningAction SilentlyContinue)
                Log-Success "[Uninstall Successful]`n"
            }
            catch {
                $tryUsingWmiObject = $true # uninstall using package management failed, so we will try using wmi
                $global:WarningCount++
                Log-Warning "Warning #$global:WarningCount : Uninstall failed using package management. retrying using Get-WmiObject..."
            }
        }
    }

    if ($tryUsingWmiObject)
    {
        $app = Get-WmiObject -Class Win32_Product -Filter "Caption = '$ProgramCaption' "
        if ($app)
        {
            Log-Info "$ProgramCaption found installed using Get-WmiObject. Proceeding with uninstallation."
            Start-Sleep -Seconds 2
            $result = $app.Uninstall()
            if ($result.ReturnValue -eq 0 -or $result.ReturnValue -eq 3010)
            {
                Log-Success "[Uninstall Successful]`n"
            }
            else
            {
                $global:WarningCount++
                Log-Warning "Warning #$global:WarningCount : Uninstall failed. Use the Control Panel to manually uninstall $ProgramCaption. Continuing..."
            }
        }
    }

    $Error.Clear()
}
#endregion

<#
.SYNOPSIS
Install MSI
Usage:
    InstallMSI -MSIFilePath $MSIFilePath -MSIInstallLogName $MSIInstallLogName
#>

function InstallMSI
{
    param(
        [string] $MSIFilePath,
        [string] $MSIInstallLogName,
        [switch] $OptionalComponent
        )

    [int]$maxRetryLimit = 5
    [int]$retryCount    = 0

    Log-Info "Installing $MSIFilePath..."

    if (-Not (Test-Path -Path $MSIFilePath -PathType Any))
    {
        if ($OptionalComponent.IsPresent)
        {
            Log-InfoHighLight "Optional Component MSI not found: $MSIFilePath. Continuing..."
            Log-Warning "[Skipping]`n"
            return
        }

        Log-Error "MSI not found: $MSIFilePath. Aborting..."
        Log-Warning "Download the installation script, extract the contents, and rerun the PowerShell script."
        exit -3
    }

     while($maxRetryLimit -gt $retryCount)
     {
        $Error.Clear()
        $process = (Start-Process -Wait -Passthru -FilePath msiexec -ArgumentList `
            "/i `"$MSIFilePath`" /quiet /lv `"$MSIInstallLogName`"")

        $returnCode = $process.ExitCode;

        if ($returnCode -eq 0 -or $returnCode -eq 3010)
        {
            Log-Success "[OK]`n"
            return
        }
        else
        {
            $retryCount++
            Log-InfoHighLight "$MSIFilePath installation failed with $returnCode."
            Log-Warning "Retry attempt #$retryCount of #$maxRetryLimit.`n"
            Start-Sleep -Seconds 10
        }
    }

    Log-Error "$MSIFilePath installation failed. More logs available at $MSIInstallLogName. Aborting..."
    Log-Warning "Try Re-running the script. If required please share the installation log file $MSIInstallLogName while contacting Microsoft Support."
    exit -3
}

<#
.SYNOPSIS
Create JsonFile
Usage:
    CreateJsonFile -JsonFileData $JsonFileData -JsonFilePath $JsonFilePath
#>
function CreateJsonFile
{
    param(
        $JsonFileData,
        [string] $JsonFilePath
        )

    if ($UpgradeAgents -and (test-path -path $JsonFilePath))
    {
        Log-Info "Skip creating config file:  $JsonFilePath..."
        return;
    }

    Log-Info "Creating config file: $JsonFilePath..."

    New-Item -Path $ConfigFileDir -type directory -Force | Out-Null
    $JsonFileData | ConvertTo-Json | Add-Content -Path $JsonFilePath -Encoding UTF8

    if ($?)
    {
        Log-Success "[OK]`n"
    }
    else
    {
        Log-Error "Failure in creating $JsonFilePath. Aborting..."
        Log-Warning "Take steps to resolve the issue. If the issue persists, contact Microsoft Support."
        Log-Error $_
        exit -4
    }
}

<#
.SYNOPSIS
Enables IIS modules.
Usage:
    EnableIIS
#>

function EnableIIS
{
    Log-Info "Enabling IIS Role and other dependent features..."

    $OS = Get-WmiObject Win32_OperatingSystem

    if ($OS.Caption.contains("Server 2022") -eq $true)
    {
       Install-WindowsFeature WAS, WAS-Process-Model, WAS-Config-APIs, Web-Server, `
        Web-WebServer, Web-Mgmt-Service, Web-Request-Monitor, Web-Common-Http, Web-Static-Content, `
        Web-Default-Doc, Web-Dir-Browsing, Web-Http-Errors, Web-App-Dev, Web-CGI, Web-Health, `
        Web-Http-Logging, Web-Log-Libraries, Web-Security, Web-Filtering, Web-Performance, `
        Web-Stat-Compression, Web-Mgmt-Tools, Web-Mgmt-Console, Web-Scripting-Tools, `
        Web-Asp-Net45, Web-Net-Ext45, Web-Http-Redirect, Web-Windows-Auth, Web-Url-Auth
    }
    elseif ($OS.Caption.contains("Server") -eq $true)
    {
       Install-WindowsFeature WAS, WAS-Process-Model, WAS-Config-APIs, Web-Server, `
        Web-WebServer, Web-Mgmt-Service, Web-Request-Monitor, Web-Common-Http, Web-Static-Content, `
        Web-Default-Doc, Web-Dir-Browsing, Web-Http-Errors, Web-App-Dev, Web-CGI, Web-Health, `
        Web-Http-Logging, Web-Log-Libraries, Web-Security, Web-Filtering, Web-Performance, `
        Web-Stat-Compression, Web-Mgmt-Tools, Web-Mgmt-Console, Web-Scripting-Tools, `
        Web-Asp-Net45, Web-Net-Ext45, Web-Http-Redirect, Web-Windows-Auth, Web-Url-Auth
    }
    else
    {
       Log-InfoHighLight "Windows client SKU is not supported for Azure Migrate Appliance Operating System. To be used for testing purpose only..."
       Enable-WindowsOptionalFeature -Online -FeatureName NetFx4Extended-ASPNET45, IIS-WebServerRole, `
        IIS-WebServer, IIS-CommonHttpFeatures,IIS-HttpErrors,IIS-HttpRedirect,IIS-ApplicationDevelopment, `
        IIS-NetFxExtensibility, IIS-NetFxExtensibility45, IIS-HealthAndDiagnostics, IIS-HttpLogging, `
        IIS-LoggingLibraries, IIS-RequestMonitor, IIS-HttpTracing, IIS-Security, IIS-URLAuthorization, `
        IIS-RequestFiltering, IIS-IPSecurity, IIS-Performance, IIS-HttpCompressionDynamic, `
        IIS-WebServerManagementTools, IIS-ManagementScriptingTools, IIS-IIS6ManagementCompatibility, `
        IIS-Metabase, WAS-WindowsActivationService, WAS-ProcessModel, WAS-NetFxEnvironment, WAS-ConfigurationAPI, `
        IIS-HostableWebCore, IIS-StaticContent, IIS-DefaultDocument, IIS-DirectoryBrowsing, IIS-WebDAV, `
        IIS-WebSockets, IIS-ApplicationInit, IIS-ASPNET, IIS-ASPNET45, IIS-ASP, IIS-CGI, IIS-ISAPIExtensions, `
        IIS-ISAPIFilter, IIS-ServerSideIncludes, IIS-CustomLogging, IIS-BasicAuthentication, IIS-HttpCompressionStatic, `
        IIS-ManagementConsole, IIS-ManagementService, IIS-WMICompatibility | Out-Null
    }

    if ($?)
    {
        Log-Success "[OK]`n"
    }
    else
    {
        Log-Error "Experienced errors trying to enable the required role(s) $Errors. Canceling..."
        Log-Warning "Please ensure the following roles are enabled manually:`
            WAS (Windows Activation Service), WAS-Process-Model, WAS-Config-APIs, Web-Server (IIS), '
            Web-WebServer, Web-Mgmt-Service, Web-Request-Monitor, Web-Common-Http, Web-Static-Content, '
            Web-Default-Doc, Web-Dir-Browsing, Web-Http-Errors, Web-App-Dev, Web-CGI, Web-Health,'
            Web-Http-Logging, Web-Log-Libraries, Web-Security, Web-Filtering, Web-Performance, '
            Web-Stat-Compression, Web-Mgmt-Tools, Web-Mgmt-Console, Web-Scripting-Tools, '
            Web-Asp-Net45, Web-Net-Ext45, Web-Http-Redirect, Web-Windows-Auth, Web-Url-Auth"
        exit -5
    }
}

<#
.SYNOPSIS
Add AzureCloud registry which used to identify NationalCloud
Usage:
    AddAzureCloudRegistry
#>

function AddingRegistryKeys
{
    Log-Info "Adding\Updating Registry Keys...`n"
    $AzureCloudName = "Public"

    if ( -not (Test-Path $RegAzureAppliancePath))
    {
        Log-Info "`tCreating Registry Node: $RegAzureAppliancePath"
        New-Item -Path $RegAzureAppliancePath -Force | Out-Null
    }

    New-ItemProperty -Path $RegAzureAppliancePath -Name AzureCloud -Value $AzureCloudName `
        -Force | Out-Null
    New-ItemProperty -Path $RegAzureAppliancePath -Name Type -Value Physical -Force | Out-Null

    if ( -not (Test-Path $RegAzureCredStorePath))
    {
        Log-Info "`tCreating Registry Node: $RegAzureCredStorePath"
        New-Item -Path $RegAzureCredStorePath -Force | Out-Null
    }

    New-ItemProperty -Path $RegAzureCredStorePath -Name CredStoreDefaultPath `
        -value "%Programdata%\Microsoft Azure\CredStore\Credentials.json" -Force | Out-Null

    Log-Info "`tSetting isSudo property as enabled for Linux VM discovery..."
    New-ItemProperty -Path $RegAzureCredStorePath -Name isSudo -PropertyType "DWord" -Value 1 -Force | Out-Null

    if ($DisableAutoUpdate -eq $true)
    {
        Log-Info "`tDisabling Auto Update for Azure Migrate..."
        New-ItemProperty -Path $RegAzureCredStorePath -Name AutoUpdate -PropertyType "DWord" -Value 0 -Force | Out-Null
        $global:WarningCount++
        Log-Warning "Warning #$global:WarningCount : Disabling Auto Update is not recomended. To enable Auto Update navigate to https://go.microsoft.com/fwlink/?linkid=2134524. Continuing..."
    }
    else
    {
        New-ItemProperty -Path $RegAzureCredStorePath -Name AutoUpdate -PropertyType "DWord" -Value 1 -Force | Out-Null
    }

    # Set service timeout to 90 secs to allow ASR agents to start on appliance reboot
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control"  -Name "ServicesPipeTimeout" -Value 90000

    # Enable long path support
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force | Out-Null

    if ( $?)
    {
        Log-Success "`n[OK]`n"
    }
    else
    {
        Log-Error "Failed to add\update registry keys. Aborting..."
        Log-Warning "Please ensure that the current user has access to add\update registry keys under the path: $RegAzureAppliancePath and $RegAzureCredStorePath"
        exit -6
    }
}

<#
.SYNOPSIS
Validate OS version
Usage:
    ValidateOSVersion
#>
function ValidateOSVersion
{
    [System.Version]$ver = "0.0"
    [System.Version]$minVer = "10.0.17763"

    Log-Info "Verifying supported Operating System version..."

    $OS = Get-WmiObject Win32_OperatingSystem
    $ver = $OS.Version

    If ($ver -lt $minVer)
    {
        Log-Error "The os version is $ver, minimum supported version is Windows Server 2019 ($minVer). Aborting..."
        log-Warning "Windows Server Core and Windows client SKUs are not supported."
        exit -7
    }
    elseif ($OS.Caption.contains("Server") -eq $false)
    {
        Log-Error "OS should be Windows Server 2019 and above. Aborting..."
        log-Warning "Windows Server Core and Windows client SKUs are not supported."
        exit -8
    }
    else
    {
        Log-Success "[OK]`n"
    }
}

<#
.SYNOPSIS
custom script run after the Windows Setup process.
Usage:
    CreateApplianceVersionFile
#>

function CreateApplianceVersionFile
{
    Log-Info "Creating Appliance Version File..."
    $ApplianceVersion = "6." + (Get-Date).ToString('yy.MM.dd')
    $fileContent = "$ApplianceVersion"

    if([System.IO.File]::Exists($ApplianceVersionFilePath))
    {
        Remove-Item -path $ApplianceVersionFilePath -Force
    }

    # Create Appliance version text file.
    New-Item $ApplianceVersionFilePath -ItemType File -Value $ApplianceVersion -Force | Out-Null
    Set-ItemProperty $ApplianceVersionFilePath -name IsReadOnly -value $true

    if ($?)
    {
        Log-Success "[OK]`n"
    }
    else
    {
        Log-InfoHighLight "Failed to create Appliance Version file with at $ApplianceVersionFilePath. Continuing..."
    }
}

<#
.SYNOPSIS
Validate and exit if minimum defined PowerShell version is not available.
Usage:
    ValidatePSVersion
#>

function ValidatePSVersion
{
    [System.Version]$minVer = "4.0"

    Log-Info "Verifying the PowerShell version to run the script..."

    if ($PSVersionTable.PSVersion)
    {
        $global:PsVer = $PSVersionTable.PSVersion
    }

    If ($global:PsVer -lt $minVer)
    {
        Log-Error "PowerShell version $minVer, or higher is required. Current PowerShell version is $global:PsVer. Aborting..."
        exit -11;
    }
    else
    {
        Log-Success "[OK]`n"
    }
}

<#
.SYNOPSIS
Validate and exit if PS process in not 64-bit as few cmdlets like install-windowsfeature is not available in 32-bit.
Usage:
    ValidateIsPowerShell64BitProcess
#>

function ValidateIsPowerShell64BitProcess
{
    Log-Info "Verifying the PowerShell is running in 64-bit mode..."

	# This check is valid for PowerShell 3.0 and higher only.
    if ([Environment]::Is64BitProcess)
    {
        Log-Success "[OK]`n"
    }
    else
    {
        Log-Warning "PowerShell is running in 32-bit mode. Launch PowerShell in 64-bit mode and rerun the script. Canceling..."
        Log-Error "[Failed]`n"
        exit -11;
    }
}

<#
.SYNOPSIS
Ensure IIS backend services are in running state. During IISReset they can remain in stop state as well.
Usage:
    StartIISServices
#>

function StartIISServices
{
    Log-Info "Ensuring critical services for Azure Migrate appliance configuration manager are running..."

    Start-service -Name WAS
    Start-service -Name W3SVC

    if ($?)
    {
        Log-Success "[OK]`n"
    } else
    {
        Log-Error "Failed to start services WAS/W3SVC. Aborting..."
        Log-Warning "Manually start the WAS and W3SVC services. "
        exit -12
    }
}

<#
.SYNOPSIS
Set Trusted Hosts in the host\current machine.
Usage:
    SetTrustedHosts
#>

function SetTrustedHosts
{
    $currentList = Get-Item WSMan:\localhost\Client\TrustedHosts
    Log-Info "The current value of $($currentList.Name) = $($currentList.Value)"

    if ($SkipSettingTrustedHost)
    {
        $global:WarningCount++
        Log-Warning "Warning #$global:WarningCount : Skipping the setup of Trusted Hosts list for WinRM. Manually set up the Trusted Hosts list on your Windows servers that will access this appliance."
        Log-InfoHighLight "Not specifying workgroup machines in the Trusted Host list leads to Validate-Operation failure during onboarding through Azure Migrate appliance configuration manager. Continuing...`n"

        return
    }

    if($currentList -ne $null)
    {
        # Need to add a better than *. * will be used for preview.
        $list = "*"
        Log-Info "Adding $($list) as trusted hosts to the current host machine..."

        Set-Item WSMan:\localhost\Client\TrustedHosts $list.ToString() -Force

        if ($?)
        {
            Log-Success "[OK]`n"
        }
        else
        {
            Log-Error "Failure in adding trusted hosts. Aborting..."
            Log-Warning "Please use -SkipSettingTrustedHost flag to skip this step and rerun this script."
            exit -13
        }
    }
    else
    {
        Log-Error "Unable to get trusted host list. Aborting..."
        exit -13
    }
}

<#
.SYNOPSIS
Set LEDBAT network configuration to lower priority of SMB traffic.
Usage:
    SetNetworkConfig
#>

function SetNetworkConfig
{
    try
    {
        if ($global:SelectedEnableAzureStackHCITarget -eq "True")
        {
            # If AzureStackHCI target is enabled, enable LEDBAT to lower priority of SMB traffic to prevent network congestion due to data transfer
            Log-Info "Enabling LEDBAT for SMB traffic on current host machine..."

            $targetVersion = [Version]"10.0.1706"
            $osVersion = (Get-WmiObject Win32_OperatingSystem).Version
            $currentVersion = [Version]$osVersion

            if ($currentVersion -lt $targetVersion) {
                $targetUpdate = "KB4132216"
                $installedUpdates = Get-HotFix | Where-Object { $_.HotFixID -like "KB*" -and $_.HotFixID -ge $targetUpdate }
                if (!$installedUpdates) {
                    $global:WarningCount++
                    Log-Warning "Warning #$global:WarningCount KB4132216 and KB4284833 are required to enable LEDBAT. Skipping to enable LEDBAT and continuing..."

                    return
                }
            }

            Set-NetTCPSetting -SettingName InternetCustom -CongestionProvider LEDBAT
            New-NetTransportFilter -SettingName InternetCustom -Protocol TCP -LocalPortStart 0 -LocalPortEnd 65535  -RemotePortStart 445 -RemotePortEnd 445 -ErrorAction SilentlyContinue
        }
    }
    catch
    {
        Log-Warning "Warning #$global:WarningCount Network configuration failed."
        Log-Warning "[Exception caught] $_.Exception"
        Log-Warning "Continuing with the script execution..."
    }
}

<#
.SYNOPSIS
Uninstall IE as IE is not compatible with Azure Migrate ConfigManager. IE cannot be uninstalled like regular programs.
Usage:
    UninstallInternetExplorer
#>

function UninstallInternetExplorer
{
    if ((Get-WindowsOptionalFeature -Online -FeatureName "Internet-Explorer-Optional-amd64").State -eq "Disabled")
    {
        Log-Info "Internet Explorer has already been uninstalled. Skipping uninstallation and continuing..."
        Log-Success "[OK]`n"

        return
    }

    do
    {
        Log-InfoHighLight "Azure Migrate Appliance Configuration Manager is not supported on Internet Explorer versions 11 or earlier."
        Log-InfoHighLight "You can either uninstall Internet Explorer using this script or open the appliance URL https://$machineHostName`:44368 on another browser except Internet Explorer."
        Log-Input "Do you want to remove Internet Explorer browser from this machine now? This will force a machine reboot immediately. Press [Y] to continue with the uninstallation or [N] to manually uninstall Internet Explorer..."
        $userChoice = Read-Host
    }while ("y", "n" -NotContains $userChoice.Trim())

    if ($userChoice.Trim() -eq "n")
    {
        $global:WarningCount++
        Log-Error "Skipping IE uninstallation..."
        Log-Warning "Warning #$global:WarningCount User Action Required - Remove Internet Explorer as the default browser and then launch Azure Migrate appliance configuration manager using the shortcut placed on the desktop.`n"
    }
    else
    {
        dism /online /disable-feature /featurename:Internet-Explorer-Optional-amd64 /NoRestart

        # Restart the machine
        shutdown -r -t 60 -f
        Log-Success "[OK]"
        Log-InfoHighLight "Restarting machine $machineHostName in 60 seconds. To abort this restart execute 'shutdown /a' - Not Recommended."

        # Exit the script as restart is pending.
        exit 0
    }
}

<#
.SYNOPSIS
Install New Edge Browser.
Usage:
    InstallEdgeBrowser
#>

function InstallEdgeBrowser
{
    $edgeInstallerFilePath = ""

    if( Test-Path -path "HKLM:\SOFTWARE\Clients\StartMenuInternet\Microsoft Edge")
    {
        Log-Info "New Edge browser is already installed. Skipping installation and continuing..."
        Log-Success "[OK]`n"
        return
    }

    do
    {
        Log-InfoHighLight "Azure Migrate Appliance Configuration Manager is not supported on Internet Explorer version 11 or earlier. Install a supported browser version to continue - Microsoft Edge (latest version), Chrome (latest version), or Firefox (latest version)."
        Log-Input "Do you want to install new Microsoft Edge browser (highly recommended)? [Y/N] - Select 'N' to skip the installation if you are already running a supported browser version:"
        $userChoice = Read-Host
    }while ("y", "n" -NotContains $userChoice.Trim())

    if ($userChoice.Trim() -eq "n")
    {
        $global:WarningCount++
        Log-Error "Skipping Microsoft Edge browser installation..."
        Log-Warning "Warning #$global:WarningCount User action required - Install the Microsoft Edge browser manually or use Chrome (latest version), or Firefox (latest version).`n"
        return
    }
    else
    {
        $regHive = "HKLM:\Software\Policies\Microsoft\Edge"
        if ( -not (Test-Path $regHive))
        {
            New-Item -Path $regHive -Force
        }

        New-ItemProperty -Path $regHive -Name "HideFirstRunExperience" -PropertyType "dword" -Value 1 -Force | Out-Null

        if ($global:SelectedPEEnabled -eq $true)
        {
            Log-Info "`nInstalling the Microsoft Edge using offline installer."
            $edgeInstallerFilePath = "$PSScriptRoot\MicrosoftEdgeEnterpriseX64.msi"
            $process = Start-Process -Wait -Passthru -FilePath msiexec -ArgumentList "/i `"$edgeInstallerFilePath`" /quiet /lv `"$Env:ProgramData\Microsoft Azure\Logs\MicrosoftEdgex64Enterprise.log`""
        }
        else
        {
            Log-Info "`nDownloading and installing the latest Microsoft Edge."
            $edgeInstallerFilePath = "$PSScriptRoot\MicrosoftEdgeSetup.exe"
            $process = Start-Process -Wait -Passthru -FilePath `"$edgeInstallerFilePath`"
        }

        $returnCode = $process.ExitCode;
        if ($returnCode -eq 0 -or $returnCode -eq 3010)
        {
            $edgeShortCut = "$env:SystemDrive`\Users\Public\Desktop\Microsoft Edge.lnk"
            if (Test-Path $edgeShortCut)
            {
                remove-item -Path $edgeShortCut -Force | Out-Null
            }

            Log-Info "Make Microsoft Edge your default browser and open Azure Migrate Appliance Configuration Manager at https://$machineHostName`:44368."
            Log-Info "Successfully installed Microsoft Edge browser on $machineHostName."
            Log-Success "[OK]`n"

        }
        else
        {
            $global:WarningCount++
            Log-Error "$edgeInstallerFilePath installation failed on $machineHostName machine with errorcode: $returnCode."
            Log-Warning "Warning #$global:WarningCount User Action Required - Manually download and install Microsoft Edge browser manually from the location: https://www.microsoft.com/en-us/edge/business/download. Continuing...`n"
        }
    }
}

#region - Detect user intent

<#
.SYNOPSIS
Detect fabric value from parameter/preset file/user input.
Usage:
    DetectFabric -presetJsonContent $presetJsonContent
#>

function DetectFabric
{
     param(
     $presetJsonContent
     )

    $scenarioText               = "Physical or other (AWS, GCP, Xen, etc.)"
    $scenarioSubText            = "Unknown"
    $scenarioSubTextForHyperV   = "discover, assess and migrate the servers running in your Hyper-V environment"
    $scenarioSubTextForPhysical = "discover and assess the servers running as $scenarioText"
    $scenarioSubTextForVMware   = "discover, assess and migrate the servers running in your VMware environment"
    $expectedScenarioList       = "HyperV","Physical","VMware","VMwareV2","AzureStackHCI", $global:AzureLocalTarget
    $scenarioSwitch             = "Unknown"
    $selectionMode              = ""
    $azureLocalSecenarioText = "Azure Local target appliance (For target setup only. To set up a source appliance for Azure Local migrations, select VMware or Hyper-V above)"

    if ($Scenario)
    {
        $scenarioSwitch = $Scenario
    }
    elseif ($presetJsonContent.Scenario -and $expectedScenarioList -contains $presetJsonContent.Scenario.Trim())
    {
        $scenarioSwitch = $presetJsonContent.Scenario.Trim()
        $selectionMode = "(preconfigured)"
    }
    else
    {
        do
        {
            Log-Info "1. VMware `n2. Hyper-V `n3. $scenarioText `n4. $azureLocalSecenarioText"
            Log-Input "Please enter the option for desired scenario [1, 2 3 or  4]:"
            $scenarioSwitch = Read-Host
            $scenarioSwitch = $scenarioSwitch.Trim()
            Log-InfoHighLight ""

            if ("1", "2", "3", "4" -NotContains $scenarioSwitch)
            {
                Log-Error "[Incorrect input]"
                Log-Warning "Supported options are: 1, 2, 3 or  4 only. Please try again...`n"
                continue
            }

            break
        }while ($true)
    }

    switch($scenarioSwitch)
    {
        {$_ -eq 1 -or $_ -eq "VMware" -or $_ -eq "VMwareV2"}
        {
            $global:SelectedFabricType  = $scenarioText = "VMware"
            $scenarioSubText = $scenarioSubTextForVMware
            break
        }

        {$_ -eq 2 -or $_ -eq "HyperV"}
        {
            $global:SelectedFabricType = $scenarioText = "HyperV"
            $scenarioSubText = $scenarioSubTextForHyperV
            break
        }

        {$_ -eq 3 -or $_ -eq "Physical"}
        {
            #$scenarioText = Already Initialized
            $global:SelectedFabricType  = "Physical"
            $scenarioSubText = $scenarioSubTextForPhysical
            break
        }

        {$_ -eq 4 -or $_ -eq "AzureStackHCI" -or $_ -eq $global:AzureLocalTarget }
        {
            $global:SelectedFabricType  = "AzureStackHCI"
            break
        }

        default
        {
            Log-Error "Unexpected Scenario option. $selectionMode Aborting..."
            Log-Warning "Know more about the supported scenarios for Azure Migrate: https://go.microsoft.com/fwlink/?linkid=2164248"
            exit -1
        }
    }

    $fabricTypeText = $global:SelectedFabricType
    if ($global:SelectedFabricType -eq "AzureStackHCI") {
        $fabricTypeText = $global:AzureLocalTarget
    }
    Log-Info "Selected scenario: $fabricTypeText  $selectionMode"
    Log-Success "[OK]`n"

    return $scenarioText, $scenarioSubText
}

<#
.SYNOPSIS
Detect Cloud value from parameter/preset file/user input.
Usage:
    DetectCloud -presetJsonContent $presetJsonContent
#>

function DetectCloud
{
     param(
     $presetJsonContent
     )

    $cloudSwitch       = "Unknown"
    $expectedCloudList = "Public", "Azure Public", "USGov", "USNat", "USSec", "AzureChina", "Azure China", "CNProd"
    $selectionMode     = ""
    $cloudTypeText     = ""

    if ($Cloud)
    {
        $cloudSwitch = $Cloud
    }
    elseif ($presetJsonContent.Cloud -and $expectedCloudList -contains $presetJsonContent.Cloud.Trim())
    {
        $cloudSwitch   = $presetJsonContent.Cloud.Trim()
        $selectionMode = "(preconfigured)"
    }
    else
    {
        do
        {
            log-info "1. Azure Public `n2. Azure US Government `n3. Azure China"
            Log-Input "Please enter the option for desired cloud [1, 2 or 3]:"
            $cloudSwitch = Read-Host
            $cloudSwitch = $cloudSwitch.Trim()
            Log-InfoHighLight ""

            if ("1", "2", "3" -NotContains $cloudSwitch)
            {
                Log-Error "[Incorrect input]"
                Log-Warning "Supported options are: 1, 2 and 3 only. Please try again...`n"
                continue
            }

            break
        }while ($true)
    }

    switch($cloudSwitch)
    {
        {$_ -eq 1 -or $_ -eq "Public" -or $_ -eq "Azure Public"}
        {
            $global:SelectedCloud = "Public"
            $cloudTypeText        = "Azure Public"
        }

        {$_ -eq 2 -or $_ -eq "USGov"}
        {
            $global:SelectedCloud = "USGov"
            $cloudTypeText        = "Azure US Government"
        }

        {$_ -eq "USNat"}
        {
            $global:SelectedCloud = "USNat"
            $cloudTypeText        = "USNat"
        }

        {$_ -eq "USSec"}
        {
            $global:SelectedCloud = "USSec"
            $cloudTypeText        = "USSec"
        }
        {$_ -eq 3 -or $_ -eq "CNProd" -or $_ -eq "AzureChina" -or $_ -eq "Azure China"}
        {
            $global:SelectedCloud = "AzureChina"
            $cloudTypeText        = "Azure China"
        }

        default
        {
            Log-Error "Unexpected Cloud option. $selectionMode Aborting..."
            Log-Warning "Know more about the supported clouds for Azure Migrate: https://go.microsoft.com/fwlink/?linkid=2164248"
            exit -1
        }
    }

    Log-Info "Selected cloud: $cloudTypeText $selectionMode"
    Log-Success "[OK]`n"

    return $cloudTypeText
}

<#
.SYNOPSIS
Detect Appliance type (Primary/ScaleOut) from parameter/preset file/user input.
Usage:
    DetectApplianceType -presetJsonContent $presetJsonContent
#>

function DetectApplianceType
{
     param(
     $presetJsonContent
     )

     $applianceUnit        = "primary"
     $applianceTypeSwitch  = "Unknown"
     $expectedBooleanValue = "False","True"
     $selectionMode        = ""

    if ($global:ParameterList.ContainsKey("ScaleOut"))
    {
        $applianceTypeSwitch = $ScaleOut
    }
    elseif ($presetJsonContent.ScaleOut -and $expectedBooleanValue -contains $presetJsonContent.ScaleOut.Trim())
    {
        $applianceTypeSwitch = $presetJsonContent.ScaleOut.Trim()
        $selectionMode = "(preconfigured)"
    }
    else
    {
        if($global:SelectedFabricType -ne "vmware")
        {
           $global:SelectedScaleOut = "false"
           return $applianceUnit
        }

        do
        {
            Log-Info "1. Primary appliance to discover, assess and migrate servers"
            Log-Info "2. Scale-out appliance to replicate more servers concurrently"
            Log-InfoHighLight "Know more about the scale-out capability for migration: https://go.microsoft.com/fwlink/?linkid=2151823"
            Log-Input "Please enter the option for desired configuration [1 or 2]:"
            $applianceTypeSwitch = Read-Host
            $applianceTypeSwitch = $applianceTypeSwitch.Trim()
            Log-InfoHighLight ""

            if ("1", "2" -NotContains $applianceTypeSwitch)
            {
                    Log-Error "[Incorrect input]"
                    Log-Warning "Supported options are: 1 or 2 only. Please try again...`n"
                    continue
            }

            break;
        }while ($true)
    }

    switch($applianceTypeSwitch)
    {
        {$_ -eq 1 -or $_ -eq $false -or $_ -eq "false"}
        {
            $global:SelectedScaleOut = "False"
            $applianceTypeText = "Selected configuration: This appliance will be setup as a primary appliance $selectionMode"
            $applianceUnit = "primary"
        }

        {$_ -eq 2 -or $_ -eq $true -or $_ -eq "true"}
        {
            $global:SelectedScaleOut = "True"
            $applianceTypeText = "Selected configuration: This appliance will be setup to scale-out migrations $selectionMode"
            $applianceUnit = "scale-out"
        }

        default
        {
            Log-Error "Unexpected Appliance type. Aborting..."
            Log-Warning "Know more about the scale-out capability for migration: https://go.microsoft.com/fwlink/?linkid=2151823"
            exit -1
        }
    }

    if($global:SelectedFabricType -ne "VMware" -and $global:SelectedScaleOut -eq "true")
    {
        Log-Error "Only VMware scenario is supported with scale-out capability. Aborting..."
        Log-Warning "Please execute the script again. Know more about how to execute a script with parameters: https://go.microsoft.com/fwlink/?linkid=2164248`n"
        exit -1
    }
    else
    {
        Log-Info $applianceTypeText
        Log-Success "[OK]`n"
    }

    return $applianceUnit
}

<#
.SYNOPSIS
Detect cloud access type (Public/Private link) from parameter/preset file/user input.
Usage:
    DetectCloudAccessType -presetJsonContent $presetJsonContent
#>

function DetectCloudAccessType
{
     param(
     $presetJsonContent
     )

     $cloudAccessType       = "public"
     $cloudAccessTypeSwitch = "Unknown"
     $expectedBooleanValue  = "False","True"
     $selectionMode         = ""

    if ($global:SelectedCloud -eq "AzureChina")
    {
        # Azure China has only public endpoint support.
        $cloudAccessTypeSwitch = "false"
    }
    elseif ($global:ParameterList.ContainsKey("PrivateEndpoint"))
    {
        $cloudAccessTypeSwitch = $PrivateEndpoint
    }
    elseif ($presetJsonContent.PrivateEndpoint -and $expectedBooleanValue -contains $presetJsonContent.PrivateEndpoint.Trim())
    {
        $cloudAccessTypeSwitch = $presetJsonContent.PrivateEndpoint.Trim()
        $selectionMode = "(preconfigured)"
    }
    else
    {
        do
        {
            Log-Info "1. Set up an appliance for a Migrate project created with default (public endpoint) connectivity"
            Log-Info "2. Set up an appliance for a Migrate project created with private endpoint connectivity"
            Log-InfoHighLight "Know more about the private endpoint connectivity: https://go.microsoft.com/fwlink/?linkid=2155739"
            Log-Input "Please enter the option for desired configuration [1 or 2]:"
            $cloudAccessTypeSwitch = Read-Host
            $cloudAccessTypeSwitch = $cloudAccessTypeSwitch.Trim()
            Log-InfoHighLight ""

            if ("1", "2" -NotContains $cloudAccessTypeSwitch)
            {
                Log-Error "[Incorrect input]"
                Log-Warning "Supported options are: 1 or 2 only. Please try again...`n"
                continue
            }

            break;
        }while ($true)
    }

    switch($cloudAccessTypeSwitch)
    {
        {$_ -eq 1 -or $_ -eq $false -or $_ -eq "false"}
        {
            $global:SelectedPEEnabled = "false"
            $cloudAccessTypeText = "Selected connectivity: This appliance will be configured for the default (Public endpoint) connectivity $selectionMode"
            $cloudAccessType = "default (public endpoint)"
        }

        {$_ -eq 2 -or $_ -eq $true -or $_ -eq "true"}
        {
            $global:SelectedPEEnabled = "true"
            $cloudAccessTypeText = "Selected connectivity: This appliance will be optimized for private endpoint connectivity $selectionMode"
            $cloudAccessType = "private endpoint"
        }

        default
        {
            Log-Error "Unexpected cloud access type. Aborting..."
            Log-Warning "Know more about the private endpoint connectivity: https://go.microsoft.com/fwlink/?linkid=2155739"
            exit -1
        }
    }

    Log-Info $cloudAccessTypeText
    Log-Success "[OK]`n"

    return $cloudAccessType
}


<#
.SYNOPSIS
Detect EnableAzureStackHCITarget from parameter/preset file/user input.
Usage:
    DetectEnableAzureStackHCITarget -presetJsonContent $presetJsonContent
#>

function DetectEnableAzureStackHCITarget
{
     param(
     $presetJsonContent
     )

     $enableAzureStackHCITargetSwitch = "false"
     $expectedBooleanValue  = "False","True"
     $selectionMode         = ""

    if ($global:SelectedFabricType -eq "Physical")
    {
        # Physical does not support AzureStackHCI as target
        $enableAzureStackHCITargetSwitch = "false"
    }
    elseif ($global:SelectedFabricType -eq "AzureStackHCI" -or $global:SelectedFabricType -eq "HyperV" )
    {
        # AzureStackHCI fabric always has this set to true
        $enableAzureStackHCITargetSwitch = "true"
    }
    elseif ($global:ParameterList.ContainsKey("EnableAzureStackHCITarget"))
    {
        $enableAzureStackHCITargetSwitch = $EnableAzureStackHCITarget
    }
    elseif ($global:ParameterList.ContainsKey("EnableAzureLocalTarget"))
    {
        $enableAzureStackHCITargetSwitch = $EnableAzureLocalTarget
    }
    elseif ($presetJsonContent.AzureStackHCITarget -and $expectedBooleanValue -contains $presetJsonContent.AzureStackHCITarget.Trim())
    {
        $enableAzureStackHCITargetSwitch = $presetJsonContent.AzureStackHCITarget.Trim()
        $selectionMode = "(preconfigured)"
    }
    elseif ($presetJsonContent.AzureLocal -and $expectedBooleanValue -contains $presetJsonContent.AzureLocal.Trim())
    {
        $enableAzureStackHCITargetSwitch = $presetJsonContent.AzureLocal.Trim()
        $selectionMode = "(preconfigured)"
    }
    else
    {
        if ($global:SelectedScaleOut -eq "true") { 
             # migrate to Azure Local does not support scaleout at this time, so skip the check for azure local credentials
            $enableAzureStackHCITargetSwitch  = "false"
        }
        else {

            do
            {
                Log-Info "Choose the purpose of this appliance:"
                Log-Info "1. To decide, plan and execute migrations to Azure only (default)"
                Log-Info "2. To migrate to Azure Local only"
    
                Log-Input "Please enter the option for desired configuration [1 or 2]:"
                $enableAzureStackHCITargetSwitch = Read-Host
                $enableAzureStackHCITargetSwitch = $enableAzureStackHCITargetSwitch.Trim()
                Log-InfoHighLight ""
    
                if ("1", "2" -NotContains $enableAzureStackHCITargetSwitch)
                {
                    Log-Error "[Incorrect input]"
                    Log-Warning "Supported options are: 1 or 2 only. Please try again...`n"
                    continue
                }
    
                break;
            }while ($true)
        }
    }

    switch($enableAzureStackHCITargetSwitch)
    {
        {$_ -eq 1 -or $_ -eq $false -or $_ -eq "false"}
        {
            $global:SelectedEnableAzureStackHCITarget = "false"
        }

        {$_ -eq 2 -or $_ -eq $true -or $_ -eq "true"}
        {
            $global:SelectedEnableAzureStackHCITarget = "true"
        }

        default
        {
            Log-Error "Unexpected target type. Aborting..."
            exit -1
        }
    }

    if ($global:SelectedEnableAzureStackHCITarget -eq "true")  {
        if ($global:SelectedFabricType -eq "AzureStackHCI") {
            Log-Info "This appliance will be used as an Azure Local target appliance only."
            Log-Success "[OK]`n"
        } elseif ($global:SelectedFabricType -eq "VMware") {
            Log-Info "This appliance will be used for discovery and migration to Azure Local only."
            Log-Success "[OK]`n"
        }
    } else {
        Log-Info "This appliance will be used to decide, plan and execute migrations to Azure only."
        Log-Success "[OK]`n"
    }

    return $global:SelectedEnableAzureStackHCITarget
}


<#
.SYNOPSIS
Detect presets for various parameters.
Usage:
    DetectPresets
#>

function DetectPresets
{
    $presetFilePath      = "$PSScriptRoot\Preset.json"
    $applianceUnit       = "primary"
    $AccessType          = "public"
    [string] $userChoice = "y"

    if (Test-Path $ApplianceJsonFilePath)
    {
        $applianceJsonContent = Get-Content $ApplianceJsonFilePath | Out-String | ConvertFrom-Json

        if ($applianceJsonContent.IsApplianceRegistered.ToLower() -eq "true")
        {
            $global:SelectedCloud = $applianceJsonContent.Cloud

            if ($applianceJsonContent.FabricType -like "vmware*")
            {
                # Handle VMwareV2 to VMware name conversion
                $global:SelectedFabricType = "VMware"
            }
            else
            {
                $global:SelectedFabricType = $applianceJsonContent.FabricType
            }

            if ($applianceJsonContent.ScaleOut -eq "true")
            {
                $applianceUnit = "scale-out"
                $global:SelectedScaleOut = "True"
            }

            if ($applianceJsonContent.PrivateEndpointEnabled -eq "true")
            {
                $AccessType = "private"
                $global:SelectedPEEnabled = "True"
            }

            if ($applianceJsonContent.EnableAzureStackHCITarget -and $applianceJsonContent.EnableAzureStackHCITarget -eq "true")
            {
                $global:SelectedEnableAzureStackHCITarget = "True"
            }

            # This machine has been already registered as an Azure Migrate appliance
            $global:ReuseScenario = 1

            do
            {
                # Skip the confirmation
                if ($Repurpose.IsPresent -or $UpgradeAgents.IsPresent)
                {
                    $userChoice = "y"
                    break
                }
                $fabricTypeText = $global:SelectedFabricType
                if ($global:SelectedFabricType -eq "AzureStackHCI") {
                    $fabricTypeText = $global:AzureLocalTarget
                }
                Log-Error "This host $machineHostName has already been registered as a $applianceUnit Azure Migrate appliance with Migrate Project on $global:SelectedCloud cloud for $fabricTypeText scenario with $AccessType endpoint connectivity. If you choose to proceed, configuration files from the previous installation will be lost permanently."
                Log-Input "Enter [Y] to continue or [N] to abort:"
                $userChoice = Read-Host
                Log-InfoHighLight ""
            }while ("y", "n" -NotContains $userChoice.Trim())
        }

        if ($userChoice.Trim() -eq "n")
        {
            Log-Error "You have chosen to exit. Aborting..."
            Log-Warning "Know more about how to execute a script with parameters: https://go.microsoft.com/fwlink/?linkid=2164248"
            exit -1
        }
    }

    if ($UpgradeAgents.IsPresent)
    {
        if ($global:ReuseScenario -eq 0)
        {
            Log-Error "This host $machineHostName has not been registered as an Azure Migrate appliance. 'UpgradeAgents' parameter is not supported in this state. Aborting..."
            Log-Warning "Please execute the script again. Know more about how to execute a script with parameters: https://go.microsoft.com/fwlink/?linkid=2164248"
            exit -15
        }
        else
        {
            return
        }
    }
    else
    {
        # [Optional] Clean up global options
        $global:SelectedFabricType = $global:DefaultStringVal
        $global:SelectedCloud      = $global:DefaultStringVal
        $global:SelectedScaleOut   = "False"
        $global:SelectedPEEnabled  = "False"
        $global:SelectedEnableAzureStackHCITarget = "False"
    }

    if ($RemoveAzMigrate -eq $true)
    {
        # Do nothing.
        return
    }

    if([System.IO.File]::Exists($presetFilePath))
    {
        Log-Info "Attempting to read mandatory parameters from the preset file: $presetFilePath."

        try
        {
            $presetJsonContent = Get-Content $presetFilePath | Out-String | ConvertFrom-Json
        }
        catch
        {
            Log-Error "Unable to read the preset file due to error: $_"
            Log-Warning "Retry executing the script after resolving this issue or removing the preset file.`n"
            exit -1
        }

        Log-Success "[OK]`n"
    }

    $scenarioText, $scenarioSubText = DetectFabric($presetJsonContent)
    $cloudTypeText   = DetectCloud($presetJsonContent)
    $applianceUnit   = DetectApplianceType($presetJsonContent)
    $cloudAccessType = DetectCloudAccessType($presetJsonContent)
    $enableAzureStackHCITarget = DetectEnableAzureStackHCITarget($presetJsonContent)

    if ($scenarioText -contains "VMware" -and $global:SelectedScaleOut -eq "True")
    {
        $message = "You have chosen to set up a $applianceUnit appliance to initiate concurrent replications on servers in your VMware environment to an Azure Migrate project with $cloudAccessType connectivity on $cloudTypeText cloud."
    }
    elseif ($scenarioText -contains "VMware" -and $global:SelectedEnableAzureStackHCITarget -eq "True")
    {
        $message = "You have chosen to set up an appliance to discover and migrate the servers running in your VMware environment to your Azure Local environment using an Azure Migrate project with $cloudAccessType connectivity on $cloudTypeText cloud."
    }
    elseif ($scenarioText -contains "HyperV" -and $global:SelectedEnableAzureStackHCITarget -eq "True")
    {
        # SelectedEnableAzureStackHCITarget is always true for HyperV scenario so the message will contain both options Azure and Azure Local.
        $message = "You have chosen to set up an appliance to discover and migrate the servers running in your Hyper-V environment to either Azure or Azure Local environment (not both at the same time), using an Azure Migrate project with $cloudAccessType connectivity on $cloudTypeText cloud."
    }
    elseif ($global:SelectedFabricType -eq "AzureStackHCI")
    {   
        $message = "You have chosen to set up a target appliance to migrate servers to your Azure Local environment using an Azure Migrate project with $cloudAccessType connectivity on $cloudTypeText cloud."
    }
    else
    {   
        $message = "You have chosen to set up an appliance to $scenarioSubText to an Azure Migrate project with $cloudAccessType connectivity on $cloudTypeText cloud."
    }

    Log-InfoHighLight $message

    do
    {
        Log-Info "If this is not the desired configuration to set up the appliance, you can abort and execute the script again."
        Log-Input "Enter [Y] to continue with the deployment or [N] to abort:"
        $userChoice = Read-Host
        Log-InfoHighLight ""
    }while ("y", "n" -NotContains $userChoice.Trim())

    Log-InfoHighLight ""
    if ($userChoice.Trim() -eq "n")
    {
       Log-Error "You have chosen to exit. Aborting..."
       Log-Warning "Know more about how to execute a script with parameters: https://go.microsoft.com/fwlink/?linkid=2164248"
       exit 0
    }
}

#endregion

<#
.SYNOPSIS
Install Gateway service.
Usage:
    InstallGatewayService -$gatewayPackagerPath "$$gatewayPackagerPath" -$MSIInstallLogName "ToDo"
#>

function InstallGatewayService
{
    param(
        [string] $gatewayPackagerPath,
        [string] $MSIInstallLogName
    )

    [int]$maxRetryLimit = 5
    [int]$retryCount    = 0
    [string]$filePath   = "$PSScriptRoot\GATEWAYSETUPINSTALLER.EXE"

    $extractCmd = "`"$gatewayPackagerPath`"" + " /q /x:`"$PSScriptRoot`""

    Log-Info "Extracting and Installing Gateway Service..."

     while($maxRetryLimit -gt $retryCount)
     {
        $Error.Clear()

        Invoke-Expression "& $extractCmd"
        Start-Sleep -Seconds 5

        $process = (Start-Process -Wait -Passthru -FilePath "$filePath" -ArgumentList "CommandLineInstall ")
        $returnCode = $process.ExitCode;

        if ($returnCode -eq 0 -or $returnCode -eq 3010)
        {
            Log-Success "[OK]`n"
            return
        }
        else
        {
            $retryCount++
            Log-InfoHighLight "$filePath installation failed with $returnCode."
            Log-Warning "Retry attempt #$retryCount of #$maxRetryLimit.`n"
            Start-Sleep -Seconds 10
        }
    }

    Log-Error "Gateway service installation failed. Aborting..."
    Log-Warning "Please refer to https://learn.microsoft.com/en-us/windows/win32/msi/windows-installer-error-messages to get details about the error code: $returnCode. Please share the installation log file while contacting Microsoft Support."
    exit -16
}

<#
.SYNOPSIS
Validate if Replication Appliance (ASR) component is installed on this host machine
Usage:
    ValidateRepAppliance -ProgramName
#>
function ValidateRepAppliance
{
    param(
        [string] $programName
    )

    [bool] $x86_check = $False
    [bool] $x64_check = $False

    Log-Info "Verifying that no replication appliance/Azure Site Recovery components are already installed on this host..."

    try
    {
        $x86_check = ((Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*) | Where-Object { $_."DisplayName" -like "*$programName*" } ).DisplayName.Length -gt 0;
        # ASR doesn't install x64 components hence the check is not being performed.
        #$x64_check = ((Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*) | Where-Object { $_."DisplayName" -like "*$programName*" } ).DisplayName.Length -gt 0;

        If ($x86_check -eq $true)
        {
            Log-Error "Replication appliance/Azure Site Recovery component(s) ‘$programName’ is already installed on this host. Aborting..."
            Log-Warning "Please use another host to set up the Azure Migrate appliance or remove the existing Replication appliance/Azure Site Recovery component(s) from this host and execute the script again."
            exit -1
        }
        else
        {
            Log-Success "[OK]`n"
        }
    }
    catch
    {
        Log-Error "[Failed to verify]"
        Log-InfoHighLight "Error Record: $_.Exception.ErrorRecord"
        Log-InfoHighLight "Exception caught:  $_.Exception"
        Log-Warning "Continuing with the script execution..."
        $Error.Clear()
    }
}

<#
.SYNOPSIS
Increase the maxenvelopsize from default 500KB to a higher size.
This is essential for WMI calls to get cluster resources.
Usage:
    IncreaseWSManPayloadSize
#>

function IncreaseWSManPayloadSize
{
    $MaxWSManPayloadSizeKB = 10240
    Log-Info "Increasing the maxenvelopsize from 500KB to 10MB..."

    try
    {
        Set-Item -Path WSMan:\localhost\MaxEnvelopeSizeKb -Value $MaxWSManPayloadSizeKB
    }
    catch
    {
        # Max envelop size fails in some cases, re-try with a different command.
        Log-Warning "Cannot increase maxenvelopsize trying alternative approach."
        Log-Info "Increasing the maxenvelopsize from 500KB to 10MB..."
        try
        {
            Set-WSManInstance -ResourceURI winrm/config -ValueSet @{MaxEnvelopeSizekb = $MaxWSManPayloadSizeKB}
        }
        catch
        {
            Log-Warning "Failed to increase WSMan envelope size. Execute the following command to increase the size manually:"
            Log-InfoHighLight "Set-WSManInstance -ResourceURI winrm/config -ValueSet @{MaxEnvelopeSizekb = ""10240""}"
            Log-Warning "If you continue to get issues, please submit a Microsoft support case."
        }
    }

    if ($?)
    {
        Log-Success "[OK]`n"
    }
    else
    {
        Log-Error "Failure in increasing WSMan envelope size. Aborting..."
        exit -13
    }
}

<#
.SYNOPSIS
Check if the appliance is running on an Azure VM and set prerequisites accordingly.
Usage:
    SetAzureVMPrerequisites
#>
function Set-AzureVMPrerequisites
{
    try
    {
        $metadata = Invoke-RestMethod `
            -Headers @{ "Metadata" = "true" } `
            -Method GET `
            -Uri "http://169.254.169.254/metadata/instance?api-version=2021-02-01" `
            -TimeoutSec 2 `
            -ErrorAction Stop
    }
    catch
    {
        $metadata = $null
    }

    if ($metadata)
    {
        Log-Info "Detected that this appliance is running on an Azure VM."
        Set-Service WindowsAzureGuestAgent -StartupType Disabled -Verbose
        Stop-Service WindowsAzureGuestAgent -Force -Verbose
        New-NetFirewallRule -Name BlockAzureIMDS -DisplayName 'Block access to Azure IMDS' -Enabled True -Profile Any -Direction Outbound -Action Block -RemoteAddress 169.254.169.254
        Log-Success "Azure VM prerequisites have been set successfully."
    }
    else
    {
        Log-Info "This appliance is not running on an Azure VM. Skipping Azure VM prerequisites setup."
    }
}

#region - Main
try
{
    $Error.Clear()

    # Validate PowerShell, OS version and user role.
    ValidatePSVersion
	ValidateIsPowerShell64BitProcess
    ValidateOSVersion

    # Check if any of the ASR component is not installed on this machine.
    ValidateRepAppliance("Microsoft Azure Site Recovery Configuration/Process Server")

    # Detect the presets to know what needs to be installed.
    DetectPresets

    # Detect and take user intent to cleanup previous installation if found.
    DetectAndCleanupPreviousInstallation

    # Add the required registry keys.
    AddingRegistryKeys

    # Enable IIS.
    EnableIIS

    # Set trusted hosts to machine.
    SetTrustedHosts

    # Set network config (enable LEDBAT).
    SetNetworkConfig

    ## Increase WSMan Payload Size.
    IncreaseWSManPayloadSize

    # Set prereqs in case the appliance is an Azure VM
    Set-AzureVMPrerequisites

    # Install Discovery, Assessment and MIgration agents based on the scenario .
    switch($global:SelectedFabricType)
    {
        AzureStackHCI ## keep this in case users have scripted using the old name
        {
            $ApplianceJsonFileData.FabricType="AzureStackHCI"

            ## install new dra agent
            InstallMSI -MSIFilePath "$PSScriptRoot\$DraV2MsiName" `
                    -MSIInstallLogName $DraV2MsiLog

            ## install gateway agent
            InstallGatewayService "$PSScriptRoot\$GatewayExeName" ""
        }
        HyperV
        {
            $ApplianceJsonFileData.FabricType="HyperV"
            InstallMSI -MSIFilePath "$PSScriptRoot\$HyperVDiscoveryServiceMSI" `
                -MSIInstallLogName $DiscoveryServiceMSILog
            InstallMSI -MSIFilePath "$PSScriptRoot\$HyperVAssessmentServiceMSI" `
                -MSIInstallLogName $AssessmentServiceMSILog

            # Use new DRA
            ## install new dra agent
            InstallMSI -MSIFilePath "$PSScriptRoot\$DraV2MsiName" -MSIInstallLogName $DraV2MsiLog

            ## install gateway agent
            InstallGatewayService "$PSScriptRoot\$GatewayExeName" ""

            InstallMSI -MSIFilePath "$PSScriptRoot\$SQLServiceMSI" `
                -MSIInstallLogName $SQLServiceMSILog
            InstallMSI -MSIFilePath "$PSScriptRoot\$WebAppMSI" `
                -MSIInstallLogName $WebAppMSILog

            # Install Azure Connected Machine Agent
            InstallMSI -MSIFilePath "$PSScriptRoot\$AzureConnectedMachineAgentMSI" `
                -MSIInstallLogName $AzureConnectedMachineAgentMSILog
        }
        Physical
        {
            $ApplianceJsonFileData.FabricType="Physical"
            InstallMSI -MSIFilePath "$PSScriptRoot\$ServerDiscoveryServiceMSI" `
                -MSIInstallLogName $DiscoveryServiceMSILog
            InstallMSI -MSIFilePath "$PSScriptRoot\$ServerAssessmentServiceMSI" `
                -MSIInstallLogName $AssessmentServiceMSILog
            InstallMSI -MSIFilePath "$PSScriptRoot\$SQLServiceMSI" `
                -MSIInstallLogName $SQLServiceMSILog
            InstallMSI -MSIFilePath "$PSScriptRoot\$WebAppMSI" `
                -MSIInstallLogName $WebAppMSILog

            # Install Azure Connected Machine Agent
            InstallMSI -MSIFilePath "$PSScriptRoot\$AzureConnectedMachineAgentMSI" `
                -MSIInstallLogName $AzureConnectedMachineAgentMSILog
        }
        VMware
        {
            $ApplianceJsonFileData.FabricType="VMwareV2"
            $ApplianceJsonFileData.VddkInstallerFolder="%programfiles%\\VMware\\VMware Virtual Disk Development Kit";

            if ($global:SelectedScaleOut -eq "False")
            {
                InstallMSI -MSIFilePath "$PSScriptRoot\$VMwareDiscoveryServiceMSI" `
                    -MSIInstallLogName $DiscoveryServiceMSILog
                InstallMSI -MSIFilePath "$PSScriptRoot\$VMwareAssessmentServiceMSI" `
                    -MSIInstallLogName $AssessmentServiceMSILog
                InstallMSI -MSIFilePath "$PSScriptRoot\$SQLServiceMSI" `
                    -MSIInstallLogName $SQLServiceMSILog

                InstallMSI -MSIFilePath "$PSScriptRoot\$WebAppMSI" `
                    -MSIInstallLogName $WebAppMSILog
                <#InstallMSI -MSIFilePath "$PSScriptRoot\$AppCompatMSI" `
                    -MSIInstallLogName $AppCompatMSILog -OptionalComponent
                #>

                if ($global:SelectedEnableAzureStackHCITarget -eq "True")
                {
                    # Use new DRA
                    InstallMSI -MSIFilePath "$PSScriptRoot\$DraV2MsiName" `
                        -MSIInstallLogName $DraV2MsiLog
                }
                else
                {
                InstallMSI -MSIFilePath "$PSScriptRoot\$DraMsiName" `
                    -MSIInstallLogName $DraMsiLog
                }
            }
            else
            {
                $ApplianceJsonFileData.ScaleOutCapabilities = "0"
            }

            # Install Azure Connected Machine Agent
            InstallMSI -MSIFilePath "$PSScriptRoot\$AzureConnectedMachineAgentMSI" `
                -MSIInstallLogName $AzureConnectedMachineAgentMSILog

            # LogFilePath needs to be added.
            InstallGatewayService "$PSScriptRoot\$GatewayExeName" ""
        }
        default
        {
            Log-Error "Unexpected Scenario selected:$global:SelectedFabricType. Aborting..."
            Log-Warning "Please retry the script with -Scenario parameter."
            exit -20
        }
    }

    # Install Appliance Configuration Manager
    $ApplianceJsonFileData.Cloud    = $global:SelectedCloud
    $ApplianceJsonFileData.ScaleOut = $global:SelectedScaleOut
    $ApplianceJsonFileData.PrivateEndpointEnabled =$global:SelectedPEEnabled;
    $ApplianceJsonFileData.EnableAzureStackHCITarget = $global:SelectedEnableAzureStackHCITarget;
    CreateJsonFile -JsonFileData $ApplianceJsonFileData -JsonFilePath $ApplianceJsonFilePath
    InstallMSI -MSIFilePath "$PSScriptRoot\$ConfigManagerMSI" -MSIInstallLogName $ConfigManagerMSILog

    # Client SKU has BasicAuthentication disabled by default
    Set-WebConfigurationProperty -Filter '/system.webServer/security/authentication/basicAuthentication' -Name enabled -Value true -PSPath 'IIS:\' -Location "Microsoft Azure Appliance Configuration Manager"
    Set-WebConfigurationProperty -Filter '/system.web/trust' -Name "level" -Value "Full" -PSPath "IIS:\sites\Microsoft Azure Appliance Configuration Manager"

    # Install Agent updater.
    $AutoUpdaterJsonFileData.Cloud  = $global:SelectedCloud
    CreateJsonFile -JsonFileData $AutoUpdaterJsonFileData -JsonFilePath $AutoUpdaterJsonFilePath
    InstallMSI -MSIFilePath "$PSScriptRoot\$AutoUpdaterMSI" -MSIInstallLogName $AutoUpdaterMSILog

    # Custom script for IIS bindings and launch UI.
    CreateApplianceVersionFile

    # Ensure critical services for ConfigManager are in running state.
    StartIISServices

    # Execute WebBinding scripts
    if (-Not (Test-Path -Path "$PSScriptRoot\WebBinding.ps1" -PathType Any))
    {
        Log-Error "Script file not found: `"$PSScriptRoot\WebBinding.ps1`". Aborting..."
        Log-Warning "Please download the package again and retry."
        exit -9
    }
    else
    {
        Log-Info "Running powershell script `"$PSScriptRoot\WebBinding.ps1`"..."
        & "$PSScriptRoot\WebBinding.ps1" | Out-Null
        if ($?)
        {
            Log-Success "[OK]`n"
        }
        else
        {
            Log-Error "Script execution failed. Aborting..."
            Log-Warning "Please download the package again and retry."
            exit -9
        }
    }

    # Execute SetRegistryForTrustedSites scripts
    if (-Not (Test-Path -Path "$PSScriptRoot\SetRegistryForTrustedSites.ps1" -PathType Any))
    {
        Log-Error "Script file not found: `"$PSScriptRoot\SetRegistryForTrustedSites.ps1`". Aborting..."
        Log-Warning "Please download the package again and retry."
        exit -9
    }
    else
    {
        Log-Info "Running powershell script `"$PSScriptRoot\SetRegistryForTrustedSites.ps1`" with argument '-LaunchApplication $false'..."
        & "$PSScriptRoot\SetRegistryForTrustedSites.ps1" -LaunchApplication $false | Out-Null

        if ($?)
        {
            Log-Success "[OK]`n"
        }
        else
        {
            Log-Error "Script execution failed. Aborting..."
            Log-Warning "Please download the installer package again and retry."
            exit -9
        }
    }

    # Install Edge Browser and uninstall IE
    InstallEdgeBrowser
    UninstallInternetExplorer

    if ($global:WarningCount -gt 0)
    {
        Log-Success "Installation completed with warning(s)."
        Log-Warning "Please review the $global:WarningCount warning(s) hit during script execution and take manual corrective action as suggested in the warning(s) before using Azure Migrate appliance configuration manager."
        Log-Info "You can scroll up to view the warning(s). The warning messages appear in YELLOW coloured text."
        start-sleep -Seconds 10
    }
    else
    {
        Log-Success "Installation completed successfully. Launching Azure Migrate appliance configuration manager to start the onboarding process..."
        Start $DefaultURL
    }

    Log-InfoHighLight "`nYou may use the shortcut placed on the desktop to manually launch `"Azure Migrate appliance configuration manager`"."
}
catch
{
    Log-Error "`n[Script execution failed with error] $_"
    Log-Error "[Exception caught] $_.Exception"
    Log-Warning "Retry executing the script after resolving the issue(s) or contact Microsoft Support."
    exit -1
}

#endregion
# SIG # Begin signature block
# MIIoKQYJKoZIhvcNAQcCoIIoGjCCKBYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDUxBnAruTSBiX1
# IbYvubGX96nuYdP17MSwryKM2qSS2aCCDXYwggX0MIID3KADAgECAhMzAAAEhV6Z
# 7A5ZL83XAAAAAASFMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjUwNjE5MTgyMTM3WhcNMjYwNjE3MTgyMTM3WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDASkh1cpvuUqfbqxele7LCSHEamVNBfFE4uY1FkGsAdUF/vnjpE1dnAD9vMOqy
# 5ZO49ILhP4jiP/P2Pn9ao+5TDtKmcQ+pZdzbG7t43yRXJC3nXvTGQroodPi9USQi
# 9rI+0gwuXRKBII7L+k3kMkKLmFrsWUjzgXVCLYa6ZH7BCALAcJWZTwWPoiT4HpqQ
# hJcYLB7pfetAVCeBEVZD8itKQ6QA5/LQR+9X6dlSj4Vxta4JnpxvgSrkjXCz+tlJ
# 67ABZ551lw23RWU1uyfgCfEFhBfiyPR2WSjskPl9ap6qrf8fNQ1sGYun2p4JdXxe
# UAKf1hVa/3TQXjvPTiRXCnJPAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUuCZyGiCuLYE0aU7j5TFqY05kko0w
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzUwNTM1OTAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBACjmqAp2Ci4sTHZci+qk
# tEAKsFk5HNVGKyWR2rFGXsd7cggZ04H5U4SV0fAL6fOE9dLvt4I7HBHLhpGdE5Uj
# Ly4NxLTG2bDAkeAVmxmd2uKWVGKym1aarDxXfv3GCN4mRX+Pn4c+py3S/6Kkt5eS
# DAIIsrzKw3Kh2SW1hCwXX/k1v4b+NH1Fjl+i/xPJspXCFuZB4aC5FLT5fgbRKqns
# WeAdn8DsrYQhT3QXLt6Nv3/dMzv7G/Cdpbdcoul8FYl+t3dmXM+SIClC3l2ae0wO
# lNrQ42yQEycuPU5OoqLT85jsZ7+4CaScfFINlO7l7Y7r/xauqHbSPQ1r3oIC+e71
# 5s2G3ClZa3y99aYx2lnXYe1srcrIx8NAXTViiypXVn9ZGmEkfNcfDiqGQwkml5z9
# nm3pWiBZ69adaBBbAFEjyJG4y0a76bel/4sDCVvaZzLM3TFbxVO9BQrjZRtbJZbk
# C3XArpLqZSfx53SuYdddxPX8pvcqFuEu8wcUeD05t9xNbJ4TtdAECJlEi0vvBxlm
# M5tzFXy2qZeqPMXHSQYqPgZ9jvScZ6NwznFD0+33kbzyhOSz/WuGbAu4cHZG8gKn
# lQVT4uA2Diex9DMs2WHiokNknYlLoUeWXW1QrJLpqO82TLyKTbBM/oZHAdIc0kzo
# STro9b3+vjn2809D0+SOOCVZMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCGgkwghoFAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAASFXpnsDlkvzdcAAAAABIUwDQYJYIZIAWUDBAIB
# BQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEILLRS3S9uOEa0LBpZ4eVzb5W
# 1UQ4ZQ0tMQtesv0P13XEMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
# BQAEggEAWwwsPZvD6KwbA2K1wVgRtc/oRceogiNZE8Wi9dNV4kI6KDCwlQOfclTp
# gvZgRnSAc+K5CkERFTnT9RjWwcK2SRlsC1/mg943CUy8fWgWyF2dzU5Ml2depPlx
# zqu32nvMhE2X4l+RvIpRzxj5zp8gk/4LJc5iEjEu/kPu1I2yehIeCwoloaLzkwvA
# sKxCfcwqQP5Y5RqUWOMtDc7mmN2PpUWxNPlUQkcNV2+SzuEfQogkFVUFN5CNGHpj
# xvIV0W5VPRbu5J5+m5IdsySL/dovcNthXT1KuMYOnWyq+vrL4vfiWnnsuNVAhGR4
# Mixu9uRP44CE5LKk8WqTeyxrMgyhwqGCF5MwghePBgorBgEEAYI3AwMBMYIXfzCC
# F3sGCSqGSIb3DQEHAqCCF2wwghdoAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFRBgsq
# hkiG9w0BCRABBKCCAUAEggE8MIIBOAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFl
# AwQCAQUABCDYebLdTWd4WZcWJmx73jDdxMt9pIebcNFt+Rik9Aw7UgIGaSc9mmgR
# GBIyMDI1MTIwOTExMTczNS45MlowBIACAfSggdGkgc4wgcsxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVy
# aWNhIE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjozMzAzLTA1
# RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCC
# EeowggcgMIIFCKADAgECAhMzAAACD1eaRxRA5kbmAAEAAAIPMA0GCSqGSIb3DQEB
# CwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI1MDEzMDE5NDMw
# NFoXDTI2MDQyMjE5NDMwNFowgcsxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMx
# JzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjozMzAzLTA1RTAtRDk0NzElMCMGA1UE
# AxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCAiIwDQYJKoZIhvcNAQEB
# BQADggIPADCCAgoCggIBAKXoNO6vF/rqjvcbQDbIqjX+di8hMFCx3nQXnZJDOjZx
# Ku34QMQUIOVLFnNYkPu6NDVnV0xsxPpiErslS/DFD4uRBe/aT/e/fHDzEnaaFe7B
# tP6zVY4vT72D0A4QAAzpYaMLMj8tmrf+3MevnqKf9n76j/aygaHIaEowPBaXgngv
# UWfyd22gzVIGJs92qbCY9ekH1C1o/5MI4LW8BoZA52ypdDwB2UrpW6T3Jb23LtLS
# RE/WdeQWx4zfc3MG7/+5tqgkdvVx5g9nhTgQ5cEeL/aDT1ZEv1BYi0eM8YliO4nR
# yTKs4bWSx8BlY/4G7w9cCrizUFr+H+deFcDC7FOGm9oVvhPRs6Ng7+HYs9Ft0Mxw
# x9L1luGrXSFc/pkUdHRFEn6uvkDwgP2XRSChS7+A28KocIyjDP3u52jt5Y4MDstp
# W/zUUcdjDdfkNJNSonqnA/7/SXFq3FqNtIaybbrvOpU2y7NSgXYXM8z5hQjCI6mB
# C++NggGQH4pTBl/a9Eg9aaEATNZkAZOjH/S+Ph4eDHARH1+lOFyxtkZLHHScvngf
# P4vfoonIRWKj6glW9TGbvlgQRJpOHVGcvQOWz3WwHDqa8qs7Y740JtS1/H5xBdhL
# QlxZl5/zXQFb0Gf94i+jDcpzHR1W6oN8hZ9buKZ5MsAr1AAST6hkInNRRO+GHaFh
# AgMBAAGjggFJMIIBRTAdBgNVHQ4EFgQUmdQxDY63ICEtH8wPaq0n2UpE/1kwHwYD
# VR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYDVR0fBFgwVjBUoFKgUIZO
# aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0JTIw
# VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3JsMGwGCCsGAQUFBwEBBGAwXjBc
# BggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0
# cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcnQwDAYD
# VR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8EBAMC
# B4AwDQYJKoZIhvcNAQELBQADggIBAFOjBujVtQTt9dPL65b2bnyoYRdEEZUwRCIU
# R9K6LV+E3uNL6RKI3RJHkqXcC5Xj3E7GAej34Yid7kymDmfg1Lk9bydYhYaP/yOQ
# Tel0llK8BlqtcPiXjeIw3EOF0FmpUKQBhx0VVmfF3L7bkxFjpF9obCSKeOdg0UDo
# Ngv/VzHDphrixfJXsWA90ybFWl9+c8QMW/iZxXHeO89mh3uCqINxQdvJXWBo0Pc9
# 6PInUwZ8FhsBDGzKctfUVSxYvAqw09EmPKfCXMFP85BvGfOSMuJuLiHh07Bw34fi
# bIO1RKdir1d/hi8WVn6Ymzli3HhT0lULJb9YRG0gSJ5O9NGC8BiP/gyHUXYSV/xx
# 0guDOL17Oph5/F2wEPxWLHfnIwLktOcNSjJVW6VR54MAljz7pgFu1ci3LimEiSKG
# IgezJZXFbZgYboDpRZ6e7BjrP2gE428weWq0PftnIufSHWQKSSnmRwgiEy2nMRw+
# R+qWRsNWiAyhbLzTG6XG3rg/j7VgjORGG3fNM76Ms427WmYG37wRSHsNVy3/fe25
# bk05LHnqNdDVN050UGmBxbwe8mKLyyZDVNA/jYc0gogljlqIyQr0zYejFitDLYyg
# c04/JKw7OveV7/hIN1fru6hsaRQ16uUkrMqlNHllTRJ40C7mgLINvqB21OJo3nSU
# ILqbjixeMIIHcTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG
# 9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
# BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEy
# MDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIw
# MTAwHhcNMjEwOTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBQQ0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIB
# AOThpkzntHIhC3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az
# /1xPx2b3lVNxWuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V2
# 9YZQ3MFEyHFcUTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oa
# ezOtgFt+jBAcnVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkN
# yjYtcI4xyDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7K
# MtXAhjBcTyziYrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRf
# NN0Sidb9pSB9fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SU
# HDSCD/AQ8rdHGO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoY
# WmEBc8pnol7XKHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5
# C4lh8zYGNRiER9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8
# FdsaN8cIFRg/eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TAS
# BgkrBgEEAYI3FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1
# Kc8Q/y8E7jAdBgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUw
# UzBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoG
# CCsGAQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIB
# hjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fO
# mhjEMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9w
# a2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggr
# BgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3
# DQEBCwUAA4ICAQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEz
# tTnXwnE2P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJW
# AAOwBb6J6Gngugnue99qb74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G
# 82jfZfakVqr3lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/Aye
# ixmJ5/ALaoHCgRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI9
# 5ko+ZjtPu4b6MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1j
# dEgssU5HLcEUBHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZ
# KCS6OEuabvshVGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xB
# Zj1p/cvBQUl+fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuP
# Ntq6TPmb/wrpNPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvp
# e784cETRkPHIqzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCA00w
# ggI1AgEBMIH5oYHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScw
# JQYDVQQLEx5uU2hpZWxkIFRTUyBFU046MzMwMy0wNUUwLUQ5NDcxJTAjBgNVBAMT
# HE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVAF60
# jOPYL8yR2IjTcTI2wK1I4x1aoIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# UENBIDIwMTAwDQYJKoZIhvcNAQELBQACBQDs4jVaMCIYDzIwMjUxMjA5MDU0MjUw
# WhgPMjAyNTEyMTAwNTQyNTBaMHQwOgYKKwYBBAGEWQoEATEsMCowCgIFAOziNVoC
# AQAwBwIBAAICIGEwBwIBAAICElQwCgIFAOzjhtoCAQAwNgYKKwYBBAGEWQoEAjEo
# MCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG
# 9w0BAQsFAAOCAQEAlygNQB7IWKWl5bEj+Z+t0r350fHhDMKjousOtQT633GrCxwX
# l8TF5ihnJnAKURveNl5rQC0DzAoG2BbzONFabSMumL50WW28R3hMFlnmFIUPEOGB
# FbDNMKcWj+nmoKoucUyXnu2fRvuPXAaeFJSUNK5i7D3fWK2VabB2Cb20krRz0+FY
# WNoM4kvDy+4qua3+WdfRMOzQugMyAnCuz/v30LwAhVfGN8g7cjxh4jqUN4JiFi8q
# pdY/FQsWihPU88jH1M4eqv9nCYQk691rslcG514y9KQNd/iEgc/ag/1qkFvV1ZBP
# tiGYFjLxQ1GS0TM83M/8gi3vwhFCvJMyH0LP7DGCBA0wggQJAgEBMIGTMHwxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jv
# c29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACD1eaRxRA5kbmAAEAAAIPMA0G
# CWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJ
# KoZIhvcNAQkEMSIEIL5g9bQcqcjsdMFThjJsaxcDk4Wy8PiSWtQRkPuetY1NMIH6
# BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQg3Ud3lSYqebsVbvE/eeIax8cm3jFH
# xe74zGBddzSKqfgwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAx
# MAITMwAAAg9XmkcUQOZG5gABAAACDzAiBCD5j6ZdOMyZFgZtXLd9tQGc2mm09UmT
# MLAixhc9hytRYjANBgkqhkiG9w0BAQsFAASCAgBxJDmSq7AoUg2D7djq/01Othqy
# PR+68H8JH3P4PZSlaYCrpE6/VbnBYV/78XBS25no17t/F+NyBoy7jXMkvbZv1Izi
# /E7AdUg28ZT6bE4csTbnddaDhsmvEQMo4wtWCcZZTz0rdHBXuCG5D4k86kSW53jp
# ALmuB23YwlRZ0fzFQqBHA2/l5D5zI1YOHgyR22DGYJCvXTAOryq6zJkv90XipbWz
# or/IIcw4eEWDU7+sMcj+SCtHOqhqt4nbBSzQGS3H11Uvd2oQGBpkrGGXaet4mawx
# Ji2ryPBfGdKoeIK3Nk+A0ZGVxbUMjJ6vHqoB6ae1D9TNy0xxMv4H3SFWdnnLGJwA
# bQdA+jg5A5O0RWNHK+Wrp9L6m9Qn1HdNpQjYFJW/9jfnBURF8WMzFNIATWfUkb4j
# qOTckZ7oVuQhWfMBlNWISchInNCAU055LAhfC7mGjIkuasLg4ntp5AWpXjI462nj
# hceWoJAfkbk0JAJbvMC2Wps09U6KugcztF7qwnZNXsQwsWQLWmQmcffhp/Oyau2y
# V8ser2JMTAbg53Or38jZTCgzJAyveWetuIQAZSOCFvugCMHgd6QGhelfLBNtwrMt
# dAtkHkKgsKs1MqcUQJ+RAHsVPQvaoDCuvzBQueAZBvXTS8O23+Z/EFQZPGXyHjew
# M1vnACV2IUbTEoLYbg==
# SIG # End signature block
