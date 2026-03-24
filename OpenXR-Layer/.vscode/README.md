# VSCode Setup for DCS AccMod OpenXR Layer

This directory contains VSCode configuration for the DCS AccMod OpenXR Layer project.

## Quick Setup

1. Open the workspace: `DCS-AccMod.code-workspace` (in the parent directory)
2. Install recommended extensions when prompted
3. Press `Ctrl+Shift+P` → "Tasks: Run Task" → "Download OpenXR SDK"
4. Press `Ctrl+Shift+B` to build

## Files in this Directory

- **tasks.json** - Build tasks, install/uninstall, log viewing, testing
- **c_cpp_properties.json** - C++ IntelliSense configuration
- **launch.json** - Debug configurations
- **settings.json** - Workspace settings
- **extensions.json** - Recommended extensions

## Available Tasks (Ctrl+Shift+P → Tasks: Run Task)

### Build Tasks
- **Download OpenXR SDK** - Downloads and builds OpenXR SDK (run once)
- **Build OpenXR Layer (Release)** - Builds optimized release (Ctrl+Shift+B default)
- **Build OpenXR Layer (Debug)** - Builds debug version with extra logging
- **Configure CMake** - Runs CMake configuration only
- **Clean Build** - Removes build directory

### Installation Tasks
- **Install Layer** - Registers the layer (requires admin)
- **Uninstall Layer** - Removes the layer (requires admin)
- **Full Build and Install** - Builds and installs in one step

### Testing & Debugging Tasks
- **Test UDP Communication** - Runs test script with Lua
- **View OpenXR Log** - Tails the log file in real-time

## Debugging

### Attach to DCS
1. Launch DCS with the OpenXR layer installed
2. In VSCode: Run → Start Debugging
3. Select "Debug Layer (Attach to DCS)"
4. Choose the DCS process from the list
5. Set breakpoints in `main.cpp` or `render.cpp`

Note: The layer runs early in the OpenXR initialization, so you may need to attach quickly after DCS starts.

### Debug Build
For better debugging experience, build with Debug configuration:
- Tasks → Run Task → Build OpenXR Layer (Debug)
- This includes debug symbols and disables optimizations

## IntelliSense

The C++ extension should automatically detect:
- OpenXR SDK headers
- Windows SDK headers
- Project source files

If IntelliSense isn't working:
1. Check that `OPENXR_SDK_ROOT` is set correctly
2. Update paths in `c_cpp_properties.json`
3. Run: Ctrl+Shift+P → "C/C++: Edit Configurations (UI)"

## Recommended Extensions

Install these for the best experience:
- **C/C++** (ms-vscode.cpptools) - C++ IntelliSense and debugging
- **CMake Tools** (ms-vscode.cmake-tools) - CMake integration
- **CMake** (twxs.cmake) - CMake language support
- **Lua** (sumneko.lua) - Lua language support for scripts
- **PowerShell** (ms-vscode.powershell) - PowerShell script editing

VSCode will prompt you to install these when you open the workspace.

## Keyboard Shortcuts

- `Ctrl+Shift+B` - Build (default: Release)
- `Ctrl+Shift+P` - Command Palette (access all tasks)
- `F5` - Start Debugging
- `Ctrl+Shift+D` - Debug view

## Tips

1. **First build**: Always run "Download OpenXR SDK" task before building
2. **Build errors**: Check the Problems panel (Ctrl+Shift+M)
3. **Log watching**: Use "View OpenXR Log" task to see real-time output
4. **Testing**: Run "Test UDP Communication" to verify UDP setup
5. **Clean slate**: Use "Clean Build" if you encounter strange build issues

## Troubleshooting

### "OpenXR SDK not found"
- Run: Tasks → Download OpenXR SDK
- Or manually set `OPENXR_SDK_ROOT` environment variable

### "CMake not found"
- Install CMake 3.15+ from https://cmake.org/download/
- Or install via Visual Studio Installer → Individual Components → CMake tools

### "Visual Studio generator not found"
- Install Visual Studio 2022 or 2019 with "Desktop development with C++"
- Or edit `tasks.json` and change the generator to your VS version

### IntelliSense errors but builds successfully
- This is often normal - IntelliSense can be overly strict
- Try: Ctrl+Shift+P → "C/C++: Reset IntelliSense Database"
- Or: Reload window (Ctrl+Shift+P → "Developer: Reload Window")

## File Structure

```
DCS-AccMod/
├── DCS-AccMod.code-workspace  # Open this in VSCode
└── OpenXR-Layer/
    ├── .vscode/                # This directory
    │   ├── tasks.json
    │   ├── c_cpp_properties.json
    │   ├── launch.json
    │   ├── settings.json
    │   └── extensions.json
    ├── src/                    # C++ source files
    ├── build/                  # Build output (excluded from view)
    ├── CMakeLists.txt
    ├── download_openxr.bat     # SDK downloader
    └── build.bat               # Command-line build
```
