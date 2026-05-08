# Show installed OpenXR API layers from Windows registry

Write-Host "=== OpenXR API Layers ===" -ForegroundColor Cyan
Write-Host ""

# Check Implicit Layers
Write-Host "Implicit Layers:" -ForegroundColor Yellow
$implicitPath = "HKLM:\SOFTWARE\Khronos\OpenXR\1\ApiLayers\Implicit"
if (Test-Path $implicitPath) {
    try {
        $regKey = Get-Item -Path $implicitPath
        $valueNames = $regKey.GetValueNames()
        
        if ($valueNames.Count -gt 0) {
            foreach ($valueName in $valueNames) {
                $value = $regKey.GetValue($valueName)
                Write-Host "  $valueName" -ForegroundColor Green
                Write-Host "    Value: $value"
                if (Test-Path $valueName) {
                    Write-Host "    ✓ File exists" -ForegroundColor Green
                } else {
                    Write-Host "    ✗ File not found" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "  (none installed)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  (error reading registry: $($_.Exception.Message))" -ForegroundColor Red
    }
} else {
    Write-Host "  (registry key not found)" -ForegroundColor Gray
}

Write-Host ""

# Check Explicit Layers
Write-Host "Explicit Layers:" -ForegroundColor Yellow
$explicitPath = "HKLM:\SOFTWARE\Khronos\OpenXR\1\ApiLayers\Explicit"
if (Test-Path $explicitPath) {
    try {
        $regKey = Get-Item -Path $explicitPath
        $valueNames = $regKey.GetValueNames()
        
        if ($valueNames.Count -gt 0) {
            foreach ($valueName in $valueNames) {
                $value = $regKey.GetValue($valueName)
                Write-Host "  $valueName" -ForegroundColor Green
                Write-Host "    Value: $value"
                if (Test-Path $valueName) {
                    Write-Host "    ✓ File exists" -ForegroundColor Green
                } else {
                    Write-Host "    ✗ File not found" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "  (none installed)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  (error reading registry: $($_.Exception.Message))" -ForegroundColor Red
    }
} else {
    Write-Host "  (registry key not found)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== DCS AccMod Layer Status ===" -ForegroundColor Cyan
$dcsLayerPath = "HKLM:\SOFTWARE\Khronos\OpenXR\1\ApiLayers\Implicit"
$dcsJsonPath = "C:\HELL\CODE\DCS-AccMod\OpenXR-Layer\DCS_AccMod_OpenXR_Layer.json"
if (Test-Path $dcsLayerPath) {
    try {
        $regKey = Get-Item -Path $dcsLayerPath
        $valueNames = $regKey.GetValueNames()
        
        if ($valueNames -contains $dcsJsonPath) {
            Write-Host "✓ DCS AccMod layer is installed" -ForegroundColor Green
            
            if (Test-Path $dcsJsonPath) {
                Write-Host "✓ Manifest file exists" -ForegroundColor Green
            } else {
                Write-Host "✗ Manifest file not found" -ForegroundColor Red
            }
            
            $dllPath = "C:\HELL\CODE\DCS-AccMod\OpenXR-Layer\DCS_AccMod_OpenXR_Layer.dll"
            if (Test-Path $dllPath) {
                Write-Host "✓ DLL file exists" -ForegroundColor Green
            } else {
                Write-Host "✗ DLL file not found" -ForegroundColor Red
            }
        } else {
            Write-Host "✗ DCS AccMod layer is NOT installed" -ForegroundColor Red
            Write-Host "  Run install.bat as Administrator to install" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "✗ Error reading registry: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "✗ Registry key not found" -ForegroundColor Red
}
