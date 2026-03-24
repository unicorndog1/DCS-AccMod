# DCS-AccMod Dev Notes

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

### Verify circles are being sent to the layer
Read the layer's own log (readable while DCS is running):
```powershell
Get-Content "$env:TEMP\DCS_AccMod_OpenXR.log"
```
- Must show `xrNegotiateLoaderApiLayerInterface` called
- Frame lines show `Frame N: X circles` — if always 0, VR mode is not set to LAYER

### Enable LAYER mode in-game
`vrModeEnabled` starts at 0 (OFF) and is NOT persisted. Must be toggled in the AccMod manager UI each session:
- Click **"VR Mode"** once → `ON` (window overlay)
- Click again → `LAYER` (OpenXR layer, sends UDP to port 7779)

Only when `vrModeEnabled == 2` does Lua create the UDP socket and send circle packets.
