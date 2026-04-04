# DCS MFD Rendering in AccMod - Implementation Plan

## Overview
This plan outlines how to render DCS MFD displays within the AccMod system by creating virtual monitors, configuring DCS to render MFDs to them, and capturing the rendered output for display in AccMod windows or VR overlay.

## Architecture Summary

```
DCS Engine
    ↓
MonitorSetup.lua (configure MFD viewports → virtual monitors)
    ↓
Virtual Display Driver (creates fake monitors)
    ↓
Desktop Duplication API (captures rendered MFD frames)
    ↓
AccMod Display System (windows/OpenXR layer)
```

## Phase 1: DCS MonitorSetup Configuration

### 1.1 Understanding MonitorSetup
**Location:** `%USERPROFILE%\Saved Games\DCS\Config\MonitorSetup\`

DCS uses MonitorSetup.lua files to define viewports for multi-monitor setups. Each viewport can display:
- Cockpit views
- MFD displays (Left, Right, Center)
- AMPCD (Advanced Multi-Purpose Color Display)
- MFCD (Multi-Function Color Display)
- External views

### 1.2 Create MonitorSetup Configuration
Create a custom MonitorSetup file that defines viewports for MFD exports:

```lua
-- Example structure (to be refined)
_ = function(p)
    return {
        -- Main display
        [1] = {
            x = 0,
            y = 0,
            width = 1920,
            height = 1080
        },
        
        -- Left MFD viewport (to virtual monitor 2)
        [2] = {
            x = 1920,  -- Position on virtual monitor
            y = 0,
            width = 800,
            height = 800,
            viewDx = 0,
            viewDy = 0,
            aspect = 1.0,
            
            -- MFD-specific configuration
            UIMainView = {
                x = 0,
                y = 0,
                width = 800,
                height = 800
            }
        },
        
        -- Right MFD viewport (to virtual monitor 3)
        [3] = {
            x = 2720,
            y = 0,
            width = 800,
            height = 800,
            viewDx = 0,
            viewDy = 0,
            aspect = 1.0
        }
    }
end
```

### 1.3 Research Required
- [ ] Examine existing MonitorSetup files from DCS community
- [ ] Identify correct viewport parameters for MFD extraction
- [ ] Test with different aircraft (F/A-18, F-16, A-10C, etc.)
- [ ] Understand aircraft-specific MFD export IDs

## Phase 2: Virtual Monitor Creation

### 2.1 Virtual Display Driver Setup
**Tool:** [Virtual Display Driver (VDD)](https://github.com/VirtualDrivers/Virtual-Display-Driver)

**Benefits:**
- Creates virtual monitors that Windows treats as real displays
- Custom resolutions (e.g., 800x800 for MFDs)
- No hardware required
- Works with DirectX/DXGI applications

**Installation:**
```powershell
winget install --id=VirtualDrivers.Virtual-Display-Driver -e
```

### 2.2 Configuration via VDD
Create virtual monitors programmatically or via config:

**Option A: Manual via VDC App**
- Install VDD
- Create 2-3 virtual monitors (one per MFD)
- Set resolution to 800x800 or 1024x1024

**Option B: Programmatic (Advanced)**
- Edit `vdd_settings.xml` at `C:\VirtualDisplayDriver\`
- Define monitors with specific resolutions
- Enable/disable via PowerShell scripts

### 2.3 Automation Script
Create `setup_virtual_mfd_monitors.ps1`:
```powershell
# Install VDD if not present
if (-not (Test-Path "C:\VirtualDisplayDriver")) {
    winget install --id=VirtualDrivers.Virtual-Display-Driver -e
}

# Configure 2 MFD monitors (800x800)
# Edit vdd_settings.xml or use VDD API
# Start virtual monitors
```

## Phase 3: Screen Capture Implementation

### 3.1 Desktop Duplication API
**Microsoft DXGI Desktop Duplication** - captures monitor output efficiently

**Key Features:**
- Direct GPU access (no CPU copy)
- Frame-by-frame updates with dirty regions
- Move rectangles for optimized capture
- Hardware cursor handling
- Format: `DXGI_FORMAT_B8G8R8A8_UNORM`

### 3.2 Capture Module Architecture
Create `native/MFDCapture/` project:

```cpp
// mfd_capture.h
class MFDCapture {
public:
    struct CaptureConfig {
        int monitorIndex;      // Which virtual monitor (1=left MFD, 2=right MFD)
        int width;             // Expected resolution (800)
        int height;            // Expected resolution (800)
        int targetFPS;         // Frame capture rate (30 or 60)
    };
    
    // Initialize capture for a specific monitor
    bool Initialize(const CaptureConfig& config);
    
    // Capture next frame (non-blocking)
    bool CaptureFrame(ID3D11Texture2D** outTexture);
    
    // Get frame as raw BGRA bytes
    bool GetFrameData(uint8_t* outBuffer, size_t bufferSize);
    
