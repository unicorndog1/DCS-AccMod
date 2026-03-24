# AccJoyBridge - C++ Joystick Bridge for DCS AccMod

A high-performance C++ replacement for `hing.py` that monitors joystick input and sends UDP packets to the AccMod system. This DLL can be loaded directly from Lua without requiring Python.

## Features

- DirectInput joystick monitoring
- Button press/release detection
- Axis change detection with threshold
- UDP communication to localhost:7778
- Lua-friendly API
- Thread-based monitoring (non-blocking)
- Automatic cleanup on shutdown

## Building

### Prerequisites

- CMake 3.15 or higher
- Visual Studio 2022 (or compatible C++ compiler)
- Lua 5.1 headers and libraries (LuaJIT compatible)

### Build Steps

1. Open a command prompt in this directory
2. Run `build.bat`
3. The DLL will be output to `build\bin\Release\AccJoyBridge.dll`

### Manual Build

```cmd
mkdir build
cd build
cmake .. -G "Visual Studio 17 2022" -A x64
cmake --build . --config Release
```

## Usage

### From Lua

```lua
-- Load the DLL
local joybridge = require("AccJoyBridge")

-- Start monitoring joystick at index 1
local success, err = joybridge.start(1)
if not success then
    print("Error: " .. err)
end

-- Check if running
if joybridge.isRunning() then
    print("Monitoring active")
end

-- Stop monitoring
joybridge.stop()
```

### In DCS AccMod

Add the DLL path to your Lua package path and require it:

```lua
package.cpath = package.cpath .. ";C:/HELL/CODE/DCS-AccMod/native/AccJoyBridge/build/bin/Release/?.dll"
local joybridge = require("AccJoyBridge")

-- Start monitoring when needed
joybridge.start(1)  -- Use joystick index 1 (same as hing.py)
```

## API Reference

### `joybridge.start(joystickIndex)`

Initializes DirectInput and starts monitoring the specified joystick.

- **Parameters:**
  - `joystickIndex` (number, optional): Zero-based joystick index. Default is 1.
- **Returns:**
  - `success` (boolean): true if started successfully
  - `error` (string, optional): Error message if failed

### `joybridge.stop()`

Stops joystick monitoring and cleans up resources.

- **Returns:**
  - `success` (boolean): Always returns true

### `joybridge.isRunning()`

Checks if the joystick monitor is currently active.

- **Returns:**
  - `running` (boolean): true if monitoring is active

## UDP Message Format

The DLL sends UDP packets to `127.0.0.1:7778` with the following formats:

- Button press: `BTN_<N>_PRESSED`
- Button release: `BTN_<N>_RELEASED`
- Axis change: `AXIS_<N>_<VALUE>` (VALUE is formatted as %.4f)

This matches the exact format used by `hing.py`.

## Differences from hing.py

- **No lock file mechanism**: The DLL doesn't use a lock file. Instance management should be handled by the Lua code.
- **No console output**: Messages are only sent via UDP. For debugging, add logging to the C++ code.
- **Thread-based**: Runs in a background thread, so it won't block Lua execution.

## Troubleshooting

### "Failed to initialize joystick"

- Ensure a joystick is connected at the specified index
- Check that no other application has exclusive access to the joystick
- Verify the joystick index is correct (0-based)

### No UDP packets received

- Check that port 7778 is not blocked by firewall
- Verify the receiving application is listening on 127.0.0.1:7778
- Use Wireshark or similar to verify packets are being sent

### DLL fails to load

- Ensure all dependencies are present (dinput8.dll, ws2_32.dll are system DLLs)
- Check that the Lua version matches (must be Lua 5.1 compatible)
- Verify the DLL architecture matches your Lua environment (must be x64)

## License

Part of the DCS-AccMod project.
