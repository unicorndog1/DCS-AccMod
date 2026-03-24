# Build Scripts Guide

## Quick Start

### Full Build + Deploy
```batch
build-all.bat
```
Builds both native DLLs (AccJoyBridge + OpenXR Layer), validates Lua syntax, and deploys everything to workspace and Saved Games.

### Deploy Only
```batch
deploy.bat
```
Validates Lua syntax and copies already-built files to Saved Games without rebuilding.

### Deploy with Watch Mode
```batch
deploy.bat -watch
```
Continuously deploys changes every 2 seconds (useful during development).

## Build Scripts Overview

### `build-all.bat` (NEW - Recommended)
**Full build and deployment in one command**

What it does:
1. Validates all `.lua` files under `Mods\` and `Scripts\`
2. Builds `AccJoyBridge.dll` (native/AccJoyBridge)
3. Builds `DCS_AccMod_OpenXR_Layer.dll` (OpenXR-Layer)
4. Copies AccJoyBridge.dll to:
   - `Mods/Services/DCS-AccWidg/bin/` (workspace)
   - `%USERPROFILE%\Saved Games\DCS\Mods\Services\DCS-AccWidg\bin\` (if not locked)
5. Copies OpenXR Layer DLL to `OpenXR-Layer\` (for JSON manifest)
6. Copies `Mods\` and `Scripts\` to `%USERPROFILE%\Saved Games\DCS\`

### `deploy.bat` (NEW)
**Deploy-only mode** - copies pre-built files to Saved Games

Supports `-watch` flag for continuous deployment during development.
Each deploy pass validates Lua syntax before copying files.

### `install.bat` (Legacy)
Now redirects to `deploy.bat` for compatibility.

## Individual Component Builds

### AccJoyBridge
```batch
cd native\AccJoyBridge
build.bat
install.bat
```

### OpenXR Layer
```batch
cd OpenXR-Layer
build.bat
install.bat  # Run as Administrator (one-time setup)
```

## Typical Workflow

### First Time Setup
```batch
# 1. Build everything
build-all.bat

# 2. Register OpenXR layer (one-time, as Administrator)
cd OpenXR-Layer
install.bat
```

### Development Workflow

#### Option A: Full rebuild each time
```batch
build-all.bat
```

#### Option B: Watch mode (Lua/UI changes only)
```batch
deploy.bat -watch
# Edit Lua files, changes deploy automatically
# Press Ctrl+C to stop
```

#### Option C: Individual component rebuild
```batch
# After changing C++ code:
cd native\AccJoyBridge
build.bat
cd ..\..
deploy.bat
```

## What Gets Deployed Where

### Workspace (Local Project)
- `Mods/Services/DCS-AccWidg/bin/AccJoyBridge.dll`
- `OpenXR-Layer/DCS_AccMod_OpenXR_Layer.dll`

### Saved Games (%USERPROFILE%\Saved Games\DCS)
- `Mods/Services/DCS-AccWidg/` (entire directory structure)
- `Scripts/Hooks/DCS-AccMod-hook.lua`
- `Mods/Services/DCS-AccWidg/bin/AccJoyBridge.dll`

### Registry (OpenXR Layer)
- `HKLM\SOFTWARE\Khronos\OpenXR\1\ApiLayers\Implicit`
  - Points to `<workspace>\OpenXR-Layer\DCS_AccMod_OpenXR_Layer.json`
  - JSON manifest references `.\DCS_AccMod_OpenXR_Layer.dll` in same directory

## Troubleshooting

### "Could not copy AccJoyBridge.dll (DCS may be running)"
**Solution:** Close DCS completely, then run the script again.

### "CMake configuration failed"
**Solution:** Ensure Visual Studio 2026 Build Tools are installed.

### "OpenXR Layer not loading in DCS"
**Solution:**
1. Verify registry entry exists: Run `OpenXR-Layer\install.bat` as Administrator
2. Check [dcs.log](file:///%USERPROFILE%/Saved%20Games/DCS/Logs/dcs.log) for "XR_APILAYER_DCS_AccMod"
3. Ensure DLL exists at: `OpenXR-Layer\DCS_AccMod_OpenXR_Layer.dll`

### "No Lua syntax checker found"
**Solution:**
1. Install Lua and add `luac.exe` or `lua.exe` to `PATH`, or use a DCS install that includes `luae.exe`
2. Re-run `build-all.bat` or `deploy.bat`
3. If you need to bypass the check temporarily, set `SKIP_LUA_SYNTAX_CHECK=1`