    // Release resources
    void Shutdown();
    
private:
    ComPtr<IDXGIOutputDuplication> m_deskDupl;
    ComPtr<ID3D11Device> m_device;
    ComPtr<ID3D11DeviceContext> m_context;
    ComPtr<ID3D11Texture2D> m_acquiredFrame;
    int m_outputIndex;
};
```

### 3.3 Implementation Steps
1. **Enumerate Outputs**
   - Use `IDXGIAdapter::EnumOutputs()` to find virtual monitors
   - Identify by name/resolution (800x800)

2. **Create Duplication**
   - Call `IDXGIOutput1::DuplicateOutput()` for each MFD monitor
   - Store `IDXGIOutputDuplication` interface

3. **Capture Loop**
   ```cpp
   HRESULT hr = m_deskDupl->AcquireNextFrame(500, &frameInfo, &desktopResource);
   if (SUCCEEDED(hr)) {
       // Convert to ID3D11Texture2D
       // Process frame
       m_deskDupl->ReleaseFrame();
   }
   ```

4. **Optimization**
   - Use dirty rectangles (`GetFrameDirtyRects()`)
   - Only process changed regions for MFD updates
   - Cache last frame to avoid unnecessary processing

## Phase 4: Integration with AccMod

### 4.1 Display in Window Overlay (Non-VR)
Extend existing widget system in `Mods/Services/DCS-AccWidg/`:

**C++ Side (native/AccMod):**
```cpp
// New widget type: MFDWidget
class MFDWidget : public Widget {
public:
    void SetMFDSource(const std::string& mfdName);  // "LEFT_MFD", "RIGHT_MFD"
    void UpdateTexture(ID3D11Texture2D* capturedFrame);
    void Render(ID3D11DeviceContext* context) override;
    
private:
    MFDCapture m_capture;
    ComPtr<ID3D11ShaderResourceView> m_textureSRV;
    std::string m_mfdIdentifier;
};
```

**Lua Side:**
```lua
-- DCS-SRS-AccMod.lua extension
local mfdWidgets = {}

function InitMFDWidgets()
    mfdWidgets.leftMFD = AccMod.CreateMFDWidget({
        name = "LEFT_MFD",
        position = {x = 100, y = 100},
        size = {width = 400, height = 400},
        monitorIndex = 1  -- First virtual monitor
    })
    
    mfdWidgets.rightMFD = AccMod.CreateMFDWidget({
        name = "RIGHT_MFD",
        position = {x = 550, y = 100},
        size = {width = 400, height = 400},
        monitorIndex = 2  -- Second virtual monitor
    })
end
```

### 4.2 Display in VR (OpenXR Layer)
Extend `OpenXR-Layer/src/render.cpp`:

**Add MFD Quad Layers:**
```cpp
void RenderManager::CreateMFDLayers() {
    // Create quad composition layers for each MFD
    XrCompositionLayerQuad leftMFDLayer = {};
    leftMFDLayer.type = XR_TYPE_COMPOSITION_LAYER_QUAD;
    leftMFDLayer.space = m_referenceSpace;
    
    // Position in VR space (e.g., floating in front of user)
    leftMFDLayer.pose.position = {-0.3f, 0.0f, -0.5f};  // Left side
    leftMFDLayer.pose.orientation = {0, 0, 0, 1};
    leftMFDLayer.size = {0.2f, 0.2f};  // 20cm x 20cm in VR
    
    // Swapchain with captured MFD texture
    leftMFDLayer.subImage.swapchain = m_mfdSwapchains[0];
    leftMFDLayer.subImage.imageRect = {{0, 0}, {800, 800}};
    
    // Add to layers array
    m_layers.push_back(&leftMFDLayer);
}
```

**Update Texture from Capture:**
```cpp
void RenderManager::UpdateMFDTextures() {
    for (int i = 0; i < m_mfdCaptures.size(); ++i) {
        ID3D11Texture2D* capturedFrame = nullptr;
        if (m_mfdCaptures[i]->CaptureFrame(&capturedFrame)) {
            // Copy to OpenXR swapchain texture
            uint32_t imageIndex;
            xrAcquireSwapchainImage(m_mfdSwapchains[i], nullptr, &imageIndex);
            xrWaitSwapchainImage(m_mfdSwapchains[i], &waitInfo);
            
            // Copy capturedFrame to swapchain image
            m_d3d11Context->CopyResource(m_swapchainImages[i][imageIndex], capturedFrame);
            
            xrReleaseSwapchainImage(m_mfdSwapchains[i], nullptr);
        }
    }
}
```

### 4.3 Configuration UI
Add controls to AccMod manager:

```lua
-- In the AccMod UI panel
UI.AddToggle("Enable MFD Capture", function(enabled)
    if enabled then
        InitMFDWidgets()
    else
        DestroyMFDWidgets()
    end
end)

UI.AddSlider("MFD Update Rate", 15, 60, 30, function(fps)
    AccMod.SetMFDCaptureRate(fps)
end)

