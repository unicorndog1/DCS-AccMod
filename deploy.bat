@echo off
setlocal enabledelayedexpansion

REM Check for watch flag
set "WATCH_MODE=0"
if /I "%~1"=="-watch" set "WATCH_MODE=1"
if /I "%~1"=="/watch" set "WATCH_MODE=1"
if /I "%~1"=="--watch" set "WATCH_MODE=1"

set "ROOT_DIR=%~dp0"
set "SAVED_GAMES=%USERPROFILE%\Saved Games"
set "DCS_FOLDER=%SAVED_GAMES%\DCS"

if /I not "%SKIP_LUA_SYNTAX_CHECK%"=="1" (
    call :find_lua_checker
    if errorlevel 1 (
        echo ERROR: No Lua syntax checker found.
        echo        Install Lua and add luac.exe or lua.exe to PATH,
        echo        or install DCS where luae.exe is available.
        echo        Set SKIP_LUA_SYNTAX_CHECK=1 to bypass this check.
        exit /b 1
    )
)

if not exist "%DCS_FOLDER%" (
    echo DCS folder not found at %DCS_FOLDER%
    echo.
    echo Please ensure DCS is installed.
    exit /b 1
)

if "%WATCH_MODE%"=="1" (
    echo ==========================================
    echo WATCH MODE ENABLED - Continuous Deployment
    echo Deploying every 2 seconds...
    echo Press Ctrl+C to stop
    echo ==========================================
    echo.
)

:DEPLOY_LOOP

cd "%ROOT_DIR%"

if /I not "%SKIP_LUA_SYNTAX_CHECK%"=="1" (
    echo Validating Lua syntax...
    call :check_lua_syntax
    if !ERRORLEVEL! NEQ 0 (
        if "%WATCH_MODE%"=="1" (
            echo.
            echo Syntax check failed. Waiting 2 seconds before retry...
            ping 127.0.0.1 -n 3 >nul
            echo.
            goto DEPLOY_LOOP
        )
        exit /b 1
    )
    echo Lua syntax validation complete.
    echo.
)

echo Deploying DCS-AccMod to %DCS_FOLDER%...
echo.

REM Copy Mods and Scripts directories to DCS folder (excluding bin directories)
for %%D in (Mods Scripts) do (
    if exist "%%D" (
        echo Copying %%D ^(excluding bin directories^)...
        robocopy "%%D" "%DCS_FOLDER%\%%D" /E /XD bin /NFL /NDL /NJH /NJS /nc /ns /np
        REM robocopy returns 0-7 for success (0=no files, 1=files copied, etc), 8+ for errors
        if !ERRORLEVEL! GEQ 8 (
            echo WARNING: Some files in %%D could not be copied ^(may be in use^)
        )
    ) else (
        echo Directory %%D does not exist, skipping.
    )
)

REM Copy AccJoyBridge.dll if available (may fail if DCS is running)
if exist "native\AccJoyBridge\build\bin\Release\AccJoyBridge.dll" (
    set "ACCJOY_DEST=%DCS_FOLDER%\Mods\Services\DCS-AccWidg\bin\"
    if not exist "!ACCJOY_DEST!" mkdir "!ACCJOY_DEST!"
    
    echo Copying AccJoyBridge.dll...
    copy /Y "native\AccJoyBridge\build\bin\Release\AccJoyBridge.dll" "!ACCJOY_DEST!" >nul 2>&1
    if !ERRORLEVEL! NEQ 0 (
        echo WARNING: Could not copy AccJoyBridge.dll ^(DCS may be running^)
    )
)

REM Copy OpenXR Layer DLL from build output to OpenXR-Layer directory
if exist "OpenXR-Layer\build\bin\Release\DCS_AccMod_OpenXR_Layer.dll" (
    echo Copying OpenXR Layer DLL...
    copy /Y "OpenXR-Layer\build\bin\Release\DCS_AccMod_OpenXR_Layer.dll" "OpenXR-Layer\DCS_AccMod_OpenXR_Layer.dll" >nul 2>&1
    if !ERRORLEVEL! NEQ 0 (
        echo WARNING: Could not copy OpenXR Layer DLL ^(may be in use^)
    )
)

echo.
echo Deployment complete! [%TIME%]

if "%WATCH_MODE%"=="1" (
    echo Waiting 2 seconds before next deployment...
    ping 127.0.0.1 -n 3 >nul
    echo.
    goto DEPLOY_LOOP
)

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
