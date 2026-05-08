# DCS AccMod - MFD Rendering System Setup Script
# This script installs all required software and configures virtual monitors for MFD capture

param(
    [switch]$SkipVDDInstall,
    [switch]$ConfigureOnly,
    [int]$NumMFDs = 2,
    [int]$MFDResolution = 800
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DCS AccMod MFD Rendering Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script requires Administrator privileges" -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator and try again" -ForegroundColor Yellow
    exit 1
}

# Function to check if VDD is installed
function Test-VDDInstalled {
    return $null -ne (Get-VDDInstallInfo)
}

# Function to check if winget is available
function Test-WingetAvailable {
    try {
        $null = Get-Command winget -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Get-VDDInstallInfo {
    $candidateDirs = @(
        "C:\VirtualDisplayDriver",
        "C:\Program Files\VirtualDisplayDriver",
        "C:\Program Files\Virtual Display Driver"
    )

    $wingetPackagesRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path $wingetPackagesRoot) {
        $candidateDirs += Get-ChildItem -Path $wingetPackagesRoot -Directory -Filter "VirtualDrivers.Virtual-Display-Driver*" -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
    }

    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($uninstallPath in $uninstallPaths) {
        $entries = Get-ItemProperty -Path $uninstallPath -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -like "*Virtual Display Driver*" -or
                $_.DisplayName -like "*Virtual Driver Control*"
            }

        foreach ($entry in $entries) {
            foreach ($locationHint in @($entry.InstallLocation, $entry.DisplayIcon, $entry.UninstallString)) {
                if (-not $locationHint) {
                    continue
                }

                $candidate = $locationHint.Trim('"')
                if ($candidate -match '\.exe(,.*)?$') {
                    $candidate = Split-Path $candidate -Parent
                }

                if ($candidate) {
                    $candidateDirs += $candidate
                }
            }
        }
    }

    foreach ($dir in ($candidateDirs | Where-Object { $_ } | Select-Object -Unique)) {
        if (-not (Test-Path $dir)) {
            continue
        }

        $settingsPath = Join-Path $dir "vdd_settings.xml"
        $vdcPath = Join-Path $dir "VDC.exe"
        if (-not (Test-Path $vdcPath)) {
            $vdcPath = Get-ChildItem -Path $dir -Filter "*.exe" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^VDC\.exe$|Virtual.*Control' } |
                Select-Object -First 1 -ExpandProperty FullName
        }

        return [PSCustomObject]@{
            InstallDir = $dir
            SettingsPath = $settingsPath
            SettingsExists = Test-Path $settingsPath
            VdcPath = $vdcPath
        }
    }

    return $null
}

function Get-OrCreateXmlChildNode {
    param(
        [Parameter(Mandatory = $true)]
        [xml]$Document,
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlNode]$Parent,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $node = $Parent.SelectSingleNode($Name)
    if (-not $node) {
        $node = $Document.CreateElement($Name)
        $null = $Parent.AppendChild($node)
    }

    return $node
}

function Set-XmlChildInnerText {
    param(
        [Parameter(Mandatory = $true)]
        [xml]$Document,
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlNode]$Parent,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $node = Get-OrCreateXmlChildNode -Document $Document -Parent $Parent -Name $Name
    $node.InnerText = $Value
    return $node
}

function Save-PrettyXmlFile {
    param(
        [Parameter(Mandatory = $true)]
        [xml]$Document,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $settings.OmitXmlDeclaration = $false

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $Document.Save($writer)
    } finally {
        $writer.Dispose()
    }
}

