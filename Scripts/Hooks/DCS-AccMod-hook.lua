
-- AccMod Hook - Provides bridge to net.dostring_in for AccMod script
net.log("Loading AccMod Hook...")

-- Create global bridge table accessible from AccMod GUI script
AccModBridge = {}

-- Execute Lua code in specified environment using net.dostring_in
-- env: "mission", "export", "server", or "gui"
-- code: Lua code string to execute
-- Returns: result (string), success (boolean)
function AccModBridge.execInEnv(env, code)
    if not env or not code then
        return "error: missing env or code parameter", false
    end
    
 
     -- Execute in other environment using net.dostring_in
    local result, success = net.dostring_in(env, code)
     return result, success
	
end

-- Log that bridge is ready
net.log("AccModBridge ready - net.dostring_in accessible via AccModBridge.execInEnv()")

-- Make AccModBridge globally accessible
_G.AccModBridge = AccModBridge

-- Load the main AccMod script
status, result = pcall(function() 
    local dcsSr = require('lfs')
    dofile(dcsSr.writedir()..[[Mods\Services\DCS-AccWidg\Scripts\DCS-SRS-AccMod.lua]])
    
    -- Inject AccModBridge directly into the AccMod module if it exists
    if package.loaded.AccMod then
        package.loaded.AccMod.AccModBridge = AccModBridge
        net.log("AccModBridge injected into AccMod module")
    end
end, nil) 

if not status then
    net.log("AccMod Load Error: " .. tostring(result))
else
    net.log("AccMod loaded successfully with bridge")
end