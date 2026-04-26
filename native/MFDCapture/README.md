# MFD Capture Module

This module captures DCS MFD displays rendered to virtual monitors using the Windows Desktop Duplication API.

## Architecture

```
Virtual Monitor → DXGI Output Duplication → ID3D11Texture2D → AccMod Display
```

## Building

```bash
cd native/MFDCapture
mkdir build
cd build
cmake ..
cmake --build . --config Release
```

## Usage

```cpp
#include "MFDCapture.h"

// Initialize capture for virtual monitor 1 (Left MFD)
MFDCapture capture;
MFDCapture::Config config;
config.monitorIndex = 1;  // 0 = primary, 1 = second monitor (virtual)
config.width = 800;
config.height = 800;
config.targetFPS = 30;

if (!capture.Initialize(config)) {
    // Handle error
}

// Capture loop
while (running) {
    ID3D11Texture2D* frame = nullptr;
    if (capture.CaptureFrame(&frame)) {
        // Use frame texture for rendering
        // ...
        capture.ReleaseFrame();
    }
}

capture.Shutdown();
```

## Integration with AccMod

The capture module will be integrated into the AccMod DLL and exposed to Lua:

```lua
-- Enable MFD capture
local leftMFD = AccMod.StartMFDCapture({
    name = "LEFT_MFD",
    monitorIndex = 1,
    updateRate = 30
})

local rightMFD = AccMod.StartMFDCapture({
    name = "RIGHT_MFD", 
    monitorIndex = 2,
    updateRate = 30
})
```

## Performance

Target metrics:
- Capture latency: <16ms
- CPU overhead: <5%
- Memory: ~50MB per MFD
