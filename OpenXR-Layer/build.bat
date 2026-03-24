@echo off
REM Build script for DCS AccMod OpenXR Layer
REM Compiler: Visual Studio Build Tools 18 (2026), x64
REM Output DLL is deployed to the same directory as this script,
REM next to DCS_AccMod_OpenXR_Layer.json (the registered OpenXR manifest).
REM Registry entry: HKLM\SOFTWARE\Khronos\OpenXR\1\ApiLayers\Implicit
REM   -> <this dir>\DCS_AccMod_OpenXR_Layer.json (library_path = .\DCS_AccMod_OpenXR_Layer.dll)

echo ===================================
echo   DCS AccMod OpenXR Layer Builder
echo ===================================
echo.

REM Configure cmake if build directory does not yet exist
if not exist "build" (
    echo Configuring cmake...
    mkdir build
    cd build
    cmake .. -G "Visual Studio 18 2026" -A x64
    if %ERRORLEVEL% NEQ 0 (
        echo.
        echo ERROR: cmake configuration failed!
        cd ..
        exit /b 1
    )
    cd ..
)

echo Building Release configuration...
cmake --build build --config Release

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: Build failed!
    exit /b 1
)

REM Deploy DLL next to the registered JSON manifest (same directory as this script)
echo.
echo Deploying DLL...
copy "build\bin\Release\DCS_AccMod_OpenXR_Layer.dll" "%~dp0DCS_AccMod_OpenXR_Layer.dll" /Y

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: DLL copy failed!
    exit /b 1
)

echo.
echo ===================================
echo   Build Complete!
echo ===================================
echo DLL deployed to: %~dp0DCS_AccMod_OpenXR_Layer.dll
echo.
echo Fully restart DCS to load the updated layer.
echo.