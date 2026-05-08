
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

function bootstrap(me) 
  package.loaded.AccMod = nil  -- Clear any existing AccMod module

    local dcsSr = require('lfs')
    dofile(dcsSr.writedir()..[[Mods\Services\DCS-AccWidg\Scripts\DCS-SRS-AccMod.lua]])
    
    -- Inject AccModBridge directly into the AccMod module if it exists
    if package.loaded.AccMod then
        package.loaded.AccMod.AccModBridge = AccModBridge
        package.loaded.AccMod.bootstrap = me
        net.log("AccModBridge injected into AccMod module")
    end
end
-- Load the main AccMod script
status, result = pcall(bootstrap, bootstrap) 

if not status then
    net.log("AccMod Load Error: " .. tostring(result))
else
    net.log("AccMod loaded successfully with bridge")
end

-- Set heading for a specific unit by name via mission environment.
-- Returns a status string beginning with "OK" on success, otherwise "ERR:*".
function AccModBridge.setUnitHeading(unitName, groupName, heading)
    if not unitName or not groupName then
        return "ERR:missing_unit_or_group", false
    end

    local numericHeading = tonumber(heading) or 0

    local innerCode = string.format([[ 
local unitName = %q
local groupName = %q
local newHeading = %.6f

local function applyHeadingToPosition(pos, hdg)
    local ch = math.cos(hdg)
    local sh = math.sin(hdg)

    pos.x = pos.x or {}
    pos.y = pos.y or {}
    pos.z = pos.z or {}

    pos.x.x = ch
    pos.x.y = 0
    pos.x.z = sh

    pos.y.x = 0
    pos.y.y = 1
    pos.y.z = 0

    pos.z.x = -sh
    pos.z.y = 0
    pos.z.z = ch

    return pos
end

if not coalition or type(coalition.getGroups) ~= "function" then
    return "ERR:coalition_api", 1
end

for coalitionId = 0, 2 do
    local groups = coalition.getGroups(coalitionId)
    if groups then
        for _, group in ipairs(groups) do
            if group and group:getName() == groupName then
                local units = group:getUnits()
                if units then
                    for _, u in ipairs(units) do
                        if u and u:getName() == unitName then
                            local pos = u:getPosition()
                            if pos and pos.p then
                                pos = applyHeadingToPosition(pos, newHeading)
                                if type(u.setPosition) ~= "function" then
                                    return "ERR:no_set_position", 1
                                end
                                local ok, err = pcall(function() u:setPosition(pos, false) end)
                                if ok then
                                    return "OK", 1
                                else
                                    return "ERR:setPosition_call_failed:" .. tostring(err), 1
                                end
                            end
                            return "ERR:no_position", 1
                        end
                    end
                end
            end
        end
    end
end

return "ERR:not_found", 1
]], unitName, groupName, numericHeading)

    local missionCode = "local a,b= a_do_script([=[" .. innerCode .. "]=]) \n return b"
    local result, success = AccModBridge.execInEnv("mission", missionCode)
    return result, success
end