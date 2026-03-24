@echo off
REM Install script for DCS AccMod OpenXR Layer
REM MUST RUN AS ADMINISTRATOR

echo ===================================
echo   DCS AccMod OpenXR Layer Installer
echo ===================================
echo.

REM Check for admin rights
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: This script must be run as Administrator!
    echo Right-click and select "Run as administrator"
    exit /b 1
)

echo Installing OpenXR layer to registry...
echo.

REM Get the full path to the JSON manifest
set "MANIFEST_PATH=%~dp0DCS_AccMod_OpenXR_Layer.json"

echo Manifest path: %MANIFEST_PATH%
echo.

REM Register the layer in the registry
reg add "HKLM\SOFTWARE\Khronos\OpenXR\1\ApiLayers\Implicit" /v "%MANIFEST_PATH%" /t REG_DWORD /d 0 /f

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: Failed to register layer in registry!
    exit /b 1
)

echo.
echo ===================================
echo   Installation Complete!
echo ===================================
echo.
echo The OpenXR layer has been registered.
echo Restart DCS and enter VR to activate the overlay.
echo.
echo To uninstall, run uninstall.bat as Administrator.
echo.