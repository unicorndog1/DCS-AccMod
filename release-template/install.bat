@echo off
setlocal enabledelayedexpansion

echo ===================================
echo   DCS AccMod Release Installer
echo ===================================
echo.

REM Check for admin rights because OpenXR layer registration writes HKLM.
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: This script must be run as Administrator.
    echo Right-click install.bat and choose "Run as administrator".
    exit /b 1
)

set "PACKAGE_DIR=%~dp0"
set "PACKAGE_MODS=%PACKAGE_DIR%Mods"
set "PACKAGE_SCRIPTS=%PACKAGE_DIR%Scripts"
set "PACKAGE_OPENXR=%PACKAGE_DIR%OpenXR-Layer"
set "DCS_FOLDER="

if not exist "%PACKAGE_MODS%" (
    echo ERROR: Mods directory not found next to install.bat.
    exit /b 1
)

if not exist "%PACKAGE_SCRIPTS%" (
    echo ERROR: Scripts directory not found next to install.bat.
    exit /b 1
)

if not exist "%PACKAGE_OPENXR%\install.bat" (
    echo ERROR: OpenXR-Layer\install.bat not found next to install.bat.
    exit /b 1
)

for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$savedGames = Join-Path $env:USERPROFILE 'Saved Games'; $profiles = Get-ChildItem -Path $savedGames -Directory -Filter 'DCS*' -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'Config\options.lua') } | Sort-Object { (Get-Item (Join-Path $_.FullName 'Config\options.lua')).LastWriteTimeUtc } -Descending; if ($profiles) { $profiles[0].FullName } else { Join-Path $savedGames 'DCS' }"`) do set "DCS_FOLDER=%%I"

if not defined DCS_FOLDER (
    echo ERROR: Could not resolve a DCS Saved Games profile.
    exit /b 1
)

echo Installing release package into:
echo   %DCS_FOLDER%
echo.

if not exist "%DCS_FOLDER%" (
    echo Creating Saved Games profile directory...
    mkdir "%DCS_FOLDER%"
    if %ERRORLEVEL% NEQ 0 (
        echo ERROR: Failed to create %DCS_FOLDER%
        exit /b 1
    )
)

echo Copying Mods...
robocopy "%PACKAGE_MODS%" "%DCS_FOLDER%\Mods" /E /R:2 /W:1 /NFL /NDL /NJH /NJS /nc /ns /np >nul
if %ERRORLEVEL% GEQ 8 (
    echo ERROR: Failed to copy Mods into %DCS_FOLDER%\Mods
    exit /b 1
)

echo Copying Scripts...
robocopy "%PACKAGE_SCRIPTS%" "%DCS_FOLDER%\Scripts" /E /R:2 /W:1 /NFL /NDL /NJH /NJS /nc /ns /np >nul
if %ERRORLEVEL% GEQ 8 (
    echo ERROR: Failed to copy Scripts into %DCS_FOLDER%\Scripts
    exit /b 1
)

echo Registering OpenXR layer...
call "%PACKAGE_OPENXR%\install.bat"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: OpenXR layer installation failed.
    exit /b 1
)

echo.
echo ===================================
echo   Installation Complete!
echo ===================================
echo.
echo Installed package contents to:
echo   %DCS_FOLDER%
echo.
echo Registered OpenXR layer from:
echo   %PACKAGE_OPENXR%
echo.
echo Restart DCS completely before testing.
echo.
exit /b 0