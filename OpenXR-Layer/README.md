# DCS AccMod OpenXR Layer

An OpenXR API layer that renders aircraft tracking circles/dots in VR for DCS World.

## Installation

### Prerequisites
- Visual Studio Build Tools 2026 (or compatible)
- CMake
- Windows 10/11
- OpenXR-compatible VR runtime (e.g., SteamVR, Virtual Desktop, Oculus)

### Build & Install

1. **Build the layer**:
   ```batch
   build.bat
   ```
   This compiles the DLL and copies it to the root directory next to the JSON manifest.

2. **Install the layer** (requires Administrator):
   ```batch
   install.bat
   ```
   This registers the layer in the Windows registry at:
   `HKLM\SOFTWARE\Khronos\OpenXR\1\ApiLayers\Implicit`

3. **Restart DCS completely** to load the layer.

### Uninstall

Run as Administrator:
```batch
uninstall.bat
```

## Verification

After installation, verify the layer is registered:

```powershell
Get-Item "HKLM:\SOFTWARE\Khronos\OpenXR\1\ApiLayers\Implicit"
```

When DCS launches in VR, check `dcs.log` for:
```
OpenXR: Available Layers: (N)
  Name=XR_APILAYER_DCS_AccMod SpecVersion=1.0.0 LayerVersion=1 Description=DCS AccMod OpenXR Overlay Layer...
```

Check the layer's own log:
```powershell
Get-Content "$env:TEMP\DCS_AccMod_OpenXR.log"
```

## How It Works

1. The layer receives UDP packets on port **7779** from DCS Lua scripts
2. Packets contain circle data: position, radius, color, labels
3. The layer renders these circles as overlay graphics in VR using OpenXR composition layers
4. Three VR modes available in AccMod Manager:
   - **OFF**: No visualization
   - **ON**: Window overlay (CPU-rendered)
   - **LAYER**: OpenXR layer (GPU-rendered, better performance)

## Troubleshooting

### Layer not appearing in DCS log "Available Layers"

**Symptom**: OpenXR fails to start in DCS or other VR games.

**Cause**: The DLL file doesn't exist at the location specified in the JSON manifest.

**Fix**:
1. Ensure `build.bat` completed successfully
2. Verify the DLL exists: `Test-Path "C:\HELL\CODE\DCS-AccMod\OpenXR-Layer\DCS_AccMod_OpenXR_Layer.dll"`
3. If missing, run `build.bat` again
4. Re-run `install.bat` as Administrator
5. Restart DCS completely

### Layer loads but no circles appear

1. Check VR mode is set to **LAYER** in AccMod Manager UI (click "VR Mode" button twice)
2. Verify UDP traffic: Check layer log for "Received circle" messages
3. Ensure DCS Lua scripts are sending UDP packets to localhost:7779

## File Structure

```
OpenXR-Layer/
├── DCS_AccMod_OpenXR_Layer.json    ← JSON manifest (registered in registry)
├── DCS_AccMod_OpenXR_Layer.dll     ← Layer DLL (deployed by build.bat)
├── build.bat                        ← Compile and deploy
├── install.bat                      ← Register layer (run as Admin)
├── uninstall.bat                    ← Unregister layer (run as Admin)
├── src/
│   ├── main.cpp                     ← Layer entry point, UDP receiver
│   ├── render.cpp                   ← OpenXR rendering logic
│   └── common.h                     ← Shared definitions
└── build/
    └── bin/Release/
        └── DCS_AccMod_OpenXR_Layer.dll  ← Build output (copied to root)
```

## Development

After making changes to the source code:
1. Run `build.bat` to recompile
2. The layer is automatically reloaded when DCS restarts

No need to re-run `install.bat` unless the JSON manifest changes or the registry entry is removed.
