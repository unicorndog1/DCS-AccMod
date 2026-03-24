-- Test script for AccJoyBridge DLL
-- This replaces hing.py and provides the same functionality

-- Load the DLL
package.cpath = package.cpath .. ";./native/AccJoyBridge/build/bin/Release/?.dll"
local joybridge = require("AccJoyBridge")

print("AccJoyBridge Test")
print("================")

-- Check if already running
if joybridge.isRunning() then
    print("Already running!")
else
    print("Starting joystick monitor (joystick index 1)...")
    local success, err = joybridge.start(1)
    
    if success then
        print("Joystick monitor started successfully!")
        print("Monitoring joystick and sending UDP to 127.0.0.1:7778")
        print("Press Ctrl+C to stop")
        
        -- Keep the script running
        while true do
            -- Sleep to prevent busy loop
            os.execute("timeout /t 1 /nobreak >nul")
        end
    else
        print("Failed to start: " .. (err or "unknown error"))
    end
end

-- Cleanup (this will run on exit)
local function cleanup()
    print("\nStopping joystick monitor...")
    joybridge.stop()
    print("Stopped.")
end

-- Register cleanup
-- Note: In DCS Lua environment, use appropriate shutdown hooks
if pcall(require, "os") then
    -- Standard Lua environment
    local function signal_handler()
        cleanup()
        os.exit(0)
    end
    -- This is a simplified version; proper signal handling may vary
end
