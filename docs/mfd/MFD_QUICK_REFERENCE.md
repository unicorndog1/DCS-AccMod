# Quick Reference: MFD Rendering Setup

## One-Page Setup Guide

### 1. Install Virtual Display Driver
```powershell
winget install --id=VirtualDrivers.Virtual-Display-Driver -e
```

### 2. Create Virtual Monitors
- Launch VDC (Virtual Driver Control)
- Add 2 displays @ 800x800, 60Hz
- Name them: DCS_MFD_LEFT, DCS_MFD_RIGHT
- Arrange away from main monitor

### 3. Configure DCS
Copy: `examples\MonitorSetup_MFD_Example.lua`
To: `%USERPROFILE%\Saved Games\DCS\Config\MonitorSetup\`
Rename to: `[Aircraft].lua` (e.g., FA-18C_hornet.lua)

Edit coordinates to match your virtual monitor positions:
```lua
[2] = { x = 1920, y = 0, width = 800, height = 800 }  -- Left MFD
[3] = { x = 2720, y = 0, width = 800, height = 800 }  -- Right MFD
```

### 4. Build & Deploy
```powershell
.\build-all.bat
.\deploy.bat
```

### 5. Enable in DCS
- Start DCS
- Enter aircraft
- Press Ctrl+Shift+A
- Enable MFD Capture

## Common Aircraft Names

| Aircraft | MonitorSetup Filename |
|----------|----------------------|
| F/A-18C | `FA-18C_hornet.lua` |
| F-16C | `F-16C_50.lua` |
| A-10C | `A-10C_2.lua` |
| AH-64D | `AH-64D_BLK_II.lua` |

## Troubleshooting Quick Fixes

| Problem | Solution |
|---------|----------|
| No virtual monitors | Reinstall VDD as Admin, restart |
| DCS doesn't render MFDs | Check MonitorSetup filename and coordinates |
| Black MFD widgets | Verify virtual monitors enabled in VDC |
| Poor FPS | Reduce capture rate to 15 FPS |

## Display Positions Example

```
Main Monitor (0,0) → Virtual #1 (1920,0) → Virtual #2 (2720,0)
   1920x1080           800x800                800x800
```

## Quick Test
```powershell
cd native\MFDCapture\build\bin\Release
.\MFDCaptureTest.exe
# Select virtual monitor index
# Should capture and save frames
```

## Files Reference

| File | Purpose |
|------|---------|
| `setup-mfd-system.ps1` | Automated installer |
| `docs/mfd/MFD_SETUP_GUIDE.md` | Full setup guide |
| `docs/mfd/MFD_RENDERING_PLAN.md` | Technical design |
| `examples\MonitorSetup_MFD_Example.lua` | DCS config template |

## Support
Full Guide: `docs/mfd/MFD_SETUP_GUIDE.md`
Progress: `docs/mfd/MFD_IMPLEMENTATION_PROGRESS.md`
Issues: GitHub Issues
