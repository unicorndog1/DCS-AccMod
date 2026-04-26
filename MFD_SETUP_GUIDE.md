# DCS AccMod - MFD Rendering Setup Guide

This guide walks you through setting up MFD (Multi-Function Display) rendering in DCS AccMod. The system captures DCS MFD displays rendered to virtual monitors and displays them in AccMod windows or VR overlay.

## Overview

The MFD rendering system works by:
1. Creating virtual monitors (fake displays recognized by Windows)
2. Configuring DCS to render MFDs to these virtual monitors
3. Capturing the rendered MFD frames using Desktop Duplication API
4. Displaying captured frames in AccMod widgets or VR overlays

## Prerequisites

- **Windows 10/11** (64-bit)
- **DCS World** (Open Beta or Stable)
- **Visual Studio 2022** (for building native modules)
- **Administrator privileges** (for virtual display driver installation)
- **DirectX 11 compatible GPU**

## Quick Start Installation

### Option 1: Automated Setup (Recommended)

Run the automated setup script as Administrator:

```powershell
# Right-click PowerShell, select "Run as Administrator"
cd C:\HELL\CODE\DCS-AccMod
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup-mfd-system.ps1
```

The script will:
- Install Virtual Display Driver (VDD)
- Check dependencies (Visual C++ Redistributable)
- Guide you through virtual monitor configuration
- Create example DCS MonitorSetup files

### Option 2: Manual Setup

Follow the detailed steps below for manual installation.

---

## Step-by-Step Manual Setup

### STEP 1: Install Virtual Display Driver

The Virtual Display Driver creates fake monitors that Windows treats as real displays.

**1.1 Download and Install**

Using winget (easiest):
```powershell
winget install --id=VirtualDrivers.Virtual-Display-Driver -e
```

Or download manually:
- Visit: https://github.com/VirtualDrivers/Virtual-Display-Driver/releases
- Download latest `VirtualDisplayDriver_Setup.exe`
- Run installer as Administrator
- Follow installation prompts

**1.2 Install Visual C++ Redistributable (if needed)**

VDD requires Visual C++ Runtime:
- Download from: https://aka.ms/vs/17/release/vc_redist.x64.exe
- Run and install

**1.3 Verify Installation**

Check Device Manager:
- Win + X → Device Manager
- Expand "Display adapters"
- You should see "Virtual Display Driver Adapter"

---

### STEP 2: Create Virtual Monitors for MFDs

**2.1 Launch Virtual Driver Control (VDC)**

- Find VDC in Start Menu or run: `C:\VirtualDisplayDriver\VDC.exe`
- VDC is the configuration app for virtual monitors

**2.2 Create MFD Monitors**

For most aircraft (F/A-18, F-16), you need 2 virtual monitors:

**Left MFD Monitor:**
1. Click **"Add Display"**
2. Set Resolution: **800x800**
3. Set Refresh Rate: **60Hz**
4. (Optional) Set Custom Name: **"DCS_MFD_LEFT"**
5. Click **"Apply"**

**Right MFD Monitor:**
1. Click **"Add Display"** again
2. Set Resolution: **800x800**
3. Set Refresh Rate: **60Hz**
4. (Optional) Set Custom Name: **"DCS_MFD_RIGHT"**
5. Click **"Apply"**

**For A-10C:** Use 600x600 resolution instead of 800x800

**For FA-18C with AMPCD:** Create a 3rd monitor (800x800) for center display

**2.3 Arrange Virtual Monitors**

- Open Windows Display Settings (Win + P, then "Display Settings")
- You should see 2-3 new displays
- Arrange them **away from your main display** to avoid mouse cursor issues
- Recommended: Place them to the far right (e.g., Main @ 0,0; MFD1 @ 3840,0; MFD2 @ 4640,0)
- Click **"Apply"** and **"Keep changes"**

**2.4 Note Monitor Positions**

Write down the positions for later:
- Left MFD Monitor: Display #___, Position: (_____, _____)
- Right MFD Monitor: Display #___, Position: (_____, _____)

---

### STEP 3: Configure DCS MonitorSetup

DCS uses `MonitorSetup.lua` files to define where to render viewports (including MFDs).

**3.1 Locate DCS Config Folder**

Navigate to:
```
%USERPROFILE%\Saved Games\DCS\Config\MonitorSetup
```

Create the `MonitorSetup` folder if it doesn't exist.

**3.2 Copy Example Configuration**

From AccMod installation:
```
C:\HELL\CODE\DCS-AccMod\examples\MonitorSetup_MFD_Example.lua
```