function Set-VDDSettingsXml {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SettingsPath,
        [Parameter(Mandatory = $true)]
        [int]$MonitorCount,
        [Parameter(Mandatory = $true)]
        [int]$Resolution,
        [int]$RefreshRate = 60
    )

    if (Test-Path $SettingsPath) {
        [xml]$xml = Get-Content -Path $SettingsPath -Raw
    } else {
        $xml = New-Object System.Xml.XmlDocument
        $xml.LoadXml("<?xml version='1.0' encoding='utf-8'?><vdd_settings></vdd_settings>")
    }

    $root = $xml.SelectSingleNode('/vdd_settings')
    if (-not $root) {
        throw "Invalid VDD settings XML: missing <vdd_settings> root element"
    }

    $monitorsNode = Get-OrCreateXmlChildNode -Document $xml -Parent $root -Name 'monitors'
    $null = Set-XmlChildInnerText -Document $xml -Parent $monitorsNode -Name 'count' -Value ([string]$MonitorCount)

    $gpuNode = Get-OrCreateXmlChildNode -Document $xml -Parent $root -Name 'gpu'
    $gpuFriendlyNameNode = Get-OrCreateXmlChildNode -Document $xml -Parent $gpuNode -Name 'friendlyname'
    if ([string]::IsNullOrWhiteSpace($gpuFriendlyNameNode.InnerText)) {
        $gpuFriendlyNameNode.InnerText = 'default'
    }

    $globalNode = Get-OrCreateXmlChildNode -Document $xml -Parent $root -Name 'global'
    $refreshRateExists = $false
    foreach ($refreshNode in $globalNode.SelectNodes('g_refresh_rate')) {
        if ($refreshNode.InnerText -eq [string]$RefreshRate) {
            $refreshRateExists = $true
            break
        }
    }
    if (-not $refreshRateExists) {
        $refreshNode = $xml.CreateElement('g_refresh_rate')
        $refreshNode.InnerText = [string]$RefreshRate
        $null = $globalNode.AppendChild($refreshNode)
    }

    $resolutionsNode = Get-OrCreateXmlChildNode -Document $xml -Parent $root -Name 'resolutions'
    $requestedResolutionExists = $false
    foreach ($resolutionNode in $resolutionsNode.SelectNodes('resolution')) {
        $widthNode = $resolutionNode.SelectSingleNode('width')
        $heightNode = $resolutionNode.SelectSingleNode('height')
        $refreshNode = $resolutionNode.SelectSingleNode('refresh_rate')

        if ($widthNode -and $heightNode -and $refreshNode -and
            $widthNode.InnerText -eq [string]$Resolution -and
            $heightNode.InnerText -eq [string]$Resolution -and
            $refreshNode.InnerText -eq [string]$RefreshRate) {
            $requestedResolutionExists = $true
            break
        }
    }

    if (-not $requestedResolutionExists) {
        $resolutionNode = $xml.CreateElement('resolution')
        $null = Set-XmlChildInnerText -Document $xml -Parent $resolutionNode -Name 'width' -Value ([string]$Resolution)
        $null = Set-XmlChildInnerText -Document $xml -Parent $resolutionNode -Name 'height' -Value ([string]$Resolution)
        $null = Set-XmlChildInnerText -Document $xml -Parent $resolutionNode -Name 'refresh_rate' -Value ([string]$RefreshRate)
        $null = $resolutionsNode.AppendChild($resolutionNode)
    }

    $optionsNode = Get-OrCreateXmlChildNode -Document $xml -Parent $root -Name 'options'
    $defaultOptions = [ordered]@{
        CustomEdid = 'false'
        PreventSpoof = 'false'
        EdidCeaOverride = 'false'
        HardwareCursor = 'true'
        SDR10bit = 'false'
        HDRPlus = 'false'
        logging = 'false'
        debuglogging = 'false'
    }

    foreach ($optionName in $defaultOptions.Keys) {
        $optionNode = Get-OrCreateXmlChildNode -Document $xml -Parent $optionsNode -Name $optionName
        if ([string]::IsNullOrWhiteSpace($optionNode.InnerText)) {
            $optionNode.InnerText = $defaultOptions[$optionName]
        }
    }

    $settingsDir = Split-Path $SettingsPath -Parent
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }

    Save-PrettyXmlFile -Document $xml -Path $SettingsPath

    [PSCustomObject]@{
        SettingsPath = $SettingsPath
        MonitorCount = $MonitorCount
        Resolution = $Resolution
        RefreshRate = $RefreshRate
    }
}

