# DCS-AccMod Dev Notes

## VR Zoom Detection & Overlay Scaling (2026-05-02)

**Feature**: OpenXR layer now detects DCS VR zoom and automatically scales overlay dots to match the zoomed view.

**Implementation**:
- **Hook `xrLocateViews`**: Intercepts view data every frame to extract FOV (field of view) angles
- **Baseline capture**: First frame FOV is stored as baseline (unzoomed state)
- **Zoom calculation**: `zoomFactor = baselineFOV / currentFOV`
  - 1.0x = normal view
  - 2.0x = zoomed in 2x (FOV halved)
- **Position scaling**: Circle positions scale away from screen center (0.5, 0.5)
  - Formula: `zoomedPos = 0.5 + (originalPos - 0.5) * zoomFactor`
- **Radius scaling**: Circle sizes also scale with zoom factor to maintain apparent size
- **Hash invalidation**: Zoom factor included in scene hash to trigger re-rasterization

**Files Modified**:
- [common.h](c:\HELL\CODE\DCS-AccMod\OpenXR-Layer\src\common.h) - Added zoom state to `LayerState`
- [main.cpp](c:\HELL\CODE\DCS-AccMod\OpenXR-Layer\src\main.cpp) - Initialize zoom state
- [render.cpp](c:\HELL\CODE\DCS-AccMod\OpenXR-Layer\src\render.cpp) - Hook `xrLocateViews`, apply zoom scaling

**How It Works**:
1. DCS narrows FOV angles when user zooms in VR
2. Layer captures FOV change via `xrLocateViews` hook
3. Calculates zoom factor = baseline / current FOV
4. Scales circle positions and radii proportionally
5. Dots stay aligned with zoomed world geometry

**Testing**: Use DCS VR zoom (default binding varies by module) and verify overlay dots scale correctly with the view.

## Lua 60 Upvalue Limit Fix (2026-04-30)

**Problem**: `UnitHighlightPanel:detectUnits()` at line 2767 exceeded Lua 5.1's hard limit of 60 upvalues per function. Error message:
```
AccMod Load Error: function at line 2767 has more than 60 upvalues
```

**Root Cause**: The 147-line `detectUnits()` function referenced too many outer scope variables:
- Multiple `self.property` accesses
- Multiple `base.*` references  
- Helper function `hasFullLOS` from outer scope
- Table creation inside loops

**Fix Applied**:
1. Created module-level constants `VALID_TYPE_LEVEL1` and `VALID_TYPE_LEVEL2` (moved from inside function)
2. Extracted inner loop into `_processUnitForDetection()` helper function with explicit parameters
3. Localized all `self` properties at function start (`maxDots`, `lastDetectionLog`)
4. Reduced main function from 147 lines to ~70 lines

**Files Changed**:
- [DCS-SRS-AccMod.lua](c:\HELL\CODE\DCS-AccMod\Mods\Services\DCS-AccWidg\Scripts\DCS-SRS-AccMod.lua) - lines ~65 (constants), ~2770 (helper), ~2880 (refactored detectUnits)

**Prevention Guidelines**:
- Keep functions under 100 lines
- Extract complex nested logic into helper functions with explicit parameters
- Move constant tables to module scope
- Localize all external references at function top
- Minimize `self.property` accesses in methods (cache in locals)

## OpenXR Layer Installation

### Proper Installation Steps
1. **Build the layer**: Run `build.bat` to compile and deploy the DLL to the root directory
2. **Install the layer**: Run `install.bat as Administrator` to register in Windows registry
3. **Verify installation**: Check registry entry exists:
   ```powershell
   Get-Item "HKLM:\SOFTWARE\Khronos\OpenXR\1\ApiLayers\Implicit"
   ```
4. **Restart DCS completely** to load the updated layer

### Fixed Issue (2026-04-09)
**Problem**: OpenXR layer was never loading - didn't appear in DCS log "Available Layers" section. This caused OpenXR to fail in DCS and other games.

**Root Cause**: The `install.bat` registered the JSON manifest from `OpenXR-Layer\DCS_AccMod_OpenXR_Layer.json`, which references the DLL with relative path `.\DCS_AccMod_OpenXR_Layer.dll`. However, the DLL was only built to `build\bin\Release\` and never copied to the root directory. When OpenXR runtime tried to load the layer, it couldn't find the DLL at the expected location and silently failed.

**Fix**: 
- `build.bat` already had deployment logic (lines 38-46) to copy DLL from `build\bin\Release\` to root directory
- Updated `install.bat` to verify DLL exists and copy from build directory if needed before registering
- Both files now ensure DLL is present at `OpenXR-Layer\DCS_AccMod_OpenXR_Layer.dll` before registration

**Key files**:
- [OpenXR-Layer/DCS_AccMod_OpenXR_Layer.json](c:\HELL\CODE\DCS-AccMod\OpenXR-Layer\DCS_AccMod_OpenXR_Layer.json) - manifest with relative path `.\DCS_AccMod_OpenXR_Layer.dll`
- [OpenXR-Layer/DCS_AccMod_OpenXR_Layer.dll](c:\HELL\CODE\DCS-AccMod\OpenXR-Layer\DCS_AccMod_OpenXR_Layer.dll) - must exist here for layer to load
- [OpenXR-Layer/install.bat](c:\HELL\CODE\DCS-AccMod\OpenXR-Layer\install.bat) - now checks DLL exists before registering

## Debugging Checklist

### Verify OpenXR API layer is loaded
Check `dcs.log` (`%USERPROFILE%\Saved Games\DCS\Logs\dcs.log`) for the "Available Layers" section — `XR_APILAYER_DCS_AccMod` must appear there:

```
OpenXR: Available Layers: (N)
  Name=XR_APILAYER_DCS_AccMod SpecVersion=1.0.0 LayerVersion=1 Description=DCS AccMod OpenXR Overlay Layer...
```

Quick search:
```powershell
Select-String -Path "$env:USERPROFILE\Saved Games\DCS\Logs\dcs.log" -Pattern "XR_APILAYER_DCS_AccMod"
```

If it is **missing**: check the registry entry exists and points to the correct JSON:
```powershell
Get-Item "HKLM:\SOFTWARE\Khronos\OpenXR\1\ApiLayers\Implicit"
```
Expected: `C:\HELL\CODE\DCS-AccMod\OpenXR-Layer\DCS_AccMod_OpenXR_Layer.json`

**Also check the DLL exists**:
```powershell
Test-Path "C:\HELL\CODE\DCS-AccMod\OpenXR-Layer\DCS_AccMod_OpenXR_Layer.dll"
```
If missing, run `build.bat` again.

### Verify circles are being sent to the layer
Read the layer's own log (readable while DCS is running):
```powershell
Get-Content "$env:TEMP\DCS_AccMod_OpenXR.log"
```
- Must show `xrNegotiateLoaderApiLayerInterface` called
- Frame lines show `Frame N: X circles` — if always 0, VR mode is not set to LAYER

### Enable LAYER mode in-game
`vrModeEnabled` starts at 0 (OFF) by default but is now persisted in `AccModManager.lua`. Toggle in the AccMod manager UI:
- Click **"VR Mode"** once → `ON` (window overlay)
- Click again → `LAYER` (OpenXR layer, sends UDP to port 7779)
- Your selection will be saved and restored on restart

Only when `vrModeEnabled == 2` does Lua create the UDP socket and send circle packets.
