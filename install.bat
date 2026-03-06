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


REM Copy only Mods and Scripts directories to DCS folder
echo Copying Mods and Scripts to %DCS_FOLDER%...
for %%D in (Mods Scripts) do (
    if exist "%%D" (
        echo Copying %%D...
        xcopy "%%D" "%DCS_FOLDER%\%%D" /E /I /Y
    ) else (
        echo Directory %%D does not exist, skipping. Ensure you have unzipped the archive correctly.
    )
)

echo.
echo Installation complete!
pause