Copy this file to the DCS MonitorSetup folder.

**3.3 Rename for Your Aircraft**

Rename the file to match your aircraft module:
- FA-18C: `FA-18C_hornet.lua`
- F-16C: `F-16C_50.lua`
- A-10C: `A-10C_2.lua`

**3.4 Edit Coordinates**

Open the file in a text editor (Notepad++, VS Code, etc.)

Find viewport [2] (Left MFD):
```lua
[2] = {
    x = 1920,  -- CHANGE THIS to your left MFD monitor X position
    y = 0,     -- CHANGE THIS to your left MFD monitor Y position
    width = 800,
    height = 800,
    -- ... rest stays the same
},
```

Find viewport [3] (Right MFD):
```lua
[3] = {
    x = 2720,  -- CHANGE THIS to your right MFD monitor X position
    y = 0,     -- CHANGE THIS to your right MFD monitor Y position
    width = 800,
    height = 800,
    -- ... rest stays the same
},
```

**Example:** If Windows shows your virtual monitors at:
- Left MFD: Position (3840, 0)
- Right MFD: Position (4640, 0)

Then set:
```lua
[2] = { x = 3840, y = 0, width = 800, height = 800, ... }
[3] = { x = 4640, y = 0, width = 800, height = 800, ... }
```

Save and close the file.

---

### STEP 4: Build AccMod MFD Capture Module

**4.1 Build Native Module**

Open PowerShell in AccMod folder:
```powershell
cd C:\HELL\CODE\DCS-AccMod\native\MFDCapture
.\build.bat
```

This builds the capture library.

**4.2 Build Full AccMod (includes MFD support)**

```powershell
cd C:\HELL\CODE\DCS-AccMod
.\build-all.bat
```

**4.3 Deploy to DCS**

```powershell
.\deploy.bat
```

---

### STEP 5: Test the Setup

**5.1 Test Virtual Monitors**

Before launching DCS, verify virtual monitors work:

```powershell
cd C:\HELL\CODE\DCS-AccMod\native\MFDCapture\build\bin\Release
.\MFDCaptureTest.exe

# Follow prompts to select virtual monitor
# It should enumerate your displays
```

If test shows your virtual monitors, you're good to go!

**5.2 Launch DCS**

1. Start DCS World
2. Enter a mission with your aircraft (FA-18C, F-16C, etc.)
3. Once in cockpit, check if MFDs are rendering to virtual monitors:
   - Alt+Tab and look for the virtual monitor windows
   - They should show the MFD displays

**5.3 Enable MFD Capture in AccMod**

In DCS cockpit:
1. Press **Ctrl+Shift+A** (default AccMod hotkey)
2. AccMod manager UI appears
3. Look for **"MFD Capture"** section
4. Click **"Enable MFD Capture"**
5. Select which MFDs to display (Left, Right, Both)
6. Click **"Start Capture"**

**5.4 Verify Display**

You should now see MFD widgets in AccMod displaying the captured MFDs!

- Move/resize widgets as needed
- Adjust update rate if performance is an issue
- In VR mode, MFDs will appear as floating quads

---

## Troubleshooting

### Virtual monitors not appearing
- **Check:** VDD installed correctly? Look in Device Manager
- **Fix:** Reinstall VDD as Administrator
- **Fix:** Restart Windows after VDD installation

### DCS doesn't render to virtual monitors
- **Check:** MonitorSetup file in correct location?
- **Check:** MonitorSetup filename matches aircraft module name exactly?
- **Check:** Coordinates in MonitorSetup match Windows display positions?
- **Fix:** Delete `C:\Users\[YourName]\Saved Games\DCS\Config\options.lua` (forces DCS to recreate)
- **Fix:** Restart DCS after changing MonitorSetup

### Black screen in MFD widgets
- **Check:** Virtual monitors enabled in VDC?
- **Check:** DCS actually rendering to them? (Alt+Tab to virtual monitor windows)
- **Fix:** Verify display positions in Windows Display Settings
- **Fix:** Try moving virtual monitors to different positions

### Poor performance / Low FPS
- **Fix:** Reduce MFD capture rate in AccMod settings (30 FPS → 15 FPS)
- **Fix:** Disable unused MFDs (only capture what you need)
- **Fix:** Close other GPU-intensive applications
- **Check:** GPU usage in Task Manager - should be <10% overhead

### MFD display is rotated or stretched
- **Fix:** Check virtual monitor resolution matches MonitorSetup (800x800)
- **Fix:** Verify aspect ratio = 1.0 in MonitorSetup
- **Fix:** Check that viewDx and viewDy are both 0

