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
    return Test-Path "C:\VirtualDisplayDriver"
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

$vddSettingsPath = "C:\VirtualDisplayDriver\vdd_settings.xml"

if (-not (Test-Path $vddSettingsPath)) {
    Write-Host "  WARNING: VDD settings file not found at $vddSettingsPath" -ForegroundColor Yellow
    Write-Host "  Skipping monitor configuration" -ForegroundColor Yellow
    Write-Host "  Please configure monitors manually using VDC (Virtual Driver Control) app" -ForegroundColor Yellow
} else {
    Write-Host "  VDD settings found" -ForegroundColor Green
    Write-Host "  Monitors to create: $NumMFDs at ${MFDResolution}x${MFDResolution}" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  NOTE: Monitor configuration should be done via VDC app for best results" -ForegroundColor Yellow
    Write-Host "  Please use Virtual Driver Control to:" -ForegroundColor Cyan
    Write-Host "    1. Create $NumMFDs virtual displays" -ForegroundColor Cyan
    Write-Host "    2. Set resolution to ${MFDResolution}x${MFDResolution}" -ForegroundColor Cyan
    Write-Host "    3. Name them 'DCS_MFD_LEFT' and 'DCS_MFD_RIGHT'" -ForegroundColor Cyan
    Write-Host ""
    
    $openVDC = Read-Host "  Open Virtual Driver Control now? (y/n)"
    if ($openVDC -eq 'y') {
        $vdcPath = "C:\VirtualDisplayDriver\VDC.exe"
        if (Test-Path $vdcPath) {
            Start-Process $vdcPath
            Write-Host "  Launched VDC" -ForegroundColor Green
        } else {
            Write-Host "  VDC not found at $vdcPath" -ForegroundColor Red
        }
    }
}

# Phase 4: Create DCS MonitorSetup configuration
Write-Host ""
Write-Host "[4/4] Creating DCS MonitorSetup configuration..." -ForegroundColor Yellow

$dcsConfigBase = "$env:USERPROFILE\Saved Games\DCS"
$monitorSetupDir = "$dcsConfigBase\Config\MonitorSetup"
$exampleSetupPath = ".\examples\MonitorSetup_MFD_Example.lua"

if (-not (Test-Path $dcsConfigBase)) {
    Write-Host "  DCS Saved Games folder not found at $dcsConfigBase" -ForegroundColor Yellow
    Write-Host "  Skipping MonitorSetup configuration" -ForegroundColor Yellow
} else {
    Write-Host "  DCS Saved Games folder found" -ForegroundColor Green
    
    if (-not (Test-Path $monitorSetupDir)) {
        Write-Host "  Creating MonitorSetup directory..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $monitorSetupDir -Force | Out-Null
    }
    
    if (Test-Path $exampleSetupPath) {
        Write-Host "  Example MonitorSetup file found" -ForegroundColor Green
        Write-Host "  Location: $exampleSetupPath" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  To use MFD export in DCS:" -ForegroundColor Yellow
        Write-Host "    1. Copy the example file to: $monitorSetupDir" -ForegroundColor Cyan
        Write-Host "    2. Rename it to match your aircraft (e.g., FA-18C.lua)" -ForegroundColor Cyan
        Write-Host "    3. Adjust coordinates to match your virtual monitor positions" -ForegroundColor Cyan
        Write-Host "    4. Restart DCS" -ForegroundColor Cyan
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
Write-Host "  1. Configure virtual monitors using VDC app" -ForegroundColor White
Write-Host "     - Create $NumMFDs displays at ${MFDResolution}x${MFDResolution}" -ForegroundColor Gray
Write-Host "     - Note their monitor positions (e.g., Monitor 2, Monitor 3)" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Configure DCS MonitorSetup" -ForegroundColor White
Write-Host "     - Copy example MonitorSetup file to DCS Config folder" -ForegroundColor Gray
Write-Host "     - Edit coordinates to match virtual monitor positions" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Build and deploy AccMod MFD capture module" -ForegroundColor White
Write-Host "     - Run: .\build-all.bat" -ForegroundColor Gray
Write-Host "     - Run: .\deploy.bat" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. Launch DCS and enable MFD capture in AccMod UI" -ForegroundColor White
Write-Host ""
Write-Host "For detailed instructions, see: MFD_SETUP_GUIDE.md" -ForegroundColor Cyan
Write-Host ""

# Save configuration info
$configInfo = @{
    SetupDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    VDDInstalled = Test-VDDInstalled
    NumMFDs = $NumMFDs
    MFDResolution = $MFDResolution
    DCSFolder = $dcsConfigBase
} | ConvertTo-Json

$configInfo | Out-File ".\mfd-setup-info.json" -Encoding UTF8
Write-Host "Setup information saved to: mfd-setup-info.json" -ForegroundColor Gray
Write-Host ""