UI.AddButton("Configure Virtual Monitors", function()
    -- Launch setup script
    os.execute("powershell -File setup_virtual_mfd_monitors.ps1")
end)
```

## Phase 5: Performance Optimization

### 5.1 Rendering Optimizations
- **Frame Rate Control:** Capture MFDs at 30 FPS instead of 60 to reduce overhead
- **Dirty Region Tracking:** Only update changed portions of MFD
- **Asynchronous Capture:** Run capture on separate thread to avoid blocking main loop
- **GPU-Direct Copy:** Keep textures on GPU, avoid CPU readback

### 5.2 Memory Management
- Reuse texture resources between frames
- Release idle capture resources when not in use
- Pool DirectX objects to avoid allocation overhead

### 5.3 Multi-Aircraft Support
Create aircraft-specific MFD configurations:

```lua
local aircraftMFDConfig = {
    ["FA-18C_hornet"] = {
        mfds = {"LEFT_DDI", "RIGHT_DDI", "AMPCD"},
        resolutions = {800, 800, 800}
    },
    ["F-16C_50"] = {
        mfds = {"LEFT_MFD", "RIGHT_MFD", "FCR"},
        resolutions = {800, 800, 640}
    },
    ["A-10C"] = {
        mfds = {"LEFT_MFCD", "RIGHT_MFCD"},
        resolutions = {600, 600}
    }
}
```

## Phase 6: Testing & Validation

### 6.1 Test Cases
- [ ] Virtual monitors created successfully
- [ ] DCS renders to virtual monitors
- [ ] Capture captures frames without artifacts
- [ ] Frame rate acceptable (>30 FPS)
- [ ] Minimal performance impact on DCS
- [ ] MFD displays correctly in AccMod window
- [ ] MFD displays correctly in VR overlay
- [ ] Multiple MFDs work simultaneously
- [ ] Switch aircraft without restart

### 6.2 Performance Metrics
- Capture latency: <16ms (target)
- CPU overhead: <5%
- GPU overhead: <10%
- Memory footprint: <100MB

### 6.3 Compatibility Testing
- Windows 10/11
- Different GPUs (NVIDIA, AMD, Intel)
- VR headsets (Quest, Vive, Index, etc.)
- Multiple aircraft modules

## Phase 7: Documentation & User Setup

### 7.1 User Installation Guide
Create `MFD_SETUP_GUIDE.md`:
1. Install Virtual Display Driver
2. Create virtual monitors via included script
3. Copy MonitorSetup file to DCS Config
4. Enable MFD capture in AccMod UI
5. Launch DCS and enter aircraft
6. Configure MFD positions in AccMod

### 7.2 Troubleshooting Guide
Common issues:
- Virtual monitors not appearing → Check VDD installation
- Black screen in MFD widget → Verify MonitorSetup configuration
- Poor performance → Adjust capture framerate
- MFDs not updating → Check DCS viewport settings

## Technology Stack Summary

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Virtual Monitors | Virtual Display Driver (IddSampleDriver) | Create fake displays for DCS |
| Screen Capture | DirectX DXGI Desktop Duplication API | Capture rendered MFD frames |
| Rendering (Window) | Direct3D 11 / ImGui | Display captured MFDs in widgets |
| Rendering (VR) | OpenXR Composition Layers | Display captured MFDs in VR |
| Configuration | Lua (DCS Export API) | MonitorSetup and widget config |
| Native Code | C++ / CMake | Capture and rendering modules |

## Advantages of This Approach

✅ **No DCS Modification Required** - Uses standard MonitorSetup system  
✅ **Hardware Independent** - Virtual monitors, no physical displays needed  
✅ **Efficient** - GPU-direct capture via DXGI  
✅ **Flexible** - Works in both window and VR modes  
✅ **Multi-MFD Support** - Capture multiple displays simultaneously  
✅ **Low Latency** - Near-realtime with Desktop Duplication API  
✅ **Standard APIs** - Uses Microsoft-provided Windows APIs  

## Alternative Approaches (Not Recommended)

❌ **Direct DCS Hooking** - Too invasive, breaks updates  
❌ **Window Capture (BitBlt)** - Slow, CPU-based, high latency  
❌ **OBS Virtual Camera** - Unnecessary overhead, complex setup  
❌ **Export API Parsing** - MFD content not exposed via Export API  

## Next Steps

1. **Prototype** - Create simple Desktop Duplication capture demo
2. **Test Virtual Monitors** - Set up VDD and verify DCS can render to them
3. **MonitorSetup Research** - Find working MFD export configurations
4. **Integration** - Add capture to existing AccMod native code
5. **UI Development** - Create management interface for MFD widgets
6. **VR Support** - Extend OpenXR layer for MFD quads

## References

- [Virtual Display Driver GitHub](https://github.com/VirtualDrivers/Virtual-Display-Driver)
- [Microsoft Desktop Duplication API](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/desktop-dup-api)
- [Indirect Display Driver Overview](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/indirect-display-driver-model-overview)
- [DCS MonitorSetup Forums](https://forum.dcs.world/forum/1002-monitors-and-video-cards/)
- [OpenXR Composition Layers Spec](https://registry.khronos.org/OpenXR/specs/1.0/html/xrspec.html#composition-layers)
