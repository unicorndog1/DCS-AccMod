# PowerShell script to download and extract OpenXR SDK

$ErrorActionPreference = "Stop"

Write-Host "===================================" -ForegroundColor Cyan
Write-Host "  OpenXR SDK Downloader" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

# Configuration
$openXrVersion = "1.0.34"
$downloadUrl = "https://github.com/KhronosGroup/OpenXR-SDK/archive/refs/tags/release-$openXrVersion.zip"
$sdkDir = "$PSScriptRoot\..\OpenXR-SDK"
$zipFile = "$env:TEMP\OpenXR-SDK.zip"

Write-Host "OpenXR SDK Version: $openXrVersion" -ForegroundColor Yellow
Write-Host "Target Directory: $sdkDir" -ForegroundColor Yellow
Write-Host ""

# Check if already downloaded
if (Test-Path $sdkDir) {
    Write-Host "OpenXR SDK already exists at: $sdkDir" -ForegroundColor Green
    Write-Host "Delete the directory to re-download." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press any key to continue..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

Write-Host "Downloading OpenXR SDK from GitHub..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -UseBasicParsing
    Write-Host "Download complete!" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to download OpenXR SDK" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host ""
Write-Host "Extracting archive..." -ForegroundColor Cyan
try {
    $extractPath = "$PSScriptRoot\.."
    Expand-Archive -Path $zipFile -DestinationPath $extractPath -Force
    
    # Rename extracted folder
    $extractedFolder = "$extractPath\OpenXR-SDK-release-$openXrVersion"
    if (Test-Path $extractedFolder) {
        Rename-Item -Path $extractedFolder -NewName "OpenXR-SDK"
        Write-Host "Extraction complete!" -ForegroundColor Green
    } else {
        throw "Extracted folder not found: $extractedFolder"
    }
} catch {
    Write-Host "ERROR: Failed to extract OpenXR SDK" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Clean up
Write-Host ""
Write-Host "Cleaning up temporary files..." -ForegroundColor Cyan
Remove-Item $zipFile -Force

Write-Host ""
Write-Host "===================================" -ForegroundColor Green
Write-Host "  OpenXR SDK Ready!" -ForegroundColor Green
Write-Host "===================================" -ForegroundColor Green
Write-Host ""
Write-Host "SDK Location: $sdkDir" -ForegroundColor Yellow
Write-Host "You can now run build.bat to compile the layer." -ForegroundColor Yellow
Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")