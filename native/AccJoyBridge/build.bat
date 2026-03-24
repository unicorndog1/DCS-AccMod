@echo off
setlocal

echo Building AccJoyBridge...

REM Create build directory if it doesn't exist
if not exist build (
    mkdir build
)

cd build

REM Configure with CMake
cmake .. -G "Visual Studio 18 2026" -A x64

if %ERRORLEVEL% NEQ 0 (
    echo CMake configuration failed!
    exit /b 1
)

REM Build Release configuration
cmake --build . --config Release

if %ERRORLEVEL% NEQ 0 (
    echo Build failed!
    exit /b 1
)

echo.
echo Build completed successfully!
echo DLL location: build\bin\Release\AccJoyBridge.dll
echo.

endlocal
