-- Example usage of AccJoyBridge DLL in DCS AccMod
-- This script demonstrates how to start the joystick bridge

local function loadAccJoyBridge()
    -- Add DLL path to Lua's search path
    local dllPath = "C:\\HELL\\CODE\\DCS-AccMod\\native\\AccJoyBridge\\build\\bin\\Release\\?.dll"
    package.cpath = package.cpath .. ";" .. dllPath
    
    -- Load the DLL
    local success, joybridge = pcall(require, "AccJoyBridge")
    if not success then
        log.write("DCS-AccMod", log.ERROR, "Failed to load AccJoyBridge: " .. tostring(joybridge))
        return nil
    end
    
    return joybridge
end

-- Initialize the joystick bridge
local joybridge = loadAccJoyBridge()
if joybridge then
    log.write("DCS-AccMod", log.INFO, "AccJoyBridge loaded successfully")
    
    -- Start monitoring joystick at index 1
    local success, err = joybridge.start(1)
    if success then
        log.write("DCS-AccMod", logINFO, "Joystick monitoring started - sending UDP to 127.0.0.1:7778")
    else
        log.write("DCS-AccMod", log.ERROR, "Failed to start joystick monitoring: " .. tostring(err))
    end
else
    log.write("DCS-AccMod", log.ERROR, "Failed to load AccJoyBridge DLL")
end

-- On shutdown (add this to your cleanup function)
local function cleanup()
    if joybridge then
        joybridge.stop()
        log.write("DCS-AccMod", log.INFO, "Joystick monitoring stopped")
    end
end

return {
    start = function()
        if joybridge and not joybridge.isRunning() then
            return joybridge.start(1)
        end
    end,
    
    stop = function()
        if joybridge then
            return joybridge.stop()
        end
    end,
    
    isRunning = function()
        if joybridge then
            return joybridge.isRunning()
        end
        return false
    end,
    
    cleanup = cleanup
}
