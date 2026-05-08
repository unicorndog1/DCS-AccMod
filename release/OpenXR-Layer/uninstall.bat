@echo off
REM Uninstall script for DCS AccMod OpenXR Layer
REM MUST RUN AS ADMINISTRATOR

echo ===================================
echo   DCS AccMod OpenXR Layer Uninstaller
echo ===================================
echo.

REM Check for admin rights
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: This script must be run as Administrator!
    echo Right-click and select "Run as administrator"
    exit /b 1
)

echo Removing OpenXR layer from registry...
echo.

REM Get the full path to the JSON manifest
set "MANIFEST_PATH=%~dp0DCS_AccMod_OpenXR_Layer.json"

echo Manifest path: %MANIFEST_PATH%
echo.

REM Remove the layer from the registry
reg delete "HKLM\SOFTWARE\Khronos\OpenXR\1\ApiLayers\Implicit" /v "%MANIFEST_PATH%" /f

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo WARNING: Layer may not have been registered or already removed.
)

echo.
echo ===================================
echo   Uninstallation Complete!
echo ===================================
echo.
echo The OpenXR layer has been removed from the registry.
echo Restart DCS for changes to take effect.
echo.