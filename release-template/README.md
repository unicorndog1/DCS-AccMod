# DCS AccMod Release Package

This package contains the prebuilt DCS AccMod files needed to install the mod and register the bundled OpenXR layer.

## Package Contents

- `install.bat` - one-shot installer for the full release package
- `Mods\` - DCS service mod payload
- `Scripts\` - DCS hook and support scripts
- `OpenXR-Layer\` - prebuilt OpenXR DLL, manifest, install script, and uninstall script

## Install

1. Extract the release package to a normal folder.
2. Close DCS completely.
3. Right-click `install.bat` and choose **Run as administrator**.
4. Wait for the installer to copy the package into your Saved Games DCS profile and register the OpenXR layer.
5. Restart DCS completely.

The installer automatically picks the most recently used `Saved Games\DCS*` profile by checking which `Config\options.lua` was updated most recently.

## What `install.bat` Does

1. Copies `Mods\` into your active Saved Games DCS profile.
2. Copies `Scripts\` into your active Saved Games DCS profile.
3. Runs `OpenXR-Layer\install.bat` to register the bundled OpenXR layer in Windows.

## Manual OpenXR Layer Operations

- Install only the XR layer: run `OpenXR-Layer\install.bat` as Administrator.
- Uninstall the XR layer: run `OpenXR-Layer\uninstall.bat` as Administrator.

## Notes

- The XR layer installer writes to `HKLM\SOFTWARE\Khronos\OpenXR\1\ApiLayers\Implicit`, so Administrator rights are required.
- If DCS is still running, some files may stay locked. Close DCS and rerun `install.bat`.
- After installing, fully restart DCS before testing VR overlay behavior.