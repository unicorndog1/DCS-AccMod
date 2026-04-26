@echo off
REM Build script for MFDCapture module

echo ========================================
echo Building MFD Capture Module
echo ========================================
echo.

cd /d "%~dp0"

if not exist "build" mkdir build
cd build

echo Configuring CMake...
cmake .. -G "Visual Studio 17 2022" -A x64
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: CMake configuration failed
    echo Make sure Visual Studio 2022 is installed
    pause
    exit /b 1
)

echo.
echo Building Release configuration...
cmake --build . --config Release
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: Build failed
    pause
    exit /b 1
)

echo.
echo ========================================
echo Build Complete!
echo ========================================
echo.
echo Output:
echo   Library: build\lib\Release\MFDCapture.lib
echo   Test: build\bin\Release\MFDCaptureTest.exe
echo.
echo To test:
echo   cd build\bin\Release
echo   MFDCaptureTest.exe [monitor_index]
echo.

cd ..
pause
