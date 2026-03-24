@echo off
REM Download OpenXR SDK for building the layer

echo ===================================
echo   OpenXR SDK Downloader
echo ===================================
echo.

echo Launching PowerShell download script...
echo.

powershell.exe -ExecutionPolicy Bypass -File "%~dp0download_openxr.ps1"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: Download failed!
    exit /b 1
)

echo.
echo Download complete!