function Restart-VDDDisplayAdapter {
    $result = [PSCustomObject]@{
        Attempted = $false
        Applied = $false
        Message = $null
    }

    $vddDevice = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FriendlyName -like '*Virtual Display Driver*' -or
            $_.FriendlyName -like '*Virtual Display Driver Adapter*'
        } |
        Select-Object -First 1

    if (-not $vddDevice) {
        $result.Message = 'VDD adapter was not detected in PnP. Use VDC "Reload Driver" or reboot to apply the new XML settings.'
        return $result
    }

    try {
        $result.Attempted = $true
        Disable-PnpDevice -InstanceId $vddDevice.InstanceId -Confirm:$false -ErrorAction Stop | Out-Null
        Enable-PnpDevice -InstanceId $vddDevice.InstanceId -Confirm:$false -ErrorAction Stop | Out-Null
        $result.Applied = $true
        $result.Message = "Reloaded VDD adapter: $($vddDevice.FriendlyName)"
        return $result
    } catch {
        $result.Message = "VDD XML was updated, but automatic adapter reload failed: $($_.Exception.Message)"
        return $result
    }
}

function Get-DCSProfileInfo {
    $savedGamesRoot = Join-Path $env:USERPROFILE "Saved Games"
    if (-not (Test-Path $savedGamesRoot)) {
        return $null
    }

    $candidates = Get-ChildItem -Path $savedGamesRoot -Directory -Filter "DCS*" |
        Where-Object { Test-Path (Join-Path $_.FullName "Config\options.lua") } |
        Sort-Object {
            (Get-Item (Join-Path $_.FullName "Config\options.lua")).LastWriteTimeUtc
        } -Descending

    if (-not $candidates -or $candidates.Count -eq 0) {
        return $null
    }

    $selected = $candidates[0]
    [PSCustomObject]@{
        ProfileName = $selected.Name
        BasePath = $selected.FullName
        OptionsPath = Join-Path $selected.FullName "Config\options.lua"
        MonitorSetupDir = Join-Path $selected.FullName "Config\MonitorSetup"
    }
}

function Get-LuaOptionValue {
    param(
        [string]$Content,
        [string]$Key,
        [ValidateSet('String', 'Number')]
        [string]$ValueType
    )

    if ($ValueType -eq 'String') {
        $pattern = '(?m)^\s*\["' + [regex]::Escape($Key) + '"\]\s*=\s*"([^"]+)"'
    } else {
        $pattern = '(?m)^\s*\["' + [regex]::Escape($Key) + '"\]\s*=\s*([0-9.]+)'
    }

    $match = [regex]::Match($Content, $pattern)
    if ($match.Success) {
        return $match.Groups[1].Value
    }

    return $null
}

function Get-DCSMonitorSetupInfo {
    param(
        [Parameter(Mandatory = $true)]
        $ProfileInfo
    )

    if (-not (Test-Path $ProfileInfo.OptionsPath)) {
        return $null
    }

    $content = Get-Content -Path $ProfileInfo.OptionsPath -Raw
    $monitorSetupName = Get-LuaOptionValue -Content $content -Key "multiMonitorSetup" -ValueType String
    $width = Get-LuaOptionValue -Content $content -Key "width" -ValueType Number
    $height = Get-LuaOptionValue -Content $content -Key "height" -ValueType Number
    $monitorSetupPath = $null

    if ($monitorSetupName -and $monitorSetupName -ne "1camera") {
        $candidatePath = Join-Path $ProfileInfo.MonitorSetupDir ("{0}.lua" -f $monitorSetupName)
        if (Test-Path $candidatePath) {
            $monitorSetupPath = $candidatePath
        }
    }

    [PSCustomObject]@{
        MonitorSetupName = if ($monitorSetupName) { $monitorSetupName } else { "1camera" }
        Width = if ($width) { [int][double]$width } else { $null }
        Height = if ($height) { [int][double]$height } else { $null }
        MonitorSetupPath = $monitorSetupPath
    }
}

function New-MFDAutoMonitorSetup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplatePath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,
        [Parameter(Mandatory = $true)]
        [int]$PrimaryWidth,
        [Parameter(Mandatory = $true)]
        [int]$PrimaryHeight,
        [Parameter(Mandatory = $true)]
        [int]$MFDResolution
    )

    $leftMfdX = $PrimaryWidth
    $rightMfdX = $PrimaryWidth + $MFDResolution
    $content = Get-Content -Path $TemplatePath -Raw

    $content = $content.Replace(
        '            width = 1920,           -- Full HD width (adjust to your monitor)',
        ('            width = {0},           -- Full HD width (adjust to your monitor)' -f $PrimaryWidth)
    )
    $content = $content.Replace(
        '            height = 1080,          -- Full HD height (adjust to your monitor)',
        ('            height = {0},          -- Full HD height (adjust to your monitor)' -f $PrimaryHeight)
    )
    $content = $content.Replace(
        '            x = 1920,               -- X position of virtual monitor (CHANGE THIS)',
        ('            x = {0},               -- X position of virtual monitor (CHANGE THIS)' -f $leftMfdX)
    )
    $content = $content.Replace(
        '            x = 2720,               -- X position of virtual monitor (CHANGE THIS)',
        ('            x = {0},               -- X position of virtual monitor (CHANGE THIS)' -f $rightMfdX)
    )

    Set-Content -Path $DestinationPath -Value $content -Encoding UTF8

    [PSCustomObject]@{
        Path = $DestinationPath
        LeftMfdX = $leftMfdX
        RightMfdX = $rightMfdX
    }
}

# Phase 1: Install Virtual Display Driver
if (-not $ConfigureOnly) {
    Write-Host "[1/4] Checking Virtual Display Driver..." -ForegroundColor Yellow
    
    if (Test-VDDInstalled) {
        Write-Host "  Virtual Display Driver already installed" -ForegroundColor Green
    } elseif ($SkipVDDInstall) {
        Write-Host "  Skipping VDD installation (--SkipVDDInstall flag set)" -ForegroundColor Yellow
    } else {
        Write-Host "  Installing Virtual Display Driver..." -ForegroundColor Yellow
        
        if (Test-WingetAvailable) {
            Write-Host "  Using winget to install VDD..." -ForegroundColor Cyan
            try {
                winget install --id=VirtualDrivers.Virtual-Display-Driver -e --silent --accept-package-agreements --accept-source-agreements
                Write-Host "  VDD installed successfully" -ForegroundColor Green
            } catch {
                Write-Host "  Winget installation failed: $_" -ForegroundColor Red
                Write-Host "  Please install manually from: https://github.com/VirtualDrivers/Virtual-Display-Driver/releases" -ForegroundColor Yellow
                exit 1
            }
        } else {
            Write-Host "  ERROR: winget not found" -ForegroundColor Red
            Write-Host "  Please install Virtual Display Driver manually from:" -ForegroundColor Yellow
            Write-Host "  https://github.com/VirtualDrivers/Virtual-Display-Driver/releases" -ForegroundColor Yellow
            Write-Host "  Or install winget from Microsoft Store (App Installer)" -ForegroundColor Yellow
            exit 1
        }
    }
} else {
    Write-Host "[1/4] Skipping installation (ConfigureOnly mode)" -ForegroundColor Yellow
}

# Phase 2: Check dependencies
Write-Host ""
Write-Host "[2/4] Checking dependencies..." -ForegroundColor Yellow

$vcRedistInstalled = Test-Path "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64"
if ($vcRedistInstalled) {
    Write-Host "  Visual C++ Redistributable: OK" -ForegroundColor Green
} else {
    Write-Host "  Visual C++ Redistributable: MISSING" -ForegroundColor Red
    Write-Host "  Download from: https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor Yellow
    $install = Read-Host "  Download and install now? (y/n)"
    if ($install -eq 'y') {
        $vcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
        $vcRedistPath = "$env:TEMP\vc_redist.x64.exe"
        Write-Host "  Downloading..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $vcRedistUrl -OutFile $vcRedistPath
        Write-Host "  Installing..." -ForegroundColor Cyan
        Start-Process -FilePath $vcRedistPath -ArgumentList "/install", "/quiet", "/norestart" -Wait
        Write-Host "  Installation complete" -ForegroundColor Green
    }
}

# Phase 3: Configure virtual monitors
Write-Host ""
Write-Host "[3/4] Configuring virtual monitors for MFD capture..." -ForegroundColor Yellow

$vddInstallInfo = Get-VDDInstallInfo
$vddSettingsPath = if ($vddInstallInfo) { $vddInstallInfo.SettingsPath } else { $null }
$vddConfigResult = $null
$vddApplyResult = $null

if (-not $vddInstallInfo) {
    Write-Host "  WARNING: Virtual Display Driver installation folder was not found" -ForegroundColor Yellow
    Write-Host "  Skipping automatic monitor configuration" -ForegroundColor Yellow
    Write-Host "  Install VDD first, then rerun this script to generate vdd_settings.xml automatically" -ForegroundColor Yellow
} else {
    Write-Host "  VDD installation found" -ForegroundColor Green
    Write-Host "  Install directory: $($vddInstallInfo.InstallDir)" -ForegroundColor Cyan
    Write-Host "  Writing VDD monitor config for $NumMFDs display(s) at ${MFDResolution}x${MFDResolution}@60Hz" -ForegroundColor Cyan

    try {
        $vddConfigResult = Set-VDDSettingsXml -SettingsPath $vddInstallInfo.SettingsPath -MonitorCount $NumMFDs -Resolution $MFDResolution -RefreshRate 60
        Write-Host "  Updated: $($vddConfigResult.SettingsPath)" -ForegroundColor Green
        Write-Host "  Requested VDD monitor count: $($vddConfigResult.MonitorCount)" -ForegroundColor Cyan
        Write-Host "  Requested VDD resolution: $($vddConfigResult.Resolution)x$($vddConfigResult.Resolution)" -ForegroundColor Cyan

        $vddApplyResult = Restart-VDDDisplayAdapter
        if ($vddApplyResult.Applied) {
            Write-Host "  $($vddApplyResult.Message)" -ForegroundColor Green
        } else {
            Write-Host "  $($vddApplyResult.Message)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  Failed to write VDD settings: $($_.Exception.Message)" -ForegroundColor Red
    }

    if ($vddInstallInfo.VdcPath) {
        Write-Host "" 
        Write-Host "  Advanced/manual VDD control is still available via:" -ForegroundColor Yellow
        Write-Host "    $($vddInstallInfo.VdcPath)" -ForegroundColor Cyan

        $openVDC = Read-Host "  Open Virtual Driver Control now? (y/n)"
        if ($openVDC -eq 'y') {
            Start-Process $vddInstallInfo.VdcPath
            Write-Host "  Launched VDC" -ForegroundColor Green
        }
    }
}

# Phase 4: Create DCS MonitorSetup configuration
Write-Host ""
Write-Host "[4/4] Creating DCS MonitorSetup configuration..." -ForegroundColor Yellow

$dcsProfile = Get-DCSProfileInfo
$dcsMonitorInfo = $null

if ($dcsProfile) {
    $dcsConfigBase = $dcsProfile.BasePath
    $monitorSetupDir = $dcsProfile.MonitorSetupDir
    $dcsMonitorInfo = Get-DCSMonitorSetupInfo -ProfileInfo $dcsProfile
} else {
    $dcsConfigBase = "$env:USERPROFILE\Saved Games\DCS"
    $monitorSetupDir = "$dcsConfigBase\Config\MonitorSetup"
}

$exampleSetupPath = ".\examples\MonitorSetup_MFD_Example.lua"
$generatedSetupPath = $null

if (-not (Test-Path $dcsConfigBase)) {
    Write-Host "  DCS Saved Games folder not found at $dcsConfigBase" -ForegroundColor Yellow
    Write-Host "  Skipping MonitorSetup configuration" -ForegroundColor Yellow
} else {
    Write-Host "  DCS Saved Games folder found" -ForegroundColor Green
    if ($dcsProfile) {
        Write-Host "  Active DCS profile: $($dcsProfile.ProfileName)" -ForegroundColor Cyan
    }

    if ($dcsMonitorInfo) {
        Write-Host "  Current monitor preset: $($dcsMonitorInfo.MonitorSetupName)" -ForegroundColor Cyan
        if ($dcsMonitorInfo.Width -and $dcsMonitorInfo.Height) {
            Write-Host "  Current desktop size from options.lua: $($dcsMonitorInfo.Width)x$($dcsMonitorInfo.Height)" -ForegroundColor Cyan
        }

        if ($dcsMonitorInfo.MonitorSetupPath) {
            Write-Host "  Active custom MonitorSetup file: $($dcsMonitorInfo.MonitorSetupPath)" -ForegroundColor Green
        } elseif ($dcsMonitorInfo.MonitorSetupName -ne "1camera") {
            Write-Host "  Active preset file not found under $monitorSetupDir" -ForegroundColor Yellow
        } else {
            Write-Host "  DCS is currently using the default single-camera preset" -ForegroundColor Yellow
        }
    }
    
    if (-not (Test-Path $monitorSetupDir)) {
        Write-Host "  Creating MonitorSetup directory..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $monitorSetupDir -Force | Out-Null
    }
    
    if (Test-Path $exampleSetupPath) {
        Write-Host "  Example MonitorSetup file found" -ForegroundColor Green
        Write-Host "  Location: $exampleSetupPath" -ForegroundColor Cyan
        if ($dcsMonitorInfo -and $dcsMonitorInfo.Width -and $dcsMonitorInfo.Height) {
            $generatedSetup = New-MFDAutoMonitorSetup `
                -TemplatePath $exampleSetupPath `
                -DestinationPath (Join-Path $monitorSetupDir "AccMod_MFD_Auto.lua") `
                -PrimaryWidth $dcsMonitorInfo.Width `
                -PrimaryHeight $dcsMonitorInfo.Height `
                -MFDResolution $MFDResolution
            $generatedSetupPath = $generatedSetup.Path

            Write-Host "  Generated: $generatedSetupPath" -ForegroundColor Green
            Write-Host "  Based on Saved Games monitor data, suggested MFD X positions are $($generatedSetup.LeftMfdX) and $($generatedSetup.RightMfdX)" -ForegroundColor Cyan
        }
        Write-Host ""
        Write-Host "  To use MFD export in DCS:" -ForegroundColor Yellow
        if ($generatedSetupPath) {
            Write-Host "    1. Start from: $generatedSetupPath" -ForegroundColor Cyan
            Write-Host "    2. Rename it to match your aircraft (e.g., FA-18C.lua)" -ForegroundColor Cyan
            Write-Host "    3. Adjust the generated MFD coordinates if your virtual displays are not placed to the far right" -ForegroundColor Cyan
            Write-Host "    4. Restart DCS" -ForegroundColor Cyan
        } else {
            Write-Host "    1. Copy the example file to: $monitorSetupDir" -ForegroundColor Cyan
            Write-Host "    2. Rename it to match your aircraft (e.g., FA-18C.lua)" -ForegroundColor Cyan
            Write-Host "    3. Adjust coordinates to match your virtual monitor positions" -ForegroundColor Cyan
            Write-Host "    4. Restart DCS" -ForegroundColor Cyan
        }
    } else {
        Write-Host "  Example MonitorSetup will be created in examples/" -ForegroundColor Yellow
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
if ($vddConfigResult) {
    Write-Host "  1. Review virtual monitors in Windows Display Settings" -ForegroundColor White
    Write-Host "     - Confirm VDD created $NumMFDs displays at ${MFDResolution}x${MFDResolution}" -ForegroundColor Gray
    Write-Host "     - Arrange them where you want DCS to export the MFDs" -ForegroundColor Gray
    if ($vddApplyResult -and -not $vddApplyResult.Applied) {
        Write-Host "     - If they do not appear immediately, reload the driver in VDC or reboot once" -ForegroundColor Gray
    }
} else {
    Write-Host "  1. Configure virtual monitors using VDC app" -ForegroundColor White
    Write-Host "     - Create $NumMFDs displays at ${MFDResolution}x${MFDResolution}" -ForegroundColor Gray
    Write-Host "     - Note their monitor positions (e.g., Monitor 2, Monitor 3)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "  2. Configure DCS MonitorSetup" -ForegroundColor White
if ($generatedSetupPath) {
    Write-Host "     - Start from generated file: $generatedSetupPath" -ForegroundColor Gray
    Write-Host "     - Verify coordinates against your virtual monitor positions" -ForegroundColor Gray
} else {
    Write-Host "     - Copy example MonitorSetup file to DCS Config folder" -ForegroundColor Gray
    Write-Host "     - Edit coordinates to match virtual monitor positions" -ForegroundColor Gray
}
Write-Host ""
Write-Host "  3. Build and deploy AccMod MFD capture module" -ForegroundColor White
Write-Host "     - Run: .\build-all.bat" -ForegroundColor Gray
Write-Host "     - Run: .\deploy.bat" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. Launch DCS and enable MFD capture in AccMod UI" -ForegroundColor White
Write-Host ""
Write-Host "For detailed instructions, see: docs\\mfd\\MFD_SETUP_GUIDE.md" -ForegroundColor Cyan
Write-Host ""

# Save configuration info
$configInfo = @{
    SetupDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    VDDInstalled = Test-VDDInstalled
    VDDInstallDir = if ($vddInstallInfo) { $vddInstallInfo.InstallDir } else { $null }
    VDDSettingsPath = $vddSettingsPath
    VDDConfigWritten = [bool]$vddConfigResult
    VDDReloadApplied = if ($vddApplyResult) { [bool]$vddApplyResult.Applied } else { $false }
    NumMFDs = $NumMFDs
    MFDResolution = $MFDResolution
    DCSFolder = $dcsConfigBase
    DCSProfile = if ($dcsProfile) { $dcsProfile.ProfileName } else { $null }
    CurrentMonitorSetup = if ($dcsMonitorInfo) { $dcsMonitorInfo.MonitorSetupName } else { $null }
    CurrentMonitorSetupPath = if ($dcsMonitorInfo) { $dcsMonitorInfo.MonitorSetupPath } else { $null }
    CurrentDesktopWidth = if ($dcsMonitorInfo) { $dcsMonitorInfo.Width } else { $null }
    CurrentDesktopHeight = if ($dcsMonitorInfo) { $dcsMonitorInfo.Height } else { $null }
    GeneratedMonitorSetupPath = $generatedSetupPath
} | ConvertTo-Json

$configInfo | Out-File ".\mfd-setup-info.json" -Encoding UTF8
Write-Host "Setup information saved to: mfd-setup-info.json" -ForegroundColor Gray
Write-Host ""
