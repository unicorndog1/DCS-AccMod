#!/usr/bin/env pwsh
# Verification script for DCS AccMod OpenXR Layer installation

Write-Host "=== DCS AccMod OpenXR Layer Verification ===" -ForegroundColor Cyan
Write-Host ""

# Check registry entry
Write-Host "1. Checking registry entry..." -ForegroundColor Yellow
$regPath = "HKLM:\SOFTWARE\Khronos\OpenXR\1\ApiLayers\Implicit"
$jsonPath = "C:\HELL\CODE\DCS-AccMod\OpenXR-Layer\DCS_AccMod_OpenXR_Layer.json"

$entries = Get-Item $regPath | Select-Object -ExpandProperty Property
if ($entries -contains $jsonPath) {
    Write-Host "   ✓ Layer registered in OpenXR registry" -ForegroundColor Green
} else {
    Write-Host "   ✗ Layer NOT found in registry" -ForegroundColor Red
    Write-Host "     Run install.bat as Administrator" -ForegroundColor Yellow
    exit 1
}

# Check JSON manifest exists
Write-Host ""
Write-Host "2. Checking JSON manifest..." -ForegroundColor Yellow
if (Test-Path $jsonPath) {
    Write-Host "   ✓ JSON manifest exists" -ForegroundColor Green
} else {
    Write-Host "   ✗ JSON manifest NOT found" -ForegroundColor Red
    exit 1
}

# Check DLL exists
Write-Host ""
Write-Host "3. Checking DLL..." -ForegroundColor Yellow
$dllPath = "C:\HELL\CODE\DCS-AccMod\OpenXR-Layer\DCS_AccMod_OpenXR_Layer.dll"
if (Test-Path $dllPath) {
    $dll = Get-Item $dllPath
    Write-Host "   ✓ DLL exists ($($dll.Length) bytes)" -ForegroundColor Green
    Write-Host "     Last built: $($dll.LastWriteTime)" -ForegroundColor Gray
} else {
    Write-Host "   ✗ DLL NOT found" -ForegroundColor Red
    Write-Host "     Run build.bat to compile the layer" -ForegroundColor Yellow
    exit 1
}

# Check DCS log for layer loading
Write-Host ""
Write-Host "4. Checking DCS log..." -ForegroundColor Yellow
$dcsLogPath = "$env:USERPROFILE\Saved Games\DCS\Logs\dcs.log"
if (Test-Path $dcsLogPath) {
    $layerFound = Select-String -Path $dcsLogPath -Pattern "XR_APILAYER_DCS_AccMod" -Quiet
    if ($layerFound) {
        Write-Host "   ✓ Layer appears in DCS log (OpenXR runtime found it)" -ForegroundColor Green
        
        # Show the context
        $matches = Select-String -Path $dcsLogPath -Pattern "XR_APILAYER_DCS_AccMod" -Context 0,1
        Write-Host ""
        Write-Host "   Log excerpt:" -ForegroundColor Gray
        foreach ($match in $matches) {
            Write-Host "     $($match.Line)" -ForegroundColor Gray
        }
    } else {
        Write-Host "   ⚠ Layer NOT found in DCS log" -ForegroundColor Yellow
        Write-Host "     This is normal if you haven't launched DCS in VR yet" -ForegroundColor Gray
        Write-Host "     Launch DCS with --force_enable_VR --force_OpenXR flags" -ForegroundColor Gray
    }
} else {
    Write-Host "   ⚠ DCS log not found (DCS hasn't run yet)" -ForegroundColor Yellow
}

# Check layer's own log
Write-Host ""
Write-Host "5. Checking layer log..." -ForegroundColor Yellow
$layerLogPath = "$env:TEMP\DCS_AccMod_OpenXR.log"
if (Test-Path $layerLogPath) {
    Write-Host "   ✓ Layer log exists" -ForegroundColor Green
    
    # Show last few lines
    $lastLines = Get-Content $layerLogPath -Tail 5
    Write-Host ""
    Write-Host "   Last log entries:" -ForegroundColor Gray
    foreach ($line in $lastLines) {
        Write-Host "     $line" -ForegroundColor Gray
    }
} else {
    Write-Host "   ⚠ Layer log not found" -ForegroundColor Yellow
    Write-Host "     Layer hasn't been loaded by OpenXR yet" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== Verification Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Launch DCS with VR enabled (--force_enable_VR --force_OpenXR)" -ForegroundColor Gray
Write-Host "  2. Check 'dcs.log' for 'XR_APILAYER_DCS_AccMod' in Available Layers" -ForegroundColor Gray
Write-Host "  3. Check layer log: `$env:TEMP\DCS_AccMod_OpenXR.log" -ForegroundColor Gray
Write-Host ""
