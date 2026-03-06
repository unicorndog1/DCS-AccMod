@echo off
setlocal enabledelayedexpansion

REM Get the user's Saved Games directory
set "SAVED_GAMES=%USERPROFILE%\Saved Games"
set "DCS_FOLDER=%SAVED_GAMES%\DCS"

REM Check if DCS folder exists
REM Check for clean parameter


if not exist "%DCS_FOLDER%" (
    echo DCS folder not found at %DCS_FOLDER%
    echo.
    echo Please ensure DCS is installed.
    pause
    exit /b 1
)

REM Create/clear uninstall tracking file
echo. > "%DCS_FOLDER%\uninstall.txt"

REM Copy all folders from current directory to DCS folder
echo Copying folders to %DCS_FOLDER%...
for /d %%D in (*) do (
    echo Copying %%D...
    xcopy "%%D" "%DCS_FOLDER%\%%D" /E /I /Y
   
 
)

echo.
echo Installation complete!
pause