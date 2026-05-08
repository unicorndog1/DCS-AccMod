-- Tracking.lua
-- Contains the UnitHighlightPanel overlay code for DCS Accessibility Widget

local base = _G
local require = base.require
local os = base.os
local math = base.math
local log = require('log')
local Skin = require('Skin')
local Gui = require('dxgui')
local Static = require('Static')
local Panel = require('Panel')

local UnitHighlightPanel = {}
UnitHighlightPanel.__index = UnitHighlightPanel

function UnitHighlightPanel.new()
    local o = {}
    setmetatable(o, UnitHighlightPanel)
    o.window = nil
    o.panel = nil
    o.borderTop = nil
    o.borderBottom = nil
    o.borderLeft = nil
    o.borderRight = nil
    o.infoText = nil
    o.testCircle = nil
    o.lastUpdateTime = 0
    o.lastDebugLog = 0
    o.lastCameraLogTime = 0
    o.detectedUnit = nil
    o.windowWidth = 0
    o.windowHeight = 0
    o.borderThickness = 3
    o.borderColor = "0x00ff00ff"
    return o
end

function UnitHighlightPanel:createWindow()
    local Window = require('Window')
    self.window = Window.new()
    local screenW, screenH = Gui.GetWindowSize()
    self.windowWidth = screenW
    self.windowHeight = screenH
    self.window:setBounds(0, 0, self.windowWidth, self.windowHeight)
    self.window:setText("")
    self.window:setSkin(Skin.windowSkinChatMin())
    self.window:setVisible(true)
    self.window:setHasCursor(false)
    self.panel = Panel.new()
    self.window:insertWidget(self.panel)
    self.panel:setBounds(0, 0, self.windowWidth, self.windowHeight)
    self.infoText = Static.new()
    self.panel:insertWidget(self.infoText)
    self.infoText:setBounds(10, 10, 400, 25)
    self.infoText:setText("Overlay Active - No unit detected")
    local infoSkin = self.infoText:getSkin()
    if not infoSkin.skinData then infoSkin.skinData = { states = { released = { {} } } } end
    if not infoSkin.skinData.states then infoSkin.skinData.states = { released = { {} } } end
    if not infoSkin.skinData.states.released then infoSkin.skinData.states.released = { {} } end
    if not infoSkin.skinData.states.released[1] then infoSkin.skinData.states.released[1] = { text = {} } end
    if not infoSkin.skinData.states.released[1].text then infoSkin.skinData.states.released[1].text = {} end
    infoSkin.skinData.states.released[1].text.fontSize = 24
    infoSkin.skinData.states.released[1].text.color = "0xffffffff"
    self.infoText:setSkin(infoSkin)
    self.borderTop = Static.new()
    self.panel:insertWidget(self.borderTop)
    self.borderBottom = Static.new()
    self.panel:insertWidget(self.borderBottom)
    self.borderLeft = Static.new()
    self.panel:insertWidget(self.borderLeft)
    self.borderRight = Static.new()
    self.panel:insertWidget(self.borderRight)
    self.testCircle = Static.new()
    self.panel:insertWidget(self.testCircle)
    self.circleSize = 80
    self.testCircle:setBounds(0, 0, self.circleSize, self.circleSize)
    self.testCircle:setText("◯")
    local circleSkin = self.testCircle:getSkin()
    if not circleSkin.skinData then circleSkin.skinData = { states = { released = { {} } } } end
    if not circleSkin.skinData.states then circleSkin.skinData.states = { released = { {} } } end
    if not circleSkin.skinData.states.released then circleSkin.skinData.states.released = { {} } end
    if not circleSkin.skinData.states.released[1] then circleSkin.skinData.states.released[1] = { text = {} } end
    if not circleSkin.skinData.states.released[1].text then circleSkin.skinData.states.released[1].text = {} end
    circleSkin.skinData.states.released[1].text.fontSize = 64
    circleSkin.skinData.states.released[1].text.color = "0xff0000ff"
    circleSkin.skinData.states.released[1].color = "0x00000000"
    self.testCircle:setSkin(circleSkin)
    self.testCircle:setVisible(false)
    local debugText = Static.new()
    self.panel:insertWidget(debugText)
    debugText:setBounds(10, 50, 600, 100)
    debugText:setText(string.format("Screen: %dx%d\nOverlay Active\nLooking for units...", self.windowWidth, self.windowHeight))
    local debugSkin = debugText:getSkin()
    if not debugSkin.skinData then debugSkin.skinData = { states = { released = { {} } } } end
    if not debugSkin.skinData.states then debugSkin.skinData.states = { released = { {} } } end
    if not debugSkin.skinData.states.released then debugSkin.skinData.states.released = { {} } end
    if not debugSkin.skinData.states.released[1] then debugSkin.skinData.states.released[1] = { text = {} } end
    if not debugSkin.skinData.states.released[1].text then debugSkin.skinData.states.released[1].text = {} end
    debugSkin.skinData.states.released[1].text.fontSize = 20
    debugSkin.skinData.states.released[1].text.color = "0x00ff00ff"
    debugText:setSkin(debugSkin)
    debugText:setVisible(true)
    self:setBorderColor(self.borderColor)
    self:hideBorders()
    log.write('AccMod', log.INFO, "UnitHighlightPanel created")
end

function UnitHighlightPanel:setBorderColor(colorHex)
    self.borderColor = colorHex
    if not self.borderTop then return end
    local skin = self.borderTop:getSkin()
    if not skin.skinData then skin.skinData = { states = { released = { {} } } } end
    if not skin.skinData.states then skin.skinData.states = { released = { {} } } end
    if not skin.skinData.states.released then skin.skinData.states.released = { {} } end
    if not skin.skinData.states.released[1] then skin.skinData.states.released[1] = {} end
    skin.skinData.states.released[1].color = colorHex
    self.borderTop:setSkin(skin)
    self.borderBottom:setSkin(skin)
    self.borderLeft:setSkin(skin)
    self.borderRight:setSkin(skin)
end

function UnitHighlightPanel:showBorders()
    if not self.borderTop then return end
    local thickness = self.borderThickness
    local w = self.windowWidth
    local h = self.windowHeight
    self.borderTop:setBounds(0, 30, w, thickness)
    self.borderTop:setVisible(true)
    self.borderBottom:setBounds(0, h - thickness, w, thickness)
    self.borderBottom:setVisible(true)
    self.borderLeft:setBounds(0, 30, thickness, h - 30)
    self.borderLeft:setVisible(true)
    self.borderRight:setBounds(w - thickness, 30, thickness, h - 30)
    self.borderRight:setVisible(true)
end

function UnitHighlightPanel:showBordersAroundPosition(centerX, centerY, width, height)
    if not self.borderTop then return end
    local thickness = self.borderThickness
    local halfW = width / 2
    local halfH = height / 2
    local left = centerX - halfW
    local top = centerY - halfH
    local right = centerX + halfW
    local bottom = centerY + halfH
    self.borderTop:setBounds(left, top, width, thickness)
    self.borderTop:setVisible(true)
    self.borderBottom:setBounds(left, bottom - thickness, width, thickness)
    self.borderBottom:setVisible(true)
    self.borderLeft:setBounds(left, top, thickness, height)
    self.borderLeft:setVisible(true)
    self.borderRight:setBounds(right - thickness, top, thickness, height)
    self.borderRight:setVisible(true)
end

function UnitHighlightPanel:hideBorders()
    if not self.borderTop then return end
    self.borderTop:setVisible(false)
    self.borderBottom:setVisible(false)
    self.borderLeft:setVisible(false)
    self.borderRight:setVisible(false)
end

function UnitHighlightPanel:serializeTable(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0
    local tmp = string.rep(" ", depth)
    if name then tmp = tmp .. name .. " = " end
    if type(val) == "table" then
        tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")
        for k, v in pairs(val) do
            tmp = tmp .. self:serializeTable(v, k, skipnewlines, depth + 1) .. "," .. (not skipnewlines and "\n" or "")
        end
        tmp = tmp .. string.rep(" ", depth) .. "}"
    elseif type(val) == "number" then
        tmp = tmp .. tostring(val)
    elseif type(val) == "string" then
        tmp = tmp .. string.format("%q", val)
    elseif type(val) == "boolean" then
        tmp = tmp .. (val and "true" or "false")
    else
        tmp = tmp .. "\"[" .. type(val) .. "]\""
    end
    return tmp
end

function UnitHighlightPanel:worldToScreen(worldPos, cameraAzimuth, cameraElevation)
    local camera = base.Export.LoGetCameraPosition()
    if not camera or not camera.p then return nil, nil end
    
    -- Dump camera object to logs (once every 5 seconds to avoid spam)
    if not self.lastCameraLogTime or (os.clock() - self.lastCameraLogTime) > 5 then
        log.write('AccMod', log.INFO, "=== CAMERA OBJECT DUMP ===")
        -- Dump position
        if camera.p then
            log.write('AccMod', log.INFO, string.format("camera.p (position): x=%.2f, y=%.2f, z=%.2f", camera.p.x, camera.p.y, camera.p.z))
        end
        -- Dump forward vector
        if camera.x then
            log.write('AccMod', log.INFO, string.format("camera.x (forward): x=%.4f, y=%.4f, z=%.4f", camera.x.x, camera.x.y, camera.x.z))
        end
        -- Dump up vector
        if camera.y then
            log.write('AccMod', log.INFO, string.format("camera.y (up): x=%.4f, y=%.4f, z=%.4f", camera.y.x, camera.y.y, camera.y.z))
        end
        -- Dump left vector
        if camera.z then
            log.write('AccMod', log.INFO, string.format("camera.z (left): x=%.4f, y=%.4f, z=%.4f", camera.z.x, camera.z.y, camera.z.z))
        end
        -- Check for any other camera fields
        for key, value in pairs(camera) do
            if key ~= 'p' and key ~= 'x' and key ~= 'y' and key ~= 'z' then
                log.write('AccMod', log.INFO, string.format("camera.%s = %s (%s)", key, tostring(value), type(value)))
            end
        end
        -- Dump entire camera table as serialized string
        log.write('AccMod', log.INFO, "CAMERA SERIALIZED: " .. self:serializeTable(camera, "camera", true))
        log.write('AccMod', log.INFO, "=== END CAMERA DUMP ===")
        self.lastCameraLogTime = os.clock()
    end
    
    local camPos = camera.p
    local camForward = camera.x
    local camUp = camera.y
    local camLeft = camera.z
    local screenW, screenH = Gui.GetWindowSize()
    local dx = worldPos.x - camPos.x
    local dy = worldPos.y - camPos.y
    local dz = worldPos.z - camPos.z
    local localZ = dx * camForward.x + dy * camForward.y + dz * camForward.z
    if localZ <= 0 then return nil, nil end
    local localX = dx * camLeft.x + dy * camLeft.y + dz * camLeft.z
    local localY = dx * camUp.x + dy * camUp.y + dz * camUp.z
    if not self.lastDebugLog or (os.clock() - self.lastDebugLog) > 3 then
        log.write('AccMod', log.INFO, string.format("Camera check - localX:%.1f localY:%.1f localZ:%.1f", localX, localY, localZ))
        self.lastDebugLog = os.clock()
    end
    local fov = 75 * math.pi / 180
    local aspect = screenW / screenH
    local screenX = (localX / localZ) / math.tan(fov / 2) / aspect
    local screenY = (localY / localZ) / math.tan(fov / 2)
    screenX = (screenX + 1) * screenW / 2
    screenY = (1 - screenY) * screenH / 2
    return screenX, screenY
end

function UnitHighlightPanel:update()
    local now = os.clock()
    if now - self.lastUpdateTime < 0.1 then return end
    self.lastUpdateTime = now
    if not self.window then return end
    local winX, winY, winW, winH = self.window:getBounds()
    local worldObjects = base.Export.LoGetWorldObjects()
    if not worldObjects then self:hideBorders(); self.infoText:setText("No world data"); self.detectedUnit = nil; return end
    local selfData = base.Export.LoGetSelfData()
    if not selfData then self:hideBorders(); self.infoText:setText("No camera data"); self.detectedUnit = nil; return end
    local detectedUnit = nil
    local closestDistance = math.huge
    local detectedScreenX = nil
    local detectedScreenY = nil
    for objID, objData in pairs(worldObjects) do
        if objData and objData.Position and objData.Type then
            local screenX, screenY = self:worldToScreen(objData.Position, 0, 0)
            if screenX and screenY then
                if screenX >= 0 and screenX <= winW and screenY >= 0 and screenY <= winH then
                    local dx = objData.Position.x - selfData.Position.x
                    local dy = objData.Position.y - selfData.Position.y
                    local dz = objData.Position.z - selfData.Position.z
                    local distance = math.sqrt(dx*dx + dy*dy + dz*dz)
                    if distance < closestDistance then
                        closestDistance = distance
                        detectedUnit = objData
                        detectedScreenX = screenX
                        detectedScreenY = screenY
                    end
                end
            end
        end
    end
    if detectedUnit and detectedScreenX and detectedScreenY then
        self.detectedUnit = detectedUnit
        self:showBordersAroundPosition(detectedScreenX, detectedScreenY, 100, 100)
        local circleX = detectedScreenX - self.circleSize / 2
        local circleY = detectedScreenY - self.circleSize / 2
        self.testCircle:setBounds(circleX, circleY, self.circleSize, self.circleSize)
        self.testCircle:setVisible(true)
        local unitName = detectedUnit.UnitName or detectedUnit.Name or "Unknown"
        local distance_m = closestDistance
        local distance_km = distance_m / 1000
        local infoStr = string.format("%s (%.1f km)", unitName, distance_km)
        self.infoText:setText(infoStr)
        if detectedUnit.Type then
            if detectedUnit.Type.level2 == 1 then
                self:setBorderColor("0x00ff00ff")
            elseif detectedUnit.Type.level2 == 2 then
                self:setBorderColor("0x00ffffff")
            elseif detectedUnit.Type.level2 == 3 then
                self:setBorderColor("0xffff00ff")
            else
                self:setBorderColor("0xff0000ff")
            end
        end
    else
        self.detectedUnit = nil
        self:hideBorders()
        self.testCircle:setVisible(false)
        self.infoText:setText("No unit detected")
    end
end

function UnitHighlightPanel:closeWindow()
    if self.window then
        self.window:setVisible(false)
        self.window = nil
    end
end

function UnitHighlightPanel:setMode(mode)
    if not self.window then return end
    if mode == "hidden" then
        self.window:setVisible(false)
    else
        self.window:setVisible(true)
    end
end

return {
    UnitHighlightPanel = UnitHighlightPanel
}