### Capture test fails
- **Error:** "Failed to initialize MFD capture"
- **Fix:** Virtual monitors must be enabled before running test
- **Fix:** Check VDD service is running: `Get-Service -Name "VirtualDisplayDriver"`
- **Fix:** Try specifying monitor by index: `MFDCaptureTest.exe 1`

### DCS doesn't start after MonitorSetup change
- **Fix:** Delete `options.lua` in DCS Saved Games folder
- **Fix:** Remove MonitorSetup file and restart DCS
- **Fix:** Check MonitorSetup Lua syntax (missing commas, brackets)

---

## Performance Tuning

### Optimize Capture Rate

Default: 30 FPS
- For VR: Use 30 FPS (smooth)
- For 2D: Can reduce to 15 FPS (less GPU load)
- For recording: Use 60 FPS

In AccMod settings:
```lua
AccMod.SetMFDCaptureRate(15)  -- Set to 15 FPS
```

### Memory Usage

Each MFD uses ~50MB RAM:
- 2 MFDs: ~100MB
- 3 MFDs: ~150MB

This is minimal and shouldn't impact DCS performance.

### GPU Overhead

Expected overhead:
- Capture: <5% GPU usage
- Display: <3% GPU usage
- Total: <10% GPU for 2 MFDs

If higher, reduce capture rate or resolution.

---

## Aircraft-Specific Guides

### F/A-18C Hornet

**Displays:** LEFT_MFCD, RIGHT_MFCD, AMPCD (3 total)

MonitorSetup filename: `FA-18C_hornet.lua`

Virtual monitors needed:
- 3 monitors @ 800x800

MFD positions in cockpit: Left lower, Right lower, Center lower

### F-16C Viper

**Displays:** LEFT_MFD, RIGHT_MFD (2 total)

MonitorSetup filename: `F-16C_50.lua`

Virtual monitors needed:
- 2 monitors @ 800x800

### A-10C Warthog

**Displays:** LEFT_MFCD, RIGHT_MFCD (2 total)

MonitorSetup filename: `A-10C_2.lua`

Virtual monitors needed:
- 2 monitors @ 600x600 (smaller resolution than others!)

### AH-64D Apache

**Displays:** 4 total (Pilot + CPG each have 2 MFDs)

MonitorSetup filename: `AH-64D_BLK_II.lua`

Virtual monitors needed:
- 4 monitors @ 800x800

---

## Advanced Configuration

### Custom Monitor Names

Edit `vdd_settings.xml`:
```xml
<Display>
    <Name>DCS_MFD_LEFT</Name>
    <Resolution>800x800</Resolution>
    <RefreshRate>60</RefreshRate>
</Display>
```

Then filter by name in code:
```cpp
config.monitorName = L"DCS_MFD_LEFT";
```

### Multi-GPU Systems

If you have multiple GPUs:
1. Set DCS to use main GPU in NVIDIA Control Panel
2. Set VDD to use same GPU
3. Capture will automatically use correct adapter

### Automation Scripts

Create desktop shortcut to launch DCS with MFD capture:
```powershell
# launch-dcs-with-mfds.ps1
# Enable virtual monitors
& "C:\VirtualDisplayDriver\VDC.exe" -enable

# Launch DCS
Start-Process "C:\Program Files\Eagle Dynamics\DCS World\bin\DCS.exe"

# Wait for DCS to start, then enable capture
Start-Sleep -Seconds 30
# TODO: Send hotkey to enable MFD capture
```

---

## Uninstallation

To remove MFD rendering system:

1. **Disable in AccMod**
   - Open AccMod manager
   - Disable MFD capture
   - Close DCS

2. **Remove MonitorSetup**
   - Delete custom MonitorSetup files from DCS Config folder

3. **Disable Virtual Monitors**
   - Open VDC
   - Remove all virtual displays
   - Click Apply

4. **Uninstall VDD** (optional)
   - Open VDC
   - Click "Uninstall Driver"
   - Follow prompts
   - Restart Windows

---

## Support and Feedback

- GitHub Issues: https://github.com/[your-repo]/DCS-AccMod/issues
- DCS Forums: ED Forums → Mods → DCS AccMod Thread
- Discord: [Your Discord Server]

---

## Credits

- Virtual Display Driver: https://github.com/VirtualDrivers/Virtual-Display-Driver
- Microsoft Desktop Duplication API
- DCS World by Eagle Dynamics

---

**Last Updated:** 2026-04-04
**Version:** 1.0.0
