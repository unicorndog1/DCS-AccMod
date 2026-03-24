@echo off
setlocal enabledelayedexpansion

echo =========================================
echo   DCS-AccMod Unified Build Script
echo =========================================
echo.
echo This script will:
echo   1. Build AccJoyBridge DLL
echo   2. Build OpenXR Layer DLL
echo   3. Deploy all files to workspace
echo   4. Deploy all files to Saved Games
echo.

set "ROOT_DIR=%~dp0"
set "SAVED_GAMES=%USERPROFILE%\Saved Games"
set "DCS_FOLDER=%SAVED_GAMES%\DCS"
for /f %%I in ('powershell -NoProfile -Command "(Get-Date).ToString('yyyyMMdd-HHmmss')"') do set "BUILD_REVISION=%%I"
set "BUILD_REVISION_FILE=%TEMP%\DCS_AccMod_BuildRevision.lua"
>"%BUILD_REVISION_FILE%" echo revision = "%BUILD_REVISION%"

if /I not "%SKIP_LUA_SYNTAX_CHECK%"=="1" (
    call :find_lua_checker
    if errorlevel 1 (
        echo ERROR: No Lua syntax checker found.
        echo        Install Lua and add luac.exe or lua.exe to PATH,
        echo        or install DCS where luae.exe is available.
        echo        Set SKIP_LUA_SYNTAX_CHECK=1 to bypass this check.
        del "%BUILD_REVISION_FILE%" >nul 2>&1
        exit /b 1
    )
)

REM =========================================
REM Validate Lua syntax
REM =========================================
echo [1/5] Validating Lua syntax...
echo.

if /I not "%SKIP_LUA_SYNTAX_CHECK%"=="1" (
    call :check_lua_syntax
    if errorlevel 1 (
        del "%BUILD_REVISION_FILE%" >nul 2>&1
        exit /b 1
    )
)

echo Lua syntax validation complete!
echo.

REM =========================================
REM Build AccJoyBridge
REM =========================================
echo [2/5] Building AccJoyBridge...
echo.

cd "%ROOT_DIR%native\AccJoyBridge"

if not exist build (
    mkdir build
)

cd build
cmake .. -G "Visual Studio 18 2026" -A x64
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: AccJoyBridge CMake configuration failed!
    cd "%ROOT_DIR%"
    exit /b 1
)

cmake --build . --config Release
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: AccJoyBridge build failed!
    cd "%ROOT_DIR%"
    exit /b 1
)

echo AccJoyBridge build complete!
echo.

REM =========================================
REM Build OpenXR Layer
REM =========================================
cd "%ROOT_DIR%OpenXR-Layer"

echo [3/5] Building OpenXR Layer...
echo.

if not exist build (
    mkdir build
    cd build
    cmake .. -G "Visual Studio 18 2026" -A x64
    if %ERRORLEVEL% NEQ 0 (
        echo ERROR: OpenXR Layer CMake configuration failed!
        cd "%ROOT_DIR%"
        exit /b 1
    )
    cd ..
)

cmake --build build --config Release
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: OpenXR Layer build failed!
    cd "%ROOT_DIR%"
    exit /b 1
)

echo OpenXR Layer build complete!
echo.

REM =========================================
REM Deploy to Workspace
REM =========================================
cd "%ROOT_DIR%"

echo [4/5] Deploying to workspace...
echo.

REM Copy AccJoyBridge.dll to workspace Mods location
set "ACCJOY_SOURCE=native\AccJoyBridge\build\bin\Release\AccJoyBridge.dll"
set "ACCJOY_DEST=Mods\Services\DCS-AccWidg\bin\"

if not exist "%ACCJOY_DEST%" mkdir "%ACCJOY_DEST%"

echo   - Copying AccJoyBridge.dll to workspace...
copy /Y "%ACCJOY_SOURCE%" "%ACCJOY_DEST%" >nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to copy AccJoyBridge.dll to workspace!
    exit /b 1
)

REM Copy OpenXR Layer DLL to OpenXR-Layer directory (for JSON manifest)
set "OPENXR_SOURCE=OpenXR-Layer\build\bin\Release\DCS_AccMod_OpenXR_Layer.dll"
set "OPENXR_DEST=OpenXR-Layer\DCS_AccMod_OpenXR_Layer.dll"

echo   - Copying OpenXR Layer DLL to manifest location...
copy /Y "%OPENXR_SOURCE%" "%OPENXR_DEST%" >nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to copy OpenXR Layer DLL!
    exit /b 1
)

echo Workspace deployment complete!
echo.

REM =========================================
REM Deploy to Saved Games
REM =========================================
echo [5/5] Deploying to Saved Games (%DCS_FOLDER%)...
echo.

if not exist "%DCS_FOLDER%" (
    echo WARNING: DCS Saved Games folder not found at %DCS_FOLDER%
    echo Please ensure DCS is installed.
    echo.
    echo Workspace deployment was successful. You can manually copy files later.
    del "%BUILD_REVISION_FILE%" >nul 2>&1
    exit /b 0
)

REM Copy Mods and Scripts directories
echo   - Copying Mods directory...
if exist "Mods" (
    xcopy "Mods" "%DCS_FOLDER%\Mods" /E /I /Y /Q
) else (
    echo WARNING: Mods directory not found!
)

echo   - Copying Scripts directory...
if exist "Scripts" (
    xcopy "Scripts" "%DCS_FOLDER%\Scripts" /E /I /Y /Q
) else (
    echo WARNING: Scripts directory not found!
)

REM Copy AccJoyBridge.dll to Saved Games (may fail if DCS is running)
set "ACCJOY_SAVEDGAMES=%DCS_FOLDER%\Mods\Services\DCS-AccWidg\bin\"
if not exist "%ACCJOY_SAVEDGAMES%" mkdir "%ACCJOY_SAVEDGAMES%"

echo   - Copying AccJoyBridge.dll to Saved Games...
copy /Y "%ACCJOY_SOURCE%" "%ACCJOY_SAVEDGAMES%" >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo WARNING: Could not copy AccJoyBridge.dll to Saved Games
    echo          (This is normal if DCS is currently running)
) else (
    echo     AccJoyBridge.dll copied successfully!
)

set "SAVED_GAMES_REVISION_DEST=%DCS_FOLDER%\Mods\Services\DCS-AccWidg\Scripts\BuildRevision.lua"
echo   - Writing build revision %BUILD_REVISION% to Saved Games...
copy /Y "%BUILD_REVISION_FILE%" "%SAVED_GAMES_REVISION_DEST%" >nul
if %ERRORLEVEL% NEQ 0 (
    echo WARNING: Failed to write build revision file to Saved Games
) else (
    echo     Build revision file copied successfully!
)

del "%BUILD_REVISION_FILE%" >nul 2>&1

echo.
echo =========================================
echo   BUILD AND DEPLOYMENT COMPLETE!
echo =========================================
echo.
echo Built components:
echo   - AccJoyBridge.dll
echo   - DCS_AccMod_OpenXR_Layer.dll
echo   - Manager revision: %BUILD_REVISION%
echo.
echo Deployed to workspace:
echo   - %ROOT_DIR%Mods\Services\DCS-AccWidg\bin\AccJoyBridge.dll
echo   - %ROOT_DIR%OpenXR-Layer\DCS_AccMod_OpenXR_Layer.dll
echo.
echo Deployed to Saved Games:
echo   - %DCS_FOLDER%\Mods\
echo   - %DCS_FOLDER%\Scripts\
echo   - %DCS_FOLDER%\Mods\Services\DCS-AccWidg\bin\AccJoyBridge.dll
echo.
echo Next steps:
echo   1. Run OpenXR-Layer\install.bat as Administrator (one-time setup)
echo   2. Launch DCS and test the mod
echo.

exit /b 0

:find_lua_checker
set "LUA_CHECKER="
set "LUA_CHECKER_MODE="

for %%C in (luac.exe luac) do (
    where %%C >nul 2>&1
    if not errorlevel 1 (
        for /f "delims=" %%P in ('where %%C') do (
            set "LUA_CHECKER=%%P"
            set "LUA_CHECKER_MODE=luac"
            exit /b 0
        )
    )
)

for %%C in (lua.exe lua lua5.1 lua51) do (
    where %%C >nul 2>&1
    if not errorlevel 1 (
        for /f "delims=" %%P in ('where %%C') do (
            set "LUA_CHECKER=%%P"
            set "LUA_CHECKER_MODE=lua"
            exit /b 0
        )
    )
)

for %%P in (
    "%ProgramFiles%\Eagle Dynamics\DCS World\bin\luae.exe"
    "%ProgramFiles%\Eagle Dynamics\DCS World OpenBeta\bin\luae.exe"
    "%ProgramFiles%\Eagle Dynamics\DCS World OpenAlpha\bin\luae.exe"
    "%ProgramFiles(x86)%\Eagle Dynamics\DCS World\bin\luae.exe"
    "%ProgramFiles(x86)%\Eagle Dynamics\DCS World OpenBeta\bin\luae.exe"
    "%ProgramFiles(x86)%\Eagle Dynamics\DCS World OpenAlpha\bin\luae.exe"
) do (
    if exist "%%~P" (
        set "LUA_CHECKER=%%~P"
        set "LUA_CHECKER_MODE=lua"
        exit /b 0
    )
)

exit /b 1

:check_lua_syntax
if not defined LUA_CHECKER exit /b 1

for %%D in ("%ROOT_DIR%Mods" "%ROOT_DIR%Scripts") do (
    if exist "%%~fD" (
        for /r "%%~fD" %%F in (*.lua) do (
            echo   - Checking %%~nxF
            call :check_one_lua "%%~fF"
            if errorlevel 1 exit /b 1
        )
    )
)

exit /b 0

:check_one_lua
if /I "%LUA_CHECKER_MODE%"=="luac" (
    "%LUA_CHECKER%" -p "%~1"
    exit /b %ERRORLEVEL%
)

"%LUA_CHECKER%" -e "local chunk, err = loadfile(arg[1]); if not chunk then io.stderr:write(err, '\n'); os.exit(1) end" "%~1"
exit /b %ERRORLEVEL%
