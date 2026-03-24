
log.write('ACC-OverlayGameGUI', log.INFO, "ACCMODS ")

-- Store original _G to avoid polluting global namespace
local base = _G

package.path  = package.path..";.\\LuaSocket\\?.lua;"..'.\\Scripts\\?.lua;'.. '.\\Scripts\\UI\\?.lua;'
package.cpath = package.cpath..";.\\LuaSocket\\?.dll;"

-- Don't use deprecated module() - it pollutes _G and breaks other mods like SRS
-- Instead, create a local namespace and export it at the end
local AccMod = {}

local require           = base.require
local os                = base.os
--local io                = base.io
local table             = base.table
local string            = base.string
local math              = base.math
local assert            = base.assert
local pairs             = base.pairs
local ipairs             = base.ipairs
local tostring          = base.tostring
local type              = base.type

local lfs               = require('lfs')
local socket            = require("socket") 
local net               = require('net')
local DCS               = require("DCS") 
local U                 = require('me_utilities')
local Skin              = require('Skin')
local Gui               = require('dxgui')
local DialogLoader      = require('DialogLoader')
local Static            = require('Static')
local Button            = require('Button')
local Tools             = require('tools')
local log               = require('log')
local ComboList				= require('ComboList')
local Picture           = require('Picture')
local Align           = require('Align')
local Panel             = require('Panel')
local setmetatable				= base.setmetatable
local _modes = {     
    hidden = "hidden",
    minimum = "minimum",
    minimum_vol =  "minimum_vol",
    txrx_only = "txrx_only",
    full = "full",
}
--[[
local _isWindowCreated = false
local _listenSocket = {}
local _radioState = {}
local self._listStatics = {} -- placeholder objects
local _listMessages = {} -- data
local _lastReceived = 0
]]

local WIDTH = 420
local HEIGHT = 260
local UnitHighlightPanel = {}

JankyJoy = {}
local ImagePanel = {}

-- UDP socket for receiving joystick events
local socket = require("socket")
local JOY_UDP_PORT = 7778
local udp = nil
local lastUdpRebindAttempt = 0

local function bindJoystickUdpSocket()
    -- During script reload, prefer reusing a previously created socket to avoid
    -- bind races where the port is still held by the previous chunk.
    if base.__AccModJoyUdp then
        pcall(function() base.__AccModJoyUdp:settimeout(0) end)
        log.write('AccMod', log.INFO, "Reusing existing joystick UDP socket on 7778")
        return base.__AccModJoyUdp
    end

    local newUdp, err = socket.udp()
    if not newUdp then
        log.write('AccMod', log.ERROR, "UDP create failed: " .. tostring(err))
        return nil
    end

    pcall(function() newUdp:setoption("reuseaddr", true) end)

    local ok, bindErr = newUdp:setsockname("*", JOY_UDP_PORT)
    if not ok then
        log.write('AccMod', log.ERROR, "UDP bind failed on 7778: " .. tostring(bindErr))
        pcall(function() newUdp:close() end)
        return nil
    end

    newUdp:settimeout(0)
    base.__AccModJoyUdp = newUdp
    log.write('AccMod', log.INFO, "Socket up on port 7778")
    return newUdp
end

local function ensureJoystickUdpSocket(force)
    local now = os.clock()
    if not udp and base.__AccModJoyUdp then
        udp = base.__AccModJoyUdp
    end
    if force or not udp then
        if force or (now - lastUdpRebindAttempt) >= 2.0 then
            lastUdpRebindAttempt = now
            udp = bindJoystickUdpSocket()
        end
    end
    return udp ~= nil
end

local function cleanupJoystickUdpSocket()
    if udp then
        pcall(function() udp:close() end)
        udp = nil
    end
    if base.__AccModJoyUdp then
        pcall(function() base.__AccModJoyUdp:close() end)
        base.__AccModJoyUdp = nil
    end
end

ensureJoystickUdpSocket(true)

-- AccJoyBridge DLL loader (C++ replacement for hing.py)
local AccJoyBridge = nil
local function loadAccJoyBridge()
    -- Add bin directory to DLL search path
    local binPath = lfs.writedir() .. "Mods\\Services\\DCS-AccWidg\\bin\\?.dll"
    package.cpath = package.cpath .. ";" .. binPath
    
    -- Try to load the DLL
    local success, joybridge = pcall(require, "AccJoyBridge")
    if not success then
        log.write('AccMod', log.WARNING, "AccJoyBridge DLL not found (C++ joystick bridge). Using external joystick source.")
        return nil
    end
    
    log.write('AccMod', log.INFO, "AccJoyBridge DLL loaded successfully")
    return joybridge
end

-- Initialize AccJoyBridge (starts joystick monitoring)
local function initializeAccJoyBridge()
    AccJoyBridge = loadAccJoyBridge()
    if AccJoyBridge then
        -- Reload-safe start: if the native monitor is still running from a prior chunk,
        -- stop it first so start() doesn't fail with stale state.
        if type(AccJoyBridge.isRunning) == "function" then
            local okRunning, isRunning = pcall(AccJoyBridge.isRunning)
            if okRunning and isRunning then
                pcall(function() AccJoyBridge.stop() end)
                log.write('AccMod', log.INFO, "AccJoyBridge: Stopped previous monitor before restart")
            end
        end

        -- Start monitoring joystick at index 1 (same as hing.py)
        local okStart, success, err = pcall(AccJoyBridge.start, 1)
        if not okStart then
            success = false
            err = "start() exception"
        end
        if success then
            log.write('AccMod', log.INFO, "AccJoyBridge: Joystick monitoring started (joystick index 1)")
        else
            log.write('AccMod', log.ERROR, "AccJoyBridge: Failed to start - " .. tostring(err))
         
        end
    end
end

-- Cleanup function for AccJoyBridge
local function cleanupAccJoyBridge()
    if AccJoyBridge then
        log.write('AccMod', log.INFO, "AccJoyBridge: Stopping joystick monitoring")
        pcall(function() AccJoyBridge.stop() end)
        AccJoyBridge = nil
    end
end

-- Start AccJoyBridge immediately
initializeAccJoyBridge()

-- Current zoom axis value (-1 = zoomed in, 1 = zoomed out)
local currentZoomAxis = 1

-- Manual FOV adjustment (degrees) - added to calculated FOV
local manualFOVOffset = 70
local lastAxisZoomLog = 0
local CLOSEST_RING_MAX_ANGLE_DEG = 5
local CLOSEST_RING_MIN_DOT = math.cos(CLOSEST_RING_MAX_ANGLE_DEG * math.pi / 180)
local WINDOW_RENDER_MODE_OFF = 0
local WINDOW_RENDER_MODE_DOTS_ONLY = 1
local WINDOW_RENDER_MODE_LABELS_AND_DOTS = 2
local WINDOW_RENDER_MODE_DECLUTTER = 3
local WINDOW_RENDER_MODE_COUNT = 4
local LAYER_RENDER_MODE_DOTS_ONLY = 0
local LAYER_RENDER_MODE_DOTS_WITH_LABELS = 1
local LAYER_RENDER_MODE_DOTS_LABELS_CLOSEST_RING = 2
local LAYER_RENDER_MODE_NOTHING = 3

-- LAYER-mode zoom compensation: DCS VR zoom is not exposed in Export API,
-- so apply a calibrated FOV scale while zoom button is held.
local LAYER_BTN_ZOOM_FOV_SCALE = 76 / 20

local function getEffectiveOverlayFovDegrees()
    local effectiveFov = manualFOVOffset

    -- In LAYER mode, the head-locked quad still needs extra compensation while
    -- the zoom button is held, otherwise the markers project too high and become
    -- hard to read even if the axis-thrash bug is fixed.
    if JankyJoy and JankyJoy.zoomButtonOn then
        effectiveFov = effectiveFov * LAYER_BTN_ZOOM_FOV_SCALE
    end

    return math.max(5, math.min(179, effectiveFov))
end

local function logZoomDiagnostics(trigger, msg)
    local camera = base.Export.LoGetCameraPosition()
    local selfData = base.Export.LoGetSelfData()

    local camFov = nil
    if camera then
        camFov = camera.fov or camera.FOV or camera.viewAngle or camera.ViewAngle
    end
    local selfFov = nil
    if selfData then
        selfFov = selfData.fov or selfData.FOV or selfData.viewAngle or selfData.ViewAngle or selfData.CameraFov
    end

    log.write('AccMod', log.INFO,
        string.format("ZOOM_DIAG [%s] msg=%s manualFOV=%.2f effectiveFOV=%.2f axis2=%s camFov=%s selfFov=%s",
            tostring(trigger),
            tostring(msg),
            manualFOVOffset,
            getEffectiveOverlayFovDegrees(),
            tostring(JankyJoy.currentZoomAxis),
            tostring(camFov),
            tostring(selfFov)
        )
    )
end

local function isLayerOverlaySuppressedByZoom()
    return AccModOverlayManager
        and AccModOverlayManager.vrModeEnabled == 2
        and JankyJoy
    and JankyJoy.layerOverlaySuppressed == true
end

local function clearOpenXRLayerOverlay()
    if AccModOverlayManager and AccModOverlayManager.openxrUDP then
        AccModOverlayManager.openxrUDP:sendto("A", "127.0.0.1", 7779)
    end
end

local function getLayerRenderModeName(mode)
    if mode == LAYER_RENDER_MODE_DOTS_ONLY then
        return "Dots only"
    elseif mode == LAYER_RENDER_MODE_DOTS_WITH_LABELS then
        return "Dots with labels"
    elseif mode == LAYER_RENDER_MODE_DOTS_LABELS_CLOSEST_RING then
        return "Dots with labels with closest rings"
    end

    return "Nothing"
end

local function getWindowRenderModeName(mode)
    if mode == WINDOW_RENDER_MODE_OFF then
        return "Off"
    elseif mode == WINDOW_RENDER_MODE_DOTS_ONLY then
        return "Dots only"
    elseif mode == WINDOW_RENDER_MODE_LABELS_AND_DOTS then
        return "Labels and dots"
    elseif mode == WINDOW_RENDER_MODE_DECLUTTER then
        return "Declutter"
    end

    return "Dots only"
end

local function getWindowRenderModeButtonLabel(mode)
    if mode == WINDOW_RENDER_MODE_OFF then
        return "Mode: Off"
    elseif mode == WINDOW_RENDER_MODE_DOTS_ONLY then
        return "Mode: Dots"
    elseif mode == WINDOW_RENDER_MODE_LABELS_AND_DOTS then
        return "Mode: Dots+Lbl"
    elseif mode == WINDOW_RENDER_MODE_DECLUTTER then
        return "Mode: Declut"
    end

    return "Mode: Dots"
end

local function normalizeWindowRenderMode(mode)
    if mode == WINDOW_RENDER_MODE_OFF
        or mode == WINDOW_RENDER_MODE_DOTS_ONLY
        or mode == WINDOW_RENDER_MODE_LABELS_AND_DOTS
        or mode == WINDOW_RENDER_MODE_DECLUTTER then
        return mode
    end

    if mode == 3 then
        return WINDOW_RENDER_MODE_DECLUTTER
    elseif mode == 4 then
        return WINDOW_RENDER_MODE_DOTS_ONLY
    elseif mode == 5 then
        return WINDOW_RENDER_MODE_DECLUTTER
    end

    return WINDOW_RENDER_MODE_DOTS_ONLY
end

local function clampValue(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function rectsOverlap(rectA, rectB, padding)
    local margin = padding or 0
    return not (
        rectA.x + rectA.w + margin <= rectB.x
        or rectB.x + rectB.w + margin <= rectA.x
        or rectA.y + rectA.h + margin <= rectB.y
        or rectB.y + rectB.h + margin <= rectA.y
    )
end

local function pointInRect(px, py, rect, padding)
    local margin = padding or 0
    return px >= rect.x - margin
        and px <= rect.x + rect.w + margin
        and py >= rect.y - margin
        and py <= rect.y + rect.h + margin
end

local function getNearestPointOnRect(px, py, rect)
    return {
        x = clampValue(px, rect.x, rect.x + rect.w),
        y = clampValue(py, rect.y, rect.y + rect.h)
    }
end

local function getOrientation(ax, ay, bx, by, cx, cy)
    local cross = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
    if math.abs(cross) < 0.001 then
        return 0
    end
    if cross > 0 then
        return 1
    end
    return -1
end

local function onSegment(ax, ay, bx, by, px, py)
    return px >= math.min(ax, bx) - 0.001
        and px <= math.max(ax, bx) + 0.001
        and py >= math.min(ay, by) - 0.001
        and py <= math.max(ay, by) + 0.001
end

local function lineSegmentsIntersect(ax, ay, bx, by, cx, cy, dx, dy)
    local o1 = getOrientation(ax, ay, bx, by, cx, cy)
    local o2 = getOrientation(ax, ay, bx, by, dx, dy)
    local o3 = getOrientation(cx, cy, dx, dy, ax, ay)
    local o4 = getOrientation(cx, cy, dx, dy, bx, by)

    if o1 ~= o2 and o3 ~= o4 then
        return true
    end

    if o1 == 0 and onSegment(ax, ay, bx, by, cx, cy) then
        return true
    end
    if o2 == 0 and onSegment(ax, ay, bx, by, dx, dy) then
        return true
    end
    if o3 == 0 and onSegment(cx, cy, dx, dy, ax, ay) then
        return true
    end
    if o4 == 0 and onSegment(cx, cy, dx, dy, bx, by) then
        return true
    end

    return false
end

local function lineIntersectsRect(ax, ay, bx, by, rect, padding)
    local expanded = {
        x = rect.x - (padding or 0),
        y = rect.y - (padding or 0),
        w = rect.w + ((padding or 0) * 2),
        h = rect.h + ((padding or 0) * 2)
    }

    if pointInRect(ax, ay, expanded) or pointInRect(bx, by, expanded) then
        return true
    end

    local left = expanded.x
    local right = expanded.x + expanded.w
    local top = expanded.y
    local bottom = expanded.y + expanded.h

    return lineSegmentsIntersect(ax, ay, bx, by, left, top, right, top)
        or lineSegmentsIntersect(ax, ay, bx, by, right, top, right, bottom)
        or lineSegmentsIntersect(ax, ay, bx, by, right, bottom, left, bottom)
        or lineSegmentsIntersect(ax, ay, bx, by, left, bottom, left, top)
end

local function estimateLabelWidth(text)
    local textLength = string.len(text or "")
    return clampValue(20 + (textLength * 8), 48, 220)
end

local function getDeclutterLabelTextRect(rect)
    local horizontalPadding = 3
    local verticalPadding = 2

    return {
        x = rect.x + horizontalPadding,
        y = rect.y + verticalPadding,
        w = math.max(1, rect.w - (horizontalPadding * 2)),
        h = math.max(1, rect.h - (verticalPadding * 2)),
    }
end

local DECLUTTER_LABEL_RADII = { 56, 78, 102, 128, 156, 188 }
local DECLUTTER_LABEL_ANGLE_OFFSETS = {
    0,
    math.rad(12),
    -math.rad(12),
    math.rad(24),
    -math.rad(24),
    math.rad(36),
    -math.rad(36),
    math.rad(20),
    -math.rad(20),
    math.rad(40),
    -math.rad(40),
    math.rad(52),
    -math.rad(52),
    math.rad(65),
    -math.rad(65),
    math.rad(78),
    -math.rad(78),
    math.rad(90),
    -math.rad(90),
    math.rad(108),
    -math.rad(108),
    math.rad(125),
    -math.rad(125),
    math.rad(142),
    -math.rad(142),
    math.rad(155),
    -math.rad(155),
    math.rad(180),
}
local DECLUTTER_CONNECTOR_DOT_IMAGE = "Mods\\Services\\DCS-AccWidg\\Theme\\connector_dot.png"
local DECLUTTER_CONNECTOR_DOT_SIZE = 3

local function normalizeAngle(angle)
    while angle > math.pi do
        angle = angle - (2 * math.pi)
    end
    while angle < -math.pi do
        angle = angle + (2 * math.pi)
    end
    return angle
end

local function angleDistance(angleA, angleB)
    return math.abs(normalizeAngle(angleA - angleB))
end

local function copyDeclutterRect(rect)
    if not rect then
        return nil
    end

    return {
        x = rect.x,
        y = rect.y,
        w = rect.w,
        h = rect.h,
        desiredCenterX = rect.desiredCenterX,
        desiredCenterY = rect.desiredCenterY,
        radius = rect.radius,
        angle = rect.angle,
    }
end

local function getDetectedUnitKey(unit)
    if unit and unit.unitId ~= nil then
        return tostring(unit.unitId)
    end

    local unitData = unit and unit.data or {}
    return table.concat({
        tostring(unitData.UnitName or unitData.Name or "Unknown"),
        tostring(unit and unit.coalition or 0),
        tostring(unitData.Type and unitData.Type.level1 or 0),
        tostring(unitData.Type and unitData.Type.level2 or 0),
    }, "|")
end

local function appendDeclutterCandidate(candidateList, seenCandidates, angle, radius, reuseBonus)
    local normalizedAngle = normalizeAngle(angle)
    local candidateKey = string.format("%.4f|%.1f", normalizedAngle, radius)
    if seenCandidates[candidateKey] then
        return
    end

    seenCandidates[candidateKey] = true
    table.insert(candidateList, {
        angle = normalizedAngle,
        radius = radius,
        reuseBonus = reuseBonus == true,
    })
end

local function rectOverlapsPlaced(rect, placedRects)
    for _, placedRect in ipairs(placedRects) do
        if rectsOverlap(rect, placedRect, 10) then
            return true
        end
    end

    return false
end

local function countDeclutterLineIssues(unitX, unitY, anchor, placedRects, placedLines)
    local rectIntersections = 0
    local lineCrossings = 0

    for _, placedRect in ipairs(placedRects) do
        if lineIntersectsRect(unitX, unitY, anchor.x, anchor.y, placedRect, 4) then
            rectIntersections = rectIntersections + 1
        end
    end

    for _, placedLine in ipairs(placedLines) do
        if lineSegmentsIntersect(unitX, unitY, anchor.x, anchor.y,
            placedLine.x1, placedLine.y1, placedLine.x2, placedLine.y2) then
            lineCrossings = lineCrossings + 1
        end
    end

    return rectIntersections, lineCrossings
end

local function getSideAwareDeclutterAnchor(unitX, unitY, rect)
    local rectCenterX = rect.x + (rect.w / 2)
    local rectCenterY = rect.y + (rect.h / 2)
    local deltaX = rectCenterX - unitX
    local deltaY = rectCenterY - unitY

    if math.abs(deltaX) >= math.abs(deltaY) then
        return {
            x = deltaX >= 0 and rect.x or (rect.x + rect.w),
            y = clampValue(unitY, rect.y, rect.y + rect.h),
        }
    end

    return {
        x = clampValue(unitX, rect.x, rect.x + rect.w),
        y = deltaY >= 0 and rect.y or (rect.y + rect.h),
    }
end

local function buildDeclutterPolarRect(unitX, unitY, labelWidth, labelHeight, angle, radius, boundsMargin, winW, winH)
    local desiredCenterX = unitX + math.cos(angle) * radius
    local desiredCenterY = unitY + math.sin(angle) * radius
    local rectX = desiredCenterX - (labelWidth / 2)
    local rectY = desiredCenterY - (labelHeight / 2)

    rectX = clampValue(rectX, boundsMargin, math.max(boundsMargin, winW - labelWidth - boundsMargin))
    rectY = clampValue(rectY, boundsMargin, math.max(boundsMargin, winH - labelHeight - boundsMargin))

    return {
        x = rectX,
        y = rectY,
        w = labelWidth,
        h = labelHeight,
        desiredCenterX = desiredCenterX,
        desiredCenterY = desiredCenterY,
        radius = radius,
        angle = angle,
    }
end

local function getLayerRenderModeButtonLabel(mode)
    if mode == LAYER_RENDER_MODE_DOTS_ONLY then
        return "Mode: Dots"
    elseif mode == LAYER_RENDER_MODE_DOTS_WITH_LABELS then
        return "Mode: Dots+Lbl"
    elseif mode == LAYER_RENDER_MODE_DOTS_LABELS_CLOSEST_RING then
        return "Mode: Closest"
    end

    return "Mode: Off"
end

local function getManagerRenderModeButtonText(manager, panel)
    local vrMode = (manager and manager.vrModeEnabled) or 0

    if vrMode == 2 then
        local mode = panel and panel.openxrLayerRenderMode
            or (manager and manager.layerRenderMode)
            or LAYER_RENDER_MODE_DOTS_LABELS_CLOSEST_RING
        return getLayerRenderModeButtonLabel(mode)
    end

    local mode = panel and panel.windowRenderMode
        or (manager and manager.windowRenderMode)
        or WINDOW_RENDER_MODE_DOTS_ONLY
    return getWindowRenderModeButtonLabel(normalizeWindowRenderMode(mode))
end

local function syncManagerRenderModeUi()
    if not AccModOverlayManager then
        return
    end

    local manager = AccModOverlayManager
    local panel = manager.unitHighlightPanel

    if panel then
        panel.windowRenderMode = manager.windowRenderMode or panel.windowRenderMode
        panel.openxrLayerRenderMode = manager.layerRenderMode or panel.openxrLayerRenderMode
    end

    if manager.btnShowLabels then
        manager.btnShowLabels:setText(getManagerRenderModeButtonText(manager, panel))
    end
end

local function ensureUnitHighlightPanelForMode()
    if not AccModOverlayManager then
        return
    end

    local manager = AccModOverlayManager
    local vrMode = manager.vrModeEnabled or 0
    local windowMode = normalizeWindowRenderMode(manager.windowRenderMode or WINDOW_RENDER_MODE_DOTS_ONLY)
    local layerMode = manager.layerRenderMode or LAYER_RENDER_MODE_DOTS_LABELS_CLOSEST_RING
    local shouldEnable = false

    if vrMode == 2 then
        shouldEnable = (layerMode ~= LAYER_RENDER_MODE_NOTHING)
    else
        shouldEnable = (windowMode ~= WINDOW_RENDER_MODE_OFF)
    end

    if not shouldEnable then
        if manager.unitHighlightPanel and manager.unitHighlightPanel.window then
            manager.unitHighlightPanel:closeWindow()
            manager.unitHighlightPanel = nil
            log.write('AccMod', log.INFO, "Unit Highlighter panel disabled by render mode")
        end
        return
    end

    if not manager.unitHighlightPanel or not manager.unitHighlightPanel.window then
        local highlightPanel = UnitHighlightPanel.new()
        highlightPanel.windowRenderMode = windowMode
        highlightPanel.openxrLayerRenderMode = layerMode
        highlightPanel:createWindow()
        manager.unitHighlightPanel = highlightPanel
        log.write('AccMod', log.INFO, "Unit Highlighter panel enabled by render mode")
    else
        manager.unitHighlightPanel.windowRenderMode = windowMode
        manager.unitHighlightPanel.openxrLayerRenderMode = layerMode
    end

    manager.unitHighlightPanel:setMode(_modes.full)
end

local function getCurrentJoyVrMode()
    if AccModOverlayManager and AccModOverlayManager.vrModeEnabled ~= nil then
        return AccModOverlayManager.vrModeEnabled
    end

    return 0
end

local function setJankyJoyButtonState(buttonId, isPressed)
    JankyJoy.buttonStates = JankyJoy.buttonStates or {}
    JankyJoy.buttonStates[buttonId] = isPressed
    JankyJoy.lastButtonEvent = {
        buttonId = buttonId,
        isPressed = isPressed,
        vrMode = getCurrentJoyVrMode(),
    }
end

local function setLayerOverlaySuppressed(isSuppressed)
    JankyJoy.layerOverlaySuppressed = isSuppressed == true
    if JankyJoy.layerOverlaySuppressed then
        clearOpenXRLayerOverlay()
    end
end

local function beginZoomInput(msg)
    JankyJoy.zoomButtonOn = true
    base.Export.LoSetCommand(2012, -0.08)
    manualFOVOffset = 26
    log.write('AccMod', log.INFO, "ZOOMz")
    logZoomDiagnostics("button-pressed", msg)
end

local function endZoomInput(msg)
    JankyJoy.zoomButtonOn = false
    manualFOVOffset = 70
    base.Export.LoSetCommand(2012, 0.9352)
    log.write('AccMod', log.INFO, "UNZOOM")
    logZoomDiagnostics("button-released", msg)
end

local function beginLayerSuppression()
    setLayerOverlaySuppressed(true)
end

local function endLayerSuppression()
    setLayerOverlaySuppressed(false)
end

local function beginLayerSuppressedZoom(msg)
    beginLayerSuppression()
    beginZoomInput(msg)
end

local function endLayerSuppressedZoom(msg)
    endLayerSuppression()
    endZoomInput(msg)
end

local function cycleWindowRenderMode()
    if not AccModOverlayManager then
        return
    end

    local currentMode = normalizeWindowRenderMode(AccModOverlayManager.windowRenderMode or WINDOW_RENDER_MODE_DOTS_ONLY)
    AccModOverlayManager.windowRenderMode = (currentMode + 1) % WINDOW_RENDER_MODE_COUNT
    log.write('AccMod', log.INFO,
        "Window render mode: " .. getWindowRenderModeName(AccModOverlayManager.windowRenderMode))

    ensureUnitHighlightPanelForMode()
    syncManagerRenderModeUi()
end

local function cycleLayerRenderMode()
    if not AccModOverlayManager or AccModOverlayManager.vrModeEnabled ~= 2 then
        return
    end

    AccModOverlayManager.layerRenderMode = ((AccModOverlayManager.layerRenderMode or LAYER_RENDER_MODE_DOTS_LABELS_CLOSEST_RING) + 1) % 4
    log.write('AccMod', log.INFO,
        "OpenXR layer render mode: " .. getLayerRenderModeName(AccModOverlayManager.layerRenderMode))

    ensureUnitHighlightPanelForMode()
    syncManagerRenderModeUi()
end

local JOY_BUTTON_EVENT_HANDLERS = {
    BTN_21 = {
        PRESSED = {
            [0] = beginZoomInput,
            [1] = beginZoomInput,
            [2] = beginLayerSuppression,
        },
        RELEASED = {
            [0] = endZoomInput,
            [1] = endZoomInput,
            [2] = endLayerSuppression,
        },
    },
    BTN_22 = {
        PRESSED = {
            [0] = beginZoomInput,
            [1] = beginZoomInput,
            [2] = beginLayerSuppressedZoom,
        },
        RELEASED = {
            [0] = endZoomInput,
            [1] = endZoomInput,
            [2] = endLayerSuppressedZoom,
        },
    },
    BTN_31 = {
        PRESSED = {
            [0] = cycleWindowRenderMode,
            [1] = cycleWindowRenderMode,
            [2] = cycleLayerRenderMode,
        },
    },
}

local function fireJoyButtonEvent(buttonId, eventState, msg)
    local buttonHandlers = JOY_BUTTON_EVENT_HANDLERS[buttonId]
    if not buttonHandlers then
        return
    end

    local stateHandlers = buttonHandlers[eventState]
    if not stateHandlers then
        return
    end

    local handler = stateHandlers[getCurrentJoyVrMode()] or stateHandlers.default
    if handler then
        handler(msg, buttonId)
    end
end

-- VR camera delta rotation matrix (rotation from aircraft to camera orientation)
-- Stored as 3x3 matrix: {{row1}, {row2}, {row3}}
vrCameraDeltaRotation = nil



-- Matrix math helper functions
-- Multiply 3x3 matrix by 3x1 vector: result = M * v
function matrix_multiply_vector(M, v)
    return {
        M[1][1]*v[1] + M[1][2]*v[2] + M[1][3]*v[3],
        M[2][1]*v[1] + M[2][2]*v[2] + M[2][3]*v[3],
        M[3][1]*v[1] + M[3][2]*v[2] + M[3][3]*v[3]
    }
end

-- Multiply two 3x3 matrices: result = A * B
function matrix_multiply_matrix(A, B)
    local result = {{}, {}, {}}
    for i = 1, 3 do
        for j = 1, 3 do
            result[i][j] = A[i][1]*B[1][j] + A[i][2]*B[2][j] + A[i][3]*B[3][j]
        end
    end
    return result
end

-- Transpose a 3x3 matrix
function matrix_transpose(M)
    return {
        {M[1][1], M[2][1], M[3][1]},
        {M[1][2], M[2][2], M[3][2]},
        {M[1][3], M[2][3], M[3][3]}
    }
end

-- Transform functions defined early so they can be referenced
function tomiles(x)
  return x * 1.94384   
end

function tofeet(x)
  return x*3.28084
end

-- Color list for cycling
local COLOR_LIST = {
	"Red",
	"Black",
	"White",
	"Green",
	"Blue",
	"Yellow",
	"Orange",
	"Cyan",
	"Magenta",
	"Purple"
}

-- Color hex values for text (format: 0xRRGGBBAA)
local COLOR_MAP = {
	Red = "0xff0000ff",
	Black = "0x000000ff",
	White = "0xffffffff",
	Green = "0x00ff00ff",
	Blue = "0x0000ffff",
	Yellow = "0xffff00ff",
	Orange = "0xff8000ff",
	Cyan = "0x00ffffff",
	Magenta = "0xff00ffff",
	Purple = "0x8000ffff"
}

-- Transform functions table with direct function references
local TRANSFORM_FUNCTIONS = {
	{name = "None", func = nil, funcName = ""},
	{name = "Km->Miles", func = tomiles, funcName = "tomiles"},
	{name = "M->Feet", func = tofeet, funcName = "tofeet"}
}

-- PDL gauge calibration: meters of deviation per gauge unit
-- Each gauge position represents this many meters of deviation from center
-- Positions: -4m, -2m, 0m (center), 2m, 4m with step = 2
local GAUGE_STEP_METERS = 4

-- ImagePanel class for displaying images in a subpanel

ImagePanel.__index = ImagePanel

function ImagePanel.new(imagePath)
    local o = {}
    setmetatable(o, ImagePanel)
    o.imagePath = imagePath
    o.window = nil
    o.panel = nil
    o.imageStatic = nil
    o.deviationText = nil  -- Text widget for showing deviations
    o.lastUpdateTime = 0
    o.currentFilename = ""
    o.tankerUnitName = nil  -- Store the tracked tanker unit name
    o.lastSearchTime = 0  -- Track when we last searched for a tanker
    o.mode = _modes.full  -- Current display mode
    o.xbound = 120
    o.ybound = 360
    o.textHeight = 60
    return o
end

function ImagePanel:createWindow()
    -- Create a simple window programmatically
    local Window = require('Window')
    self.window = Window.new()
    self.window:setBounds(100, 100, self.xbound, self.ybound + self.textHeight)
    self.window:setText("PDL Display")
    self.window:setSkin(Skin.windowSkinChatWrite())
    self.window:setVisible(true)
    self.window:setHasCursor(true)
    
    -- Create a panel to hold the widgets
    self.panel = Panel.new()
    self.window:insertWidget(self.panel)
    self.panel:setBounds(0, 0, self.xbound, self.ybound + self.textHeight)
    
    -- Create text widget for displaying deviations
    self.deviationText = Static.new()
    self.panel:insertWidget(self.deviationText)
    self.deviationText:setBounds(5, 5, self.xbound - 10, self.textHeight - 10)
    self.deviationText:setText("No data")
    
    -- Create static widget for displaying the image
    self.imageStatic = Static.new()
    self.panel:insertWidget(self.imageStatic)
    self.imageStatic:setBounds(0, self.textHeight, self.xbound, self.ybound)
    
    self:updateImage(self.imagePath)
    
    log.write('AccMod', log.INFO, "Image panel created with: " .. self.imagePath)
end

function ImagePanel:updateImage(imagePath)
    if not self.imageStatic then
        return
    end
    
    -- Only update if the image has changed
    if imagePath == self.currentFilename then
        return
    end
    
    self.currentFilename = imagePath
    
    -- Create and apply the picture
    local Size = require('Size')
    local picture = Picture.new(
        lfs.writedir() .. imagePath,
        "0xffffffff",  -- White color (no tint)
       Align.new(Align.left),            -- Horizontal alignment
       Align.new(Align.top),            -- Vertical alignment
        Size.new(self.xbound, self.ybound),  -- Size to fit the window
        nil,            -- Rectangle (full image)
        nil,            -- userTexSampler
        true            -- resizeToFill - scale image to fit
    )
    
    -- Apply picture to the static widget's skin
    local skin = self.imageStatic:getSkin()
    if not skin.skinData then
        skin.skinData = { states = { released = { {} } } }
    end
    if not skin.skinData.states then
        skin.skinData.states = { released = { {} } }
    end
    if not skin.skinData.states.released then
        skin.skinData.states.released = { {} }
    end
    if not skin.skinData.states.released[1] then
        skin.skinData.states.released[1] = {}
    end
    
    skin.skinData.states.released[1].picture = picture
    self.imageStatic:setSkin(skin)
end

function ImagePanel:updateFromTanker()
    local now = os.clock()
    
    -- Update every 0.5 seconds
    if now - self.lastUpdateTime < 0.5 then
        return
    end
    
    self.lastUpdateTime = now
    
    -- Get gauge positions from the tracked tanker
    if self.tankerUnitName then
        local duPos_, faPos_,f,v,l = getTankerGaugePosition(self.tankerUnitName)
        local duPos, faPos = getTankerGaugePositionFromDrawArgs(self.tankerUnitName)
        log.write('AccMod', log.INFO, duPos_ .. "," .. faPos_ .. " vs " .. duPos .. "," .. faPos)
        log.write('AccMod', log.INFO, string.format("Offsets F:%.2f m, V:%.2f m, L:%.2f m", f,v,l)) 
        if duPos and faPos then
            -- Convert positions to filename
            local filename = positionsToPDLFilename(duPos, faPos)
            local fullPath = "Mods\\Services\\DCS-AccWidg\\Theme\\" .. filename
            
            -- Update the image
            self:updateImage(fullPath)
            
            -- Calculate distance to tanker for text display
            local selfData = base.Export.LoGetSelfData()
            local distance_km = nil
            if selfData and selfData.Position then
                local worldObjects = base.Export.LoGetWorldObjects()
                if worldObjects then
                    for objID, objData in pairs(worldObjects) do
                        if objData and objData.UnitName == self.tankerUnitName and objData.Position then
                            local dx = objData.Position.x - selfData.Position.x
                            local dz = objData.Position.z - selfData.Position.z
                            local distance_m = math.sqrt(dx*dx + dz*dz)
                            distance_km = distance_m / 1000
                            break
                        end
                    end
                end
            end
            
            -- Check if distance exceeds 10km - auto-close panel if too far
            if distance_km and distance_km > 10 then
                log.write('AccMod', log.INFO, string.format("Distance to tanker %.1f km exceeds 10km threshold - auto-closing PDL panel", distance_km))
                self:closeWindow()
                -- Clear the manager's reference to this panel
                if AccModOverlayManager then
                    AccModOverlayManager.pdlImagePanel = nil
                end
                return
            end
            
            -- Update deviation text based on distance and gauge positions
            if self.deviationText then
                if distance_km then
                    if distance_km <= 5 and duPos == "OFF" and faPos == "OFF" then
                        -- Within 5km and both gauges OFF - prompt for pre-contact
                        self.deviationText:setText("Establish pre-contact")
                    elseif distance_km <= 25 then
                        -- Within 25km - show tracking status
                        self.deviationText:setText(string.format("Tracking tanker: %s", self.tankerUnitName))
                    else
                        -- Beyond 25km but still tracking
                        self.deviationText:setText(string.format("Tanker: %s (%.1f km)", self.tankerUnitName, distance_km))
                    end
                else
                    -- Distance calculation failed but we have gauge data
                    self.deviationText:setText(string.format("Tracking: %s", self.tankerUnitName))
                end
            end
            
        else
            -- Tanker no longer available, clear ID and show OFF image
            log.write('AccMod', log.INFO, "Tanker lost, will re-search in 60 seconds")
            self:updateImage("Mods\\Services\\DCS-AccWidg\\Theme\\pdl_DUOFF_FAOFF.jpg")
            if self.deviationText then
                self.deviationText:setText("No tanker")
            end
            self.tankerUnitName = nil
            self.lastSearchTime = now  -- Start re-search timer
        end
    else
        -- No tanker tracked - check if it's time to search again
        if now - self.lastSearchTime >= 60 then
            -- Re-search for tanker every 60 seconds
            log.write('AccMod', log.INFO, "Re-searching for KC-135 tanker...")
            local forward, vertical, lateral, distance, tankerID, tankerUnitName = findClosestKC135()
         
            self:updateImage("Mods\\Services\\DCS-AccWidg\\Theme\\pdl_DUOFF_FAOFF.jpg")
           
            
            self.lastSearchTime = now
        else
            -- Not time to search yet, show OFF image
            self:updateImage("Mods\\Services\\DCS-AccWidg\\Theme\\pdl_DUOFF_FAOFF.jpg")
            if self.deviationText then
                self.deviationText:setText("Searching...")
            end
        end
    end
end

function ImagePanel:closeWindow()
    if self.window then
        self.window:setVisible(false)
        self.window = nil
    end
end

function ImagePanel:setMode(mode)
    if not self.window then
        return
    end
    
    self.mode = mode
    
    if mode == _modes.hidden or mode == _modes.minimum then
        -- Hidden/minimum mode: hide title bar and text, show only image
        self.window:setText("")  -- Empty title bar
        if self.deviationText then
            self.deviationText:setVisible(false)
        end
        -- Move image to top and resize window to just image size
        if self.imageStatic then
            self.imageStatic:setBounds(0, 0, self.xbound, self.ybound)
        end
        if self.panel then
            self.panel:setBounds(0, 0, self.xbound, self.ybound)
        end
        -- Get current position and resize window
        local x, y, _, _ = self.window:getBounds()
        self.window:setBounds(x, y, self.xbound, self.ybound)
    else
        -- Full mode: show title bar and text
        self.window:setText("PDL Display")
        if self.deviationText then
            self.deviationText:setVisible(true)
        end
        -- Move image back to below text and resize window to full size
        if self.imageStatic then
            self.imageStatic:setBounds(0, self.textHeight, self.xbound, self.ybound)
        end
        if self.panel then
            self.panel:setBounds(0, 0, self.xbound, self.ybound + self.textHeight)
        end
        -- Get current position and resize window
        local x, y, _, _ = self.window:getBounds()
        self.window:setBounds(x, y, self.xbound, self.ybound + self.textHeight)
    end
    
    log.write('AccMod', log.INFO, "ImagePanel mode set to: " .. tostring(mode))
end

-- UnitHighlightPanel class - detects units under cursor and draws hollow rectangle

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
    o.dots = {}  -- Pool of small filled dots for multiple units
    o.ringImages = {}  -- Pool of PNG ring images for multiple units (red)
    o.blueRingImages = {}  -- Pool of blue PNG ring images for allied units
    o.unitLabels = {}  -- Pool of text labels for unit names
    o.labelLeaderDots = {}  -- Pooled 1px leader dots for declutter labels
    o.declutterLayoutCache = {}
    o.declutterDotPictures = {}
    o.labelLeaderDotCount = 16
    o.maxDots = 50  -- Maximum number of dots/rings to create
    o.showUnitLabels = true  -- Flag to show/hide unit name labels
    o.lastUpdateTime = 0
    o.lastDebugLog = 0  -- For debug logging throttle
    o.lastDetectionLog = 0  -- For detection logging throttle
    o.detectedUnits = {}  -- Array of detected units
    o.windowWidth = 0  -- Will be set to screen width on creation
    o.windowHeight = 0  -- Will be set to screen height on creation
    o.borderThickness = 3
    o.borderColor = "0x00ff00ff" -- Green by default
    o.windowRenderMode = WINDOW_RENDER_MODE_DOTS_ONLY
    o.openxrLayerRenderMode = LAYER_RENDER_MODE_DOTS_LABELS_CLOSEST_RING
    o.lastVisibleState = nil
    return o
end

function UnitHighlightPanel:hideAllUnitMarkers()
    for i = 1, #self.dots do
        self.dots[i]:setVisible(false)
        self.ringImages[i]:setVisible(false)
        self.blueRingImages[i]:setVisible(false)
        if self.unitLabels[i] then
            self.unitLabels[i]:setVisible(false)
        end
        if self.labelLeaderDots[i] then
            for _, leaderDot in ipairs(self.labelLeaderDots[i]) do
                leaderDot:setVisible(false)
            end
        end
    end
end

function UnitHighlightPanel:cycleWindowRenderMode()
    local currentMode = normalizeWindowRenderMode(self.windowRenderMode or WINDOW_RENDER_MODE_DOTS_ONLY)
    self.windowRenderMode = (currentMode + 1) % WINDOW_RENDER_MODE_COUNT
    log.write('AccMod', log.INFO,
        "Window render mode: " .. getWindowRenderModeName(self.windowRenderMode))
end

function UnitHighlightPanel:cycleOpenXRLayerRenderMode()
    self.openxrLayerRenderMode = ((self.openxrLayerRenderMode or LAYER_RENDER_MODE_DOTS_LABELS_CLOSEST_RING) + 1) % 4
    log.write('AccMod', log.INFO,
        "OpenXR layer render mode: " .. getLayerRenderModeName(self.openxrLayerRenderMode))
end

function UnitHighlightPanel:getLeaderDotPicture(colorHex)
    local tintColor = colorHex or "0xffffffff"
    self.declutterDotPictures = self.declutterDotPictures or {}

    if not self.declutterDotPictures[tintColor] then
        local Size = require('Size')
        self.declutterDotPictures[tintColor] = Picture.new(
            lfs.writedir() .. DECLUTTER_CONNECTOR_DOT_IMAGE,
            tintColor,
            Align.new(Align.left),
            Align.new(Align.top),
            Size.new(DECLUTTER_CONNECTOR_DOT_SIZE, DECLUTTER_CONNECTOR_DOT_SIZE),
            nil,
            nil,
            true
        )
    end

    return self.declutterDotPictures[tintColor]
end

function UnitHighlightPanel:createWindow()
    local Window = require('Window')
    self.window = Window.new()
    
    -- Get screen dimensions and make window span entire screen
    local screenW, screenH = Gui.GetWindowSize()
    self.windowWidth = screenW
    self.windowHeight = screenH
    
    self.window:setBounds(0, 0, self.windowWidth, self.windowHeight)
    self.window:setText("")  -- No title bar for fullscreen overlay
    self.window:setSkin(Skin.windowSkinChatMin())  -- Minimal skin with no decoration
    self.window:setVisible(true)
    self.window:setHasCursor(false)  -- Disable cursor so it doesn't interfere with gameplay
    
    -- Create main panel
    self.panel = Panel.new()
    self.window:insertWidget(self.panel)
    self.panel:setBounds(0, 0, self.windowWidth, self.windowHeight)
    
    -- Create info text at top-left corner of screen
    self.infoText = Static.new()
    self.panel:insertWidget(self.infoText)
    self.infoText:setBounds(10, 10, 400, 25)
    self.infoText:setText("Overlay Active - No unit detected")
    
    -- Style the info text with large white text
    local infoSkin = self.infoText:getSkin()
    if not infoSkin.skinData then
        infoSkin.skinData = { states = { released = { {} } } }
    end
    if not infoSkin.skinData.states then
        infoSkin.skinData.states = { released = { {} } }
    end
    if not infoSkin.skinData.states.released then
        infoSkin.skinData.states.released = { {} }
    end
    if not infoSkin.skinData.states.released[1] then
        infoSkin.skinData.states.released[1] = { text = {} }
    end
    if not infoSkin.skinData.states.released[1].text then
        infoSkin.skinData.states.released[1].text = {}
    end
    infoSkin.skinData.states.released[1].text.fontSize = 24
    infoSkin.skinData.states.released[1].text.color = "0xffffffff"  -- White
    self.infoText:setSkin(infoSkin)
    
    -- Create border rectangles (initially hidden)
    self.borderTop = Static.new()
    self.panel:insertWidget(self.borderTop)
    
    self.borderBottom = Static.new()
    self.panel:insertWidget(self.borderBottom)
    
    self.borderLeft = Static.new()
    self.panel:insertWidget(self.borderLeft)
    
    self.borderRight = Static.new()
    self.panel:insertWidget(self.borderRight)
    
    -- Create pool of dots and ring images for multiple units
    self.dotSize = 100
    local Size = require('Size')
    for i = 1, self.maxDots do
        -- Create PNG ring image (larger)
        local ringImage = Static.new()
        self.panel:insertWidget(ringImage)

        
        -- Create Picture object following updateImage pattern
        local picture = Picture.new(
            lfs.writedir() .. "Mods\\Services\\DCS-AccWidg\\Theme\\circle_red.png",
            "0xffffffff",  -- White color (no tint)
       Align.new(Align.left),            -- Horizontal alignment
       Align.new(Align.top),            -- Vertical alignment
            Size.new(self.dotSize, self.dotSize),  -- Size to fit the widget
            nil,            -- Rectangle (full image)
            nil,            -- userTexSampler
            true            -- resizeToFill - scale image to fit
        )
        
        local ringSkin = ringImage:getSkin()
        if not ringSkin.skinData then
            ringSkin.skinData = { states = { released = { {} } } }
        end
        if not ringSkin.skinData.states then
            ringSkin.skinData.states = { released = { {} } }
        end
        if not ringSkin.skinData.states.released then
            ringSkin.skinData.states.released = { {} }
        end
        if not ringSkin.skinData.states.released[1] then
            ringSkin.skinData.states.released[1] = {}
        end
        ringSkin.skinData.states.released[1].picture = picture
        ringSkin.skinData.states.released[1].color = "0x00000000"  -- Transparent background
        ringImage:setSkin(ringSkin)
        ringImage:setVisible(false)
        table.insert(self.ringImages, ringImage)
        
        -- Create blue PNG ring image for allied units
        local blueRingImage = Static.new()
        self.panel:insertWidget(blueRingImage)

        
        -- Create Picture object for blue ring
        local bluePicture = Picture.new(
            lfs.writedir() .. "Mods\\Services\\DCS-AccWidg\\Theme\\circle_blue.png",
            "0xffffffff",  -- White color (no tint)
       Align.new(Align.left),            -- Horizontal alignment
       Align.new(Align.top),            -- Vertical alignment
            Size.new(self.dotSize, self.dotSize),  -- Size to fit the widget
            nil,            -- Rectangle (full image)
            nil,            -- userTexSampler
            true            -- resizeToFill - scale image to fit
        )
        
        local blueRingSkin = blueRingImage:getSkin()
        if not blueRingSkin.skinData then
            blueRingSkin.skinData = { states = { released = { {} } } }
        end
        if not blueRingSkin.skinData.states then
            blueRingSkin.skinData.states = { released = { {} } }
        end
        if not blueRingSkin.skinData.states.released then
            blueRingSkin.skinData.states.released = { {} }
        end
        if not blueRingSkin.skinData.states.released[1] then
            blueRingSkin.skinData.states.released[1] = {}
        end
        blueRingSkin.skinData.states.released[1].picture = bluePicture
        blueRingSkin.skinData.states.released[1].color = "0x00000000"  -- Transparent background
        blueRingImage:setSkin(blueRingSkin)
        blueRingImage:setVisible(false)
        table.insert(self.blueRingImages, blueRingImage)
        
        -- Create small filled dot (fixed size, always visible)
        local dot = Static.new()
        self.panel:insertWidget(dot)
        dot:setBounds(0, 0, self.dotSize, self.dotSize)
        dot:setText("●")  -- Unicode filled dot
        
        -- Style the filled dot with red text
        local dotSkin = dot:getSkin()
        if not dotSkin.skinData then
            dotSkin.skinData = { states = { released = { {} } } }
        end
        if not dotSkin.skinData.states then
            dotSkin.skinData.states = { released = { {} } }
        end
        if not dotSkin.skinData.states.released then
            dotSkin.skinData.states.released = { {} }
        end
        if not dotSkin.skinData.states.released[1] then
            dotSkin.skinData.states.released[1] = { text = {} }
        end
        if not dotSkin.skinData.states.released[1].text then
            dotSkin.skinData.states.released[1].text = {}
        end
        dotSkin.skinData.states.released[1].text.fontSize = 5
        dotSkin.skinData.states.released[1].text.color = "0xffff00ff"  -- Red
        dotSkin.skinData.states.released[1].color = "0x00000000"  -- Transparent background
        dot:setSkin(dotSkin)
        dot:setVisible(false)  -- Hidden until unit detected
        
        table.insert(self.dots, dot)
        
        -- Create unit name label (text above ring)
        local label = Static.new()
        self.panel:insertWidget(label)
        label:setBounds(0, 0, 200, 20)
        label:setText("")
        
        -- Style the label text
        local labelSkin = label:getSkin()
        if not labelSkin.skinData then
            labelSkin.skinData = { states = { released = { {} } } }
        end
        if not labelSkin.skinData.states then
            labelSkin.skinData.states = { released = { {} } }
        end
        if not labelSkin.skinData.states.released then
            labelSkin.skinData.states.released = { {} }
        end
        if not labelSkin.skinData.states.released[1] then
            labelSkin.skinData.states.released[1] = { text = {} }
        end
        if not labelSkin.skinData.states.released[1].text then
            labelSkin.skinData.states.released[1].text = {}
        end
        labelSkin.skinData.states.released[1].text.fontSize = 14
        labelSkin.skinData.states.released[1].text.color = "0xffffffff"  -- White
        labelSkin.skinData.states.released[1].text.horzAlign = {0, 0, 0}
        labelSkin.skinData.states.released[1].color = "0x00000000"  -- Transparent background
        label:setSkin(labelSkin)
        label:setVisible(false)
        
        table.insert(self.unitLabels, label)

        local leaderDots = {}
        for dotIndex = 1, self.labelLeaderDotCount do
            local leaderDot = Static.new()
            self.panel:insertWidget(leaderDot)
            leaderDot:setBounds(0, 0, DECLUTTER_CONNECTOR_DOT_SIZE, DECLUTTER_CONNECTOR_DOT_SIZE)

            local leaderSkin = leaderDot:getSkin()
            if not leaderSkin.skinData then
                leaderSkin.skinData = { states = { released = { {} } } }
            end
            if not leaderSkin.skinData.states then
                leaderSkin.skinData.states = { released = { {} } }
            end
            if not leaderSkin.skinData.states.released then
                leaderSkin.skinData.states.released = { {} }
            end
            if not leaderSkin.skinData.states.released[1] then
                leaderSkin.skinData.states.released[1] = {}
            end
            leaderSkin.skinData.states.released[1].picture = self:getLeaderDotPicture("0xffffffff")
            leaderSkin.skinData.states.released[1].color = "0x00000000"
            leaderDot:setSkin(leaderSkin)
            leaderDot:setVisible(false)
            table.insert(leaderDots, leaderDot)
        end

        table.insert(self.labelLeaderDots, leaderDots)
    end
    
    -- Add debug info text showing screen dimensions
    local debugText = Static.new()
    self.panel:insertWidget(debugText)
    debugText:setBounds(10, 50, 600, 100)
    debugText:setText(string.format("Screen: %dx%d\\nOverlay Active\\nLooking for units...", 
        self.windowWidth, self.windowHeight))
    local debugSkin = debugText:getSkin()
    if not debugSkin.skinData then
        debugSkin.skinData = { states = { released = { {} } } }
    end
    if not debugSkin.skinData.states then
        debugSkin.skinData.states = { released = { {} } }
    end
    if not debugSkin.skinData.states.released then
        debugSkin.skinData.states.released = { {} }
    end
    if not debugSkin.skinData.states.released[1] then
        debugSkin.skinData.states.released[1] = { text = {} }
    end
    if not debugSkin.skinData.states.released[1].text then
        debugSkin.skinData.states.released[1].text = {}
    end
    debugSkin.skinData.states.released[1].text.fontSize = 20
    debugSkin.skinData.states.released[1].text.color = "0x00ff00ff"  -- Green
    debugText:setSkin(debugSkin)
    debugText:setVisible(true)
    
    -- Set initial border colors
    self:setBorderColor(self.borderColor)
    self:hideBorders()
    
    log.write('AccMod', log.INFO, "UnitHighlightPanel created")
end

function UnitHighlightPanel:setBorderColor(colorHex)
    self.borderColor = colorHex
    
    if not self.borderTop then return end
    
    -- Create a colored skin for the borders
    local skin = self.borderTop:getSkin()
    if not skin.skinData then
        skin.skinData = { states = { released = { {} } } }
    end
    if not skin.skinData.states then
        skin.skinData.states = { released = { {} } }
    end
    if not skin.skinData.states.released then
        skin.skinData.states.released = { {} }
    end
    if not skin.skinData.states.released[1] then
        skin.skinData.states.released[1] = {}
    end
    
    -- Set background color for each border
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
    
    -- Top border
    self.borderTop:setBounds(0, 30, w, thickness)
    self.borderTop:setVisible(true)
    
    -- Bottom border
    self.borderBottom:setBounds(0, h - thickness, w, thickness)
    self.borderBottom:setVisible(true)
    
    -- Left border
    self.borderLeft:setBounds(0, 30, thickness, h - 30)
    self.borderLeft:setVisible(true)
    
    -- Right border
    self.borderRight:setBounds(w - thickness, 30, thickness, h - 30)
    self.borderRight:setVisible(true)
end

function UnitHighlightPanel:showBordersAroundPosition(centerX, centerY, width, height)
    if not self.borderTop then return end
    
    local thickness = self.borderThickness
    local halfW = width / 2
    local halfH = height / 2
    
    -- Calculate rectangle bounds centered on the unit's screen position
    local left = centerX - halfW
    local top = centerY - halfH
    local right = centerX + halfW
    local bottom = centerY + halfH
    
    -- Top border
    self.borderTop:setBounds(left, top, width, thickness)
    self.borderTop:setVisible(true)
    
    -- Bottom border
    self.borderBottom:setBounds(left, bottom - thickness, width, thickness)
    self.borderBottom:setVisible(true)
    
    -- Left border
    self.borderLeft:setBounds(left, top, thickness, height)
    self.borderLeft:setVisible(true)
    
    -- Right border
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

function UnitHighlightPanel:drawDottedLeaderLine(leaderDots, x1, y1, x2, y2, colorHex)
    if not leaderDots then
        return
    end

    local dx = x2 - x1
    local dy = y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    local spacing = 6
    local visibleDots = 0
    local halfDotSize = DECLUTTER_CONNECTOR_DOT_SIZE / 2

    if length > 2 then
        visibleDots = math.min(#leaderDots, math.max(1, math.floor(length / spacing)))
    end

    for index, leaderDot in ipairs(leaderDots) do
        if index <= visibleDots then
            local t = index / (visibleDots + 1)
            local dotX = math.floor(x1 + (dx * t) - halfDotSize + 0.5)
            local dotY = math.floor(y1 + (dy * t) - halfDotSize + 0.5)
            leaderDot:setBounds(dotX, dotY, DECLUTTER_CONNECTOR_DOT_SIZE, DECLUTTER_CONNECTOR_DOT_SIZE)

            if leaderDots.currentColor ~= colorHex or index > (leaderDots.visibleCount or 0) then
                local leaderSkin = leaderDot:getSkin()
                leaderSkin.skinData.states.released[1].picture = self:getLeaderDotPicture(colorHex)
                leaderSkin.skinData.states.released[1].color = "0x00000000"
                leaderDot:setSkin(leaderSkin)
            end
            leaderDot:setVisible(true)
        else
            leaderDot:setVisible(false)
        end
    end

    leaderDots.currentColor = colorHex
    leaderDots.visibleCount = visibleDots
end

function UnitHighlightPanel:renderDeclutteredLabels(detectedUnits, selfData, winW, winH)
    local playerCoalition = (selfData and selfData.Coalition) or 2
    local labelHeight = 20
    local boundsMargin = 10
    local placedRects = {}
    local placedLines = {}
    local labelUnits = {}
    local previousLayoutCache = self.declutterLayoutCache or {}
    local nextLayoutCache = {}
    local screenCenterX = winW / 2
    local screenCenterY = winH / 2

    for _, unit in ipairs(detectedUnits) do
        table.insert(labelUnits, unit)
    end

    table.sort(labelUnits, function(left, right)
        local leftCache = previousLayoutCache[getDetectedUnitKey(left)]
        local rightCache = previousLayoutCache[getDetectedUnitKey(right)]

        if leftCache and rightCache and leftCache.order ~= rightCache.order then
            return leftCache.order < rightCache.order
        end
        if leftCache and not rightCache then
            return true
        end
        if rightCache and not leftCache then
            return false
        end

        if left.distance == right.distance then
            return (left.facingDot or 0) > (right.facingDot or 0)
        end
        return left.distance < right.distance
    end)

    for labelIndex, unit in ipairs(labelUnits) do
        local label = self.unitLabels[labelIndex]
        local leaderDots = self.labelLeaderDots[labelIndex]

        if label then
            local unitKey = getDetectedUnitKey(unit)
            local cacheEntry = previousLayoutCache[unitKey]
            local unitName = unit.data.Name or "Unknown"
            local labelWidth = estimateLabelWidth(unitName)
            local bestRect = nil
            local bestAnchor = nil
            local bestCost = nil
            local candidatePlacements = {}
            local seenCandidates = {}

            local outwardAngle = math.atan2(unit.screenY - screenCenterY, unit.screenX - screenCenterX)
            if outwardAngle == 0 and unit.screenX == screenCenterX and unit.screenY == screenCenterY then
                outwardAngle = ((labelIndex - 1) / math.max(1, #labelUnits)) * math.pi * 2
            end

            if cacheEntry and cacheEntry.angle and cacheEntry.radius then
                local cachedRect = buildDeclutterPolarRect(
                    unit.screenX,
                    unit.screenY,
                    labelWidth,
                    labelHeight,
                    cacheEntry.angle,
                    cacheEntry.radius,
                    boundsMargin,
                    winW,
                    winH
                )
                local cachedAnchor = getSideAwareDeclutterAnchor(unit.screenX, unit.screenY, getDeclutterLabelTextRect(cachedRect))

                if not rectOverlapsPlaced(cachedRect, placedRects) then
                    bestRect = cachedRect
                    bestAnchor = cachedAnchor
                    bestCost = -1000
                end
            end

            if bestRect == nil and cacheEntry and cacheEntry.angle and cacheEntry.radius then
                appendDeclutterCandidate(candidatePlacements, seenCandidates, cacheEntry.angle, cacheEntry.radius, true)
                for _, radius in ipairs(DECLUTTER_LABEL_RADII) do
                    appendDeclutterCandidate(candidatePlacements, seenCandidates, cacheEntry.angle, radius, radius == cacheEntry.radius)
                end
                for _, angleOffset in ipairs(DECLUTTER_LABEL_ANGLE_OFFSETS) do
                    appendDeclutterCandidate(candidatePlacements, seenCandidates, cacheEntry.angle + angleOffset, cacheEntry.radius, angleOffset == 0)
                end
            end

            if bestRect == nil then
                for _, radius in ipairs(DECLUTTER_LABEL_RADII) do
                    for _, angleOffset in ipairs(DECLUTTER_LABEL_ANGLE_OFFSETS) do
                        appendDeclutterCandidate(candidatePlacements, seenCandidates, outwardAngle + angleOffset, radius, false)
                    end
                end
            end

            for _, candidate in ipairs(candidatePlacements) do
                    local candidateAngle = candidate.angle
                    local radius = candidate.radius
                    local rect = buildDeclutterPolarRect(
                        unit.screenX,
                        unit.screenY,
                        labelWidth,
                        labelHeight,
                        candidateAngle,
                        radius,
                        boundsMargin,
                        winW,
                        winH
                    )
                    local anchor = getSideAwareDeclutterAnchor(unit.screenX, unit.screenY, getDeclutterLabelTextRect(rect))
                    local cost = angleDistance(outwardAngle, candidateAngle) * 80
                        + (radius * 0.25)

                    local outwardCos = math.cos(outwardAngle)
                    local outwardSin = math.sin(outwardAngle)
                    local candidateCos = math.cos(candidateAngle)
                    local candidateSin = math.sin(candidateAngle)

                    if math.abs(outwardCos) >= math.abs(outwardSin) then
                        if outwardCos * candidateCos < 0 then
                            cost = cost + 180
                        end
                    elseif outwardSin * candidateSin < 0 then
                        cost = cost + 180
                    end

                    if cacheEntry and cacheEntry.angle and cacheEntry.radius then
                        cost = cost
                            + (angleDistance(cacheEntry.angle, candidateAngle) * 60)
                            + (math.abs(cacheEntry.radius - radius) * 0.6)

                        if cacheEntry.rect then
                            local previousRectCenterX = cacheEntry.rect.x + (cacheEntry.rect.w / 2)
                            local previousRectCenterY = cacheEntry.rect.y + (cacheEntry.rect.h / 2)
                            local rectCenterX = rect.x + (rect.w / 2)
                            local rectCenterY = rect.y + (rect.h / 2)
                            local driftX = rectCenterX - previousRectCenterX
                            local driftY = rectCenterY - previousRectCenterY
                            cost = cost + math.sqrt(driftX * driftX + driftY * driftY) * 1.5
                        end
                    end

                    if candidate.reuseBonus then
                        cost = cost - 800
                    end

                    if rectOverlapsPlaced(rect, placedRects) then
                        cost = cost + 200000
                    else
                        local rectIntersections, lineCrossings = countDeclutterLineIssues(
                            unit.screenX,
                            unit.screenY,
                            anchor,
                            placedRects,
                            placedLines
                        )
                        cost = cost
                            + (rectIntersections * 1400)
                            + (lineCrossings * 450)
                    end

                    local anchorDx = anchor.x - unit.screenX
                    local anchorDy = anchor.y - unit.screenY
                    local clampDx = rect.x + (rect.w / 2) - rect.desiredCenterX
                    local clampDy = rect.y + (rect.h / 2) - rect.desiredCenterY
                    cost = cost
                        + math.sqrt(anchorDx * anchorDx + anchorDy * anchorDy) * 0.2
                        + math.sqrt(clampDx * clampDx + clampDy * clampDy) * 0.6

                    if bestCost == nil or cost < bestCost then
                        bestRect = rect
                        bestAnchor = anchor
                        bestCost = cost
                    end
                end

            if not bestRect then
                bestRect = buildDeclutterPolarRect(
                    unit.screenX,
                    unit.screenY,
                    labelWidth,
                    labelHeight,
                    outwardAngle,
                    DECLUTTER_LABEL_RADII[1],
                    boundsMargin,
                    winW,
                    winH
                )
                bestAnchor = getSideAwareDeclutterAnchor(unit.screenX, unit.screenY, getDeclutterLabelTextRect(bestRect))
            end

            local isAllied = (unit.coalition == playerCoalition)
            local labelColor = isAllied and "0x0000ffff" or "0xff0000ff"

            label:setText(unitName)
            label:setBounds(bestRect.x, bestRect.y, bestRect.w, bestRect.h)
            local labelSkin = label:getSkin()
            labelSkin.skinData.states.released[1].text.color = labelColor
            label:setSkin(labelSkin)
            label:setVisible(true)

            self:drawDottedLeaderLine(leaderDots, unit.screenX, unit.screenY, bestAnchor.x, bestAnchor.y, labelColor)

            table.insert(placedRects, bestRect)
            table.insert(placedLines, {
                x1 = unit.screenX,
                y1 = unit.screenY,
                x2 = bestAnchor.x,
                y2 = bestAnchor.y,
            })

            nextLayoutCache[unitKey] = {
                angle = bestRect.angle,
                radius = bestRect.radius,
                rect = copyDeclutterRect(bestRect),
                order = labelIndex,
            }
        end
    end

    self.declutterLayoutCache = nextLayoutCache

    for index = #labelUnits + 1, #self.unitLabels do
        self.unitLabels[index]:setVisible(false)
        if self.labelLeaderDots[index] then
            for _, leaderDot in ipairs(self.labelLeaderDots[index]) do
                leaderDot:setVisible(false)
            end
        end
    end
end

-- Check if a world position is within the camera's forward-facing cone
-- Returns: dot product (1.0 = directly ahead, -1.0 = directly behind)
function UnitHighlightPanel:getForwardFacingDot(worldPos, camera)
    if not camera or not camera.p or not camera.x then
        return 1.0  -- Default to visible if no camera data
    end
    
    -- Direction from camera to target
    local dx = worldPos.x - camera.p.x
    local dy = worldPos.y - camera.p.y
    local dz = worldPos.z - camera.p.z
    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
    
    if dist < 1e-6 then
        return 1.0  -- Target at camera position
    end
    
    -- Normalize direction vector
    dx = dx / dist
    dy = dy / dist
    dz = dz / dist
    
    -- Camera forward vector (camera.x)
    local fx = camera.x.x
    local fy = camera.x.y
    local fz = camera.x.z
    
    -- Dot product: 1.0 = directly ahead, 0.0 = 90 degrees, -1.0 = behind
    local dotProduct = dx * fx + dy * fy + dz * fz
    
    return dotProduct
end

function UnitHighlightPanel:worldToScreen(worldPos, cameraAzimuth, cameraElevation)
    local screenW, screenH = Gui.GetWindowSize()
    -- VR offset only applies in mode 1 (window overlay). In mode 2 (LAYER), the quad
    -- is head-locked in VIEW space so it already tracks the camera perfectly.
    local vrMode = AccModOverlayManager and AccModOverlayManager.vrModeEnabled == 1 and AccModOverlayManager.vrCameraOffsetLocal

    local fov        = getEffectiveOverlayFovDegrees() * math.pi / 180
    local aspect     = screenW / screenH
    local tanHalfFov = math.tan(fov / 2)
    --log.write('AccMod', log.INFO, string.format("FOV: %.1f degrees, Aspect: %.2f", manualFOVOffset, aspect))

    local camera
    if vrMode then
        camera = AccModOverlayManager:getVRCameraAdjustedForAircraft()
    end
    if not camera then
        camera = base.Export.LoGetCameraPosition()
    end
    if not camera or not camera.p then return nil, nil end
OVERLAY_DISTANCE = .75
    if vrMode then
        -- Plane fixed to aircraft, OVERLAY_DISTANCE in front of camera
        local planeOrigin = {
            x = camera.p.x + camera.x.x * OVERLAY_DISTANCE,
            y = camera.p.y + camera.x.y * OVERLAY_DISTANCE,
            z = camera.p.z + camera.x.z * OVERLAY_DISTANCE,
        }
        local planeNormal = camera.x  -- plane faces aircraft forward

        -- Ray from aircraft-fixed eye to world object (stable, no headset noise)
local eyePos =  camera.p

        local ray = {
            x = worldPos.x - eyePos.x,
            y = worldPos.y - eyePos.y,
            z = worldPos.z - eyePos.z,
        }
        local rayLen = math.sqrt(ray.x^2 + ray.y^2 + ray.z^2)
        if rayLen < 1e-6 then return nil, nil end
        ray.x = ray.x / rayLen
        ray.y = ray.y / rayLen
        ray.z = ray.z / rayLen
        local denom = planeNormal.x * ray.x + planeNormal.y * ray.y + planeNormal.z * ray.z
        if math.abs(denom) < 1e-6 then return nil, nil end

local toPlane = {
    x = planeOrigin.x - eyePos.x,
    y = planeOrigin.y - eyePos.y,
    z = planeOrigin.z - eyePos.z,
}
        local t = (planeNormal.x * toPlane.x + planeNormal.y * toPlane.y + planeNormal.z * toPlane.z) / denom
        if t <= 0 then return nil, nil end
--log.write('AccMod', log.INFO, string.format("eyePos: %.2f %.2f %.2f  camera.p: %.2f %.2f %.2f t: %.2f",
  --  eyePos.x, eyePos.y, eyePos.z, camera.p.x, camera.p.y, camera.p.z, t))
local hit = {
    x = eyePos.x + ray.x * t,
    y = eyePos.y + ray.y * t,
    z = eyePos.z + ray.z * t,
}
--log.write('AccMod', log.INFO, string.format(
--    "toPlane: %.4f %.4f %.4f  denom: %.6f  t: %.6f",
--    toPlane.x, toPlane.y, toPlane.z, denom, t))
        local dx = hit.x - planeOrigin.x
        local dy = hit.y - planeOrigin.y
        local dz = hit.z - planeOrigin.z

        local localX = dx * camera.z.x + dy * camera.z.y + dz * camera.z.z
        local localY = dx * camera.y.x + dy * camera.y.y + dz * camera.y.z

        local halfH  = OVERLAY_DISTANCE * tanHalfFov
        local halfW  = halfH * aspect

        local screenX = (localX / halfW + 1) * screenW / 2
        local screenY = (1 - localY / halfH)  * screenH / 2

        return screenX, screenY
    else
        local dx = worldPos.x - camera.p.x
        local dy = worldPos.y - camera.p.y
        local dz = worldPos.z - camera.p.z

        local localZ = dx * camera.x.x + dy * camera.x.y + dz * camera.x.z
        if localZ <= 0 then return nil, nil end

        local localX = dx * camera.z.x + dy * camera.z.y + dz * camera.z.z
        local localY = dx * camera.y.x + dy * camera.y.y + dz * camera.y.z

        local screenX = ((localX / localZ) / tanHalfFov / aspect + 1) * screenW / 2
        local screenY = (1 - (localY / localZ) / tanHalfFov)           * screenH / 2

        return screenX, screenY
    end
end
-- At module level
local smoothedEyePos = nil
local EYE_SMOOTH_ALPHA = 0.1  -- lower = smoother, higher = more responsive

function getSmoothedEyePos()
    local trueCamera = base.Export.LoGetCameraPosition()
    if not trueCamera or not trueCamera.p then return nil end

    if not smoothedEyePos then
        smoothedEyePos = {x = trueCamera.p.x, y = trueCamera.p.y, z = trueCamera.p.z}
    else
        smoothedEyePos.x = smoothedEyePos.x + EYE_SMOOTH_ALPHA * (trueCamera.p.x - smoothedEyePos.x)
        smoothedEyePos.y = smoothedEyePos.y + EYE_SMOOTH_ALPHA * (trueCamera.p.y - smoothedEyePos.y)
        smoothedEyePos.z = smoothedEyePos.z + EYE_SMOOTH_ALPHA * (trueCamera.p.z - smoothedEyePos.z)
    end

    return smoothedEyePos
end
function UnitHighlightPanel:worldToScreen2(worldPos, cameraAzimuth, cameraElevation)
    -- Get camera position - use adjusted camera in VR mode that follows aircraft
    local camera
    -- VR offset only applies in mode 1 (window overlay). In mode 2 (LAYER), the quad
    -- is head-locked in VIEW space so it already tracks the camera perfectly.
    if AccModOverlayManager and AccModOverlayManager.vrModeEnabled == 1 and AccModOverlayManager.vrCameraOffsetLocal then
        camera = AccModOverlayManager:getVRCameraAdjustedForAircraft()
    end
    
    if not camera then
        camera = base.Export.LoGetCameraPosition()
    end
    
    if not camera or not camera.p then
        return nil, nil
    end
    
    -- Camera position
    local camPos = base.Export.LoGetCameraPosition().p
    
    -- Camera orientation vectors per DCS documentation:
    -- camera.x = front/forward axis
    -- camera.y = up axis
    -- camera.z = left axis (so right = -left)
    local camForward = camera.x
    local camUp = camera.y
    local camLeft = camera.z
    
    -- Get screen dimensions
    local screenW, screenH = Gui.GetWindowSize()
    
    -- Calculate relative position from camera to unit (world space)
    local dx = worldPos.x - camPos.x
    local dy = worldPos.y - camPos.y
    local dz = worldPos.z - camPos.z
    
    -- Transform to camera space using camera orientation vectors
    -- Forward (depth) - how far in front of camera
    local localZ = dx * camForward.x + dy * camForward.y + dz * camForward.z
    
    -- Check if behind camera
    if localZ <= 0 then
        return nil, nil
    end
    
    -- Horizontal - using camera.z (LEFT vector) directly
    -- Positive localX = target to the left, Negative = target to the right
    local localX = dx * camLeft.x + dy * camLeft.y + dz * camLeft.z
    
    -- Up (vertical)
    local localY = dx * camUp.x + dy * camUp.y + dz * camUp.z
    

    -- FOV: Calculate dynamically based on zoom axis from socket plus manual offset
    -- Zoom axis ranges from -1 (zoomed in) to 1 (zoomed out)
    -- FOV ranges from 20 degrees (zoomed in at -1) to 120 degrees (zoomed out at 1)
    -- Manual offset allows adjustment via buttons (+/- 5° per click, ±50° range)
    local fovDegrees = manualFOVOffset  -- Base FOV with manual adjustment
    local fov = fovDegrees * math.pi / 180  -- Convert to radians
    local aspect = screenW / screenH
  --  log.write('AccMod', log.INFO, string.format("FOV: %.1f degrees, Aspect: %.2f", manualFOVOffset, aspect))
    -- Project to screen space
    -- Negate localX because positive localX (left) should map to negative screenX (left)
    local screenX = (localX / localZ) / math.tan(fov / 2) / aspect
    local screenY = (localY / localZ) / math.tan(fov / 2)
    
    -- Convert to pixel coordinates (-1 to 1 -> 0 to screenW/H)
    screenX = (screenX + 1) * screenW / 2
    screenY = (1 - screenY) * screenH / 2
    
    return screenX, screenY
end

-- Detect and collect all visible units (core detection logic)
-- Returns: detectedUnits table, or nil if no world/player data available
function UnitHighlightPanel:detectUnits()
    local now = os.clock()
    
    if not self.window then
        return nil
    end
    
    -- Get window bounds for screen projection
    local winX, winY, winW, winH = self.window:getBounds()
    
    -- Get all world objects
    local worldObjects = base.Export.LoGetWorldObjects()
    if not worldObjects then
        return nil, "No world data"
    end
    
    -- Get player data for camera info
    local selfData = base.Export.LoGetSelfData()
    if not selfData then
        return nil, "No camera data"
    end
    
    -- Collect all visible units (excluding static objects)
    local detectedUnits = {}
    local unitCount = 0
    local totalCandidates = 0
    local onScreenCount = 0
    local losFailedCount = 0
    
    -- Check each unit - find all visible on screen
    for objID, objData in pairs(worldObjects) do
        if objData and objData.Position and objData.Type then
            -- Skip static objects (Type.level1 == 4 means structure/static)
          --  log.write('AccMod', log.INFO, string.format("Checking object ID:%s Type level1:%d", objData.Name, objData.Type.level1))
            local valid = {[0]=false, [1]=true, [2]=true, [3]=true,[4]=false,[5]=false}
            local valid2 = {[1]=true, [2]=true ,[4]=true,[17]=true,[16]=true,[20]=true,[12]=true}
            if valid[objData.Type.level1] and valid2[objData.Type.level2] then
                totalCandidates = totalCandidates + 1
                
                -- Convert world position to screen position
                local screenX, screenY = self:worldToScreen(objData.Position, 0, 0)
                
                if screenX and screenY then
                    -- Check if screen position is within screen bounds
                    if screenX >= 0 and screenX <= winW and
                       screenY >= 0 and screenY <= winH then
                        onScreenCount = onScreenCount + 1
                        
                        -- Check line of sight from player to unit
                        local hasLOS = true
                        local objName = objData.UnitName or objData.Name
                        if selfData.Position and objData.Position then
                            hasLOS = hasFullLOS(selfData.Position, objData.Position, objName)
                            if not hasLOS then
                                losFailedCount = losFailedCount + 1
                            end
                        end
                        
                        -- Only show units with LOS
                        if hasLOS then
                            -- Calculate distance for info display
                            local dx = objData.Position.x - selfData.Position.x
                            local dy = objData.Position.y - selfData.Position.y
                            local dz = objData.Position.z - selfData.Position.z
                            local distance = math.sqrt(dx*dx + dy*dy + dz*dz)
                            
                            -- Check if unit is within forward-facing cone
                            local camera = base.Export.LoGetCameraPosition()
                            local facingDot = self:getForwardFacingDot(objData.Position, camera)
                            
                            -- Skip units beyond 10km (10000 meters)
                            if distance <= 10000 then
                                unitCount = unitCount + 1
                        --        log.write('AccMod', log.INFO, string.format("Unit visible: %s at %.1fm, screen[%.1f,%.1f]",
                        --            objData.UnitName or objData.Name or "unknown", distance, screenX, screenY))
                                
                                table.insert(detectedUnits, {
                                    data = objData,
                                    unitId = objID,
                                    screenX = screenX,
                                    screenY = screenY,
                                    distance = distance,
                                    coalition = objData.Coalition or 0,
                                    facingDot = facingDot  -- Store dot product for rendering
                                })
                            end
                            
                            -- Stop if we reach max dots
                            if unitCount >= self.maxDots then
                                log.write('AccMod', log.WARNING, "Max dots reached, stopping detection")
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Log detection summary every 2 seconds to avoid spam
    if not self.lastDetectionLog or (now - self.lastDetectionLog) >= 2 then
       -- log.write('AccMod', log.INFO, string.format("Detection: %d candidates, %d on-screen, %d LOS-blocked, %d visible",
       --     totalCandidates, onScreenCount, losFailedCount, unitCount))
        self.lastDetectionLog = now
    end
    
    return detectedUnits, nil, selfData
end

-- Render units using window overlay (VR Mode 1)
function UnitHighlightPanel:renderWindowOverlay(detectedUnits, selfData)
    if not self.window then
        return
    end
    
    local winX, winY, winW, winH = self.window:getBounds()
    local windowRenderMode = normalizeWindowRenderMode(self.windowRenderMode or WINDOW_RENDER_MODE_DOTS_ONLY)
    local renderNothingInWindow = windowRenderMode == WINDOW_RENDER_MODE_OFF
    local showDotsInWindow = windowRenderMode == WINDOW_RENDER_MODE_DOTS_ONLY
        or windowRenderMode == WINDOW_RENDER_MODE_LABELS_AND_DOTS
        or windowRenderMode == WINDOW_RENDER_MODE_DECLUTTER
    local showLabelsInWindow = self.showUnitLabels ~= false and (
        windowRenderMode == WINDOW_RENDER_MODE_LABELS_AND_DOTS
        or windowRenderMode == WINDOW_RENDER_MODE_DECLUTTER
    )
    local showDeclutterInWindow = windowRenderMode == WINDOW_RENDER_MODE_DECLUTTER

    if renderNothingInWindow then
        self:hideAllUnitMarkers()
        return
    end
    
    -- Update dots and ring images for each detected unit
    for i, unit in ipairs(detectedUnits) do
        
        if i <= #self.dots then
            -- Determine if unit is allied (same coalition as player)
            local playerCoalition = selfData.Coalition or 2  -- Default to blue if unknown
            local isAllied = (unit.coalition == playerCoalition)
            
            -- Scale ring image size based on distance (closer = bigger, further = smaller)
            local scaleFactor = 70/manualFOVOffset -- Adjust this value to tune appearance
            local minSize = 75 * scaleFactor 
            local furthest = 1000
            local maxSize = 200 *scaleFactor
            local closest = 25 -- Beyond this distance, 


            
            local ringSize = minSize + (maxSize - minSize) *
        (1-(math.min(furthest, math.max(unit.distance,closest))-closest)/(furthest-closest))
            
            -- Set colors based on coalition
            local dotColor = isAllied and "0x0000ffff" or "0xff0000ff"  -- Blue for allied, red for enemy
            
            -- Position and show small filled dot
            local dot = self.dots[i]
            local dotDisplaySize = 10  -- Fixed small size
            local dotX = unit.screenX - dotDisplaySize / 2
            local dotY = unit.screenY - dotDisplaySize / 2
            dot:setBounds(dotX, dotY, dotDisplaySize+10, dotDisplaySize+10)
            
            -- Update dot color based on coalition
            local dotSkin = dot:getSkin()
            dotSkin.skinData.states.released[1].text.color = dotColor
            dot:setSkin(dotSkin)
            
            -- Use PNG ring images with distance-based visibility
            -- Choose blue or red ring based on coalition
            local ringImage = isAllied and self.blueRingImages[i] or self.ringImages[i]
            local otherRingImage = isAllied and self.ringImages[i] or self.blueRingImages[i]
            
            local ringX = unit.screenX - ringSize /2
            local ringY = unit.screenY - ringSize /2
            ringImage:setBounds(ringX-10, ringY-10, ringSize+10, ringSize+10)
            
            -- Hide the other ring image
            otherRingImage:setVisible(false)
            
            -- Update unit label if enabled
            if showDeclutterInWindow and self.unitLabels[i] then
                self.unitLabels[i]:setVisible(false)
            elseif showLabelsInWindow and self.unitLabels[i] then
                local label = self.unitLabels[i]
                local unitName = unit.data.Name or "Unknown"
                label:setText(unitName)
                
                -- Position label based on whether we're showing dot or ring
                local labelWidth = 200
                local labelHeight = 20
                local labelX = unit.screenX 
                local labelY = unit.screenY - labelHeight / 2
                
                if showDotsInWindow then
                    -- Dot mode: position right above the dot
                    labelY = unit.screenY - dotDisplaySize / 2
                end
                
                label:setBounds(labelX, labelY, labelWidth, labelHeight)
                
                -- Update label color based on coalition
                local labelSkin = label:getSkin()
                local labelColor = isAllied and "0x0000ffff" or "0xff0000ff"  -- Blue for allied, red for enemy
                labelSkin.skinData.states.released[1].text.color = labelColor
                label:setSkin(labelSkin)
                label:setVisible(true)
            elseif self.unitLabels[i] then
                self.unitLabels[i]:setVisible(false)
            end

            if self.labelLeaderDots[i] then
                for _, leaderDot in ipairs(self.labelLeaderDots[i]) do
                    leaderDot:setVisible(false)
                end
            end
            
            -- Distance-based visibility for PNG ring images and dot
            ringImage:setVisible(false)

            dot:setVisible(showDotsInWindow)

            
        end
    end

    if showDeclutterInWindow then
        self:renderDeclutteredLabels(detectedUnits, selfData, winW, winH)
    end
    
    -- Hide unused dots and ring images
    for i = #detectedUnits + 1, #self.dots do
        self.dots[i]:setVisible(false)
        self.ringImages[i]:setVisible(false)
        self.blueRingImages[i]:setVisible(false)
        if self.unitLabels[i] then
            self.unitLabels[i]:setVisible(false)
        end
        if self.labelLeaderDots[i] then
            for _, leaderDot in ipairs(self.labelLeaderDots[i]) do
                leaderDot:setVisible(false)
            end
        end
    end
end

-- Render units using OpenXR layer (VR Mode 2)
function UnitHighlightPanel:renderOpenXRLayer(detectedUnits, selfData)
    if not AccModOverlayManager or not AccModOverlayManager.openxrUDP then
        return
    end

    if isLayerOverlaySuppressedByZoom() then
        clearOpenXRLayerOverlay()
        return
    end
    
    if not selfData then
        return
    end
    
    local playerCoalition = selfData.Coalition or 2
    local winW, winH = Gui.GetWindowSize()
    local layerRenderMode = self.openxrLayerRenderMode or LAYER_RENDER_MODE_DOTS_LABELS_CLOSEST_RING
    local renderNothingInLayer = layerRenderMode == LAYER_RENDER_MODE_NOTHING
    local showLabelsInLayer = self.showUnitLabels ~= false
        and layerRenderMode ~= LAYER_RENDER_MODE_DOTS_ONLY
    local showClosestRingInLayer = layerRenderMode == LAYER_RENDER_MODE_DOTS_LABELS_CLOSEST_RING

    if renderNothingInLayer then
        clearOpenXRLayerOverlay()
        self:hideAllUnitMarkers()
        return
    end

    -- Send view config so the OpenXR layer can size the quad to match our projection
    local tanHalfFov = math.tan(getEffectiveOverlayFovDegrees() * math.pi / 180 / 2)
    local aspect = winW / winH
    local eyeVis = 0  -- Always use both eyes
    
    -- Fixed distance: quad positioned at -1.0 meter
    local distance = 100
    
    AccModOverlayManager.openxrUDP:sendto(
        string.format("V,%.4f,%.4f,%d,%.4f", tanHalfFov, aspect, eyeVis, distance), "127.0.0.1", 7779)

    -- Clear all circles first
    clearOpenXRLayerOverlay()
    
    -- Find the unit closest to camera gaze (highest facingDot value)
    local closestUnitIndex = nil
    local highestFacingDot = -1

    if showClosestRingInLayer then
        for i, unit in ipairs(detectedUnits) do
            local facingDot = unit.facingDot or 1.0
            if facingDot > highestFacingDot then
                highestFacingDot = facingDot
                closestUnitIndex = i
            end
        end

        -- If gaze is farther than 20 degrees from the best candidate, don't show a ring.
        if highestFacingDot < CLOSEST_RING_MIN_DOT then
            closestUnitIndex = nil
        end
    end
    
    -- Send each detected unit
    for i, unit in ipairs(detectedUnits) do
        -- Normalize screen coordinates to 0.0-1.0
        local normX = unit.screenX / winW
        local normY = unit.screenY / winH
        
        -- Determine alliance and color
        local isAllied = (unit.coalition == playerCoalition)
        local r, g, b, a
        if isAllied then
            r, g, b, a = 0.0, 0.0, 1.0, 0.8 -- Blue for allied
        else
            r, g, b, a = 1.0, 0.0, 0.0, 0.8 -- Red for enemy
        end
        
        local radius
        local filledFlag
        
        -- Check if this is the closest unit to camera gaze
        if showClosestRingInLayer and i == closestUnitIndex then
            -- Render as a full circle/ring
            local scaleFactor = distance
            local furthest = 10000

            if unit.distance > furthest then
                -- Distant contact: render as a very small filled marker
                radius = 5
                filledFlag = 1
            else
                -- Normal contact: render as ring
                radius = math.max(50, 1000*100*scaleFactor/unit.distance)
                filledFlag = 0
            end
        else
            -- Default layer mode renders contacts as small filled dots.
            radius = 5
            filledFlag = 1
            if showClosestRingInLayer then
                a = a * 0.6  -- Dim the dots slightly when a closest ring is active
            end
        end
        
        -- Normalize radius to 0.0-1.0 range (assuming max screen dimension)
        -- Scale to 1/2 size for LAYER mode (no screen-space UI scaling applies)
        local normRadius = (radius / math.max(winW, winH)) * 0.25
        -- Ring thickness: thicker for better visibility (6% of radius)
        local normThickness = normRadius * 0.06
        
        -- Get unit type for label (only if enabled)
        local unitType = ""
        if showLabelsInLayer then
            unitType = unit.data.Name or "Unknown"
        end
     
        -- Send UDP packet: "C,x,y,radius,r,g,b,a,filled,thickness,label"
        local packet = string.format("C,%.4f,%.4f,%.4f,%.2f,%.2f,%.2f,%.2f,%d,%.4f,%s",
            normX, normY, normRadius, r, g, b, a, filledFlag, normThickness, unitType)
        
        AccModOverlayManager.openxrUDP:sendto(packet, "127.0.0.1", 7779)
        
        -- Log first circle for debugging (only occasionally to avoid spam)
        if i == 1 and (not self.lastUDPLog or (os.clock() - self.lastUDPLog) >= 2) then
            --   log.write('AccMod', log.INFO, string.format("Sent to OpenXR: %s", packet))
            self.lastUDPLog = os.clock()
        end
    end
    
    -- Hide all window overlay elements in LAYER mode
    self:hideAllUnitMarkers()
end

-- Main update function - orchestrates detection and rendering
function UnitHighlightPanel:update()
    local now = os.clock()
    
    -- Update every 0.1 seconds (60 FPS)
    if now - self.lastUpdateTime < (1.0/60) then
        return
    end
    
    self.lastUpdateTime = now
    
    -- Phase 1: Detect units
    local detectedUnits, errorMsg, selfData = self:detectUnits()
    
    -- Handle detection errors
    if not detectedUnits then
        self:hideBorders()
        self.infoText:setText(errorMsg or "No data")
        self.detectedUnits = {}
        self:hideAllUnitMarkers()
        return
    end
    
    -- Store detected units for external access
    self.detectedUnits = detectedUnits
    
    -- Phase 2: Render based on VR mode
    local vrMode = AccModOverlayManager and AccModOverlayManager.vrModeEnabled or 0
    
    if vrMode == 0 then
        -- Mode 0: VR OFF - render normally in window overlay
        self:renderWindowOverlay(detectedUnits, selfData)
    elseif vrMode == 1 then
        -- Mode 1: VR ON (window overlay) - render normally in window overlay
        self:renderWindowOverlay(detectedUnits, selfData)
    elseif vrMode == 2 then
        -- Mode 2: VR LAYER - send to OpenXR layer, hide window elements
        self:renderOpenXRLayer(detectedUnits, selfData)
    end
    
    -- Phase 3: Update info text
    if #detectedUnits > 0 then
        self.infoText:setText(string.format("Units in view: %d", #detectedUnits))
        self:hideBorders()  -- Borders not needed for multiple units
    else
        self.infoText:setText("No units detected")
        self:hideBorders()
    end
end

function UnitHighlightPanel:closeWindow()
    -- Clear OpenXR circles when closing
    if AccModOverlayManager and AccModOverlayManager.openxrUDP then
        clearOpenXRLayerOverlay()
        log.write('AccMod', log.INFO, "Cleared OpenXR circles on close")
    end
    
    if self.window then
        self.window:setVisible(false)
        self.window = nil
    end
end

function UnitHighlightPanel:setMode(mode)
    if not self.window then
        return
    end

    local vrMode = AccModOverlayManager and AccModOverlayManager.vrModeEnabled or 0
    local shouldShow = true

    if vrMode == 2 then
        shouldShow = (self.openxrLayerRenderMode or LAYER_RENDER_MODE_DOTS_LABELS_CLOSEST_RING) ~= LAYER_RENDER_MODE_NOTHING
    else
        shouldShow = normalizeWindowRenderMode(self.windowRenderMode or WINDOW_RENDER_MODE_DOTS_ONLY) ~= WINDOW_RENDER_MODE_OFF
    end

    self.window:setVisible(shouldShow)

    if self.lastVisibleState ~= shouldShow then
        log.write('AccMod', log.INFO,
            string.format(
                "UnitHighlightPanel:setMode visible=%s requestedMode=%s vrMode=%d windowRenderMode=%s layerRenderMode=%s",
                tostring(shouldShow),
                tostring(mode),
                vrMode,
                getWindowRenderModeName(normalizeWindowRenderMode(self.windowRenderMode or WINDOW_RENDER_MODE_DOTS_ONLY)),
                getLayerRenderModeName(self.openxrLayerRenderMode or LAYER_RENDER_MODE_DOTS_LABELS_CLOSEST_RING)
            )
        )
        self.lastVisibleState = shouldShow
    end
end


-- DebugInfoPanel class - displays LoGetCameraPosition and LoGetSelfData
DebugInfoPanel = {}
DebugInfoPanel.__index = DebugInfoPanel

function DebugInfoPanel.new()
    local o = {}
    setmetatable(o, DebugInfoPanel)
    o.window = nil
    o.panel = nil
    o.textLines = {}  -- Array of Static widgets for each line
    o.lastUpdateTime = 0
    o.updateInterval = 0.1  -- Update 10 times per second
    o.maxLines = 65  -- Maximum number of text lines to display (increased for VR offsets)
    return o
end

function DebugInfoPanel:createWindow()
    local Window = require('Window')
    self.window = Window.new()
    
    -- Create a window in top-right corner
    local winWidth, winHeight = 450, 850
    local screenW, screenH = Gui.GetWindowSize()
    local posX = screenW - winWidth - 20
    local posY = 20
    
    self.window:setBounds(posX, posY, winWidth, winHeight)
    self.window:setText("Debug Info - Camera & Aircraft")
    self.window:setSkin(Skin.windowSkinChatMin())
    self.window:setVisible(true)
    self.window:setHasCursor(true)
    
    -- Create main panel
    self.panel = Panel.new()
    self.window:insertWidget(self.panel)
    self.panel:setBounds(0, 0, winWidth, winHeight)
    
    -- Create multiple Static widgets for each line of text
    local lineHeight = 13
    for i = 1, self.maxLines do
        local textLine = Static.new()
        self.panel:insertWidget(textLine)
        textLine:setBounds(10, 5 + (i - 1) * lineHeight, winWidth - 20, lineHeight)
        textLine:setText("")
        
        -- Style the text
        local textSkin = textLine:getSkin()
        if not textSkin.skinData then
            textSkin.skinData = { states = { released = { {} } } }
        end
        if not textSkin.skinData.states then
            textSkin.skinData.states = { released = { {} } }
        end
        if not textSkin.skinData.states.released then
            textSkin.skinData.states.released = { {} }
        end
        if not textSkin.skinData.states.released[1] then
            textSkin.skinData.states.released[1] = { text = {} }
        end
        if not textSkin.skinData.states.released[1].text then
            textSkin.skinData.states.released[1].text = {}
        end
        textSkin.skinData.states.released[1].text.fontSize = 10
        textSkin.skinData.states.released[1].text.color = "0xffffffff"  -- White
        textSkin.skinData.states.released[1].text.horzAlign = {0, 0, 0}  -- Left align
        textLine:setSkin(textSkin)
        
        table.insert(self.textLines, textLine)
    end
    
    log.write('AccMod', log.INFO, "DebugInfoPanel created")
end

function heading_pitch_roll_to_vectors( heading_deg, pitch_deg, roll_deg)
    local h = math.rad(heading_deg)
    local p = math.rad(pitch_deg)
    local r = math.rad(roll_deg)

    local ch, sh = math.cos(h), math.sin(h)
    local cp, sp = math.cos(p), math.sin(p)
    local cr, sr = math.cos(r), -math.sin(r)

    -- Order: heading (yaw around Y) -> pitch (around Z) -> roll (around X)
    -- Forward, up, left are columns of R = Rx(roll) * Rz(pitch) * Ry(heading)

    local forward = {
        ch*cp,
        sp,
        sh*cp
    }

    local up = {
        -ch*sp*cr + sh*sr,
         cp*cr,
        -sh*sp*cr - ch*sr
    }
    local left = {
        -ch*sp*sr - sh*cr,
         cp*sr,
        -sh*sp*sr + ch*cr
    }

    return  forward, up, left
end


function DebugInfoPanel:update()
    if not self.window or #self.textLines == 0 then
        return
    end
    
    -- Throttle updates
    local now = os.clock()
    if now - self.lastUpdateTime < self.updateInterval then
        return
    end
    self.lastUpdateTime = now
    
    -- Get camera position data
    local cameraData = base.Export.LoGetCameraPosition()
    local selfData = base.Export.LoGetSelfData()
    
    -- Build display text
    local lines = {}
    table.insert(lines, "=== LoGetCameraPosition ===")
    
    if cameraData then
        if cameraData.p then
            table.insert(lines, "Position (p):")
            table.insert(lines, string.format("  x: %.2f", cameraData.p.x or 0))
            table.insert(lines, string.format("  y: %.2f", cameraData.p.y or 0))
            table.insert(lines, string.format("  z: %.2f", cameraData.p.z or 0))
        end
        
        if cameraData.x then
            table.insert(lines, "Forward Vector (x):")
            table.insert(lines, string.format("  x: %.4f", cameraData.x.x or 0))
            table.insert(lines, string.format("  y: %.4f", cameraData.x.y or 0))
            table.insert(lines, string.format("  z: %.4f", cameraData.x.z or 0))
        end
        
        if cameraData.y then
            table.insert(lines, "Up Vector (y):")
            table.insert(lines, string.format("  x: %.4f", cameraData.y.x or 0))
            table.insert(lines, string.format("  y: %.4f", cameraData.y.y or 0))
            table.insert(lines, string.format("  z: %.4f", cameraData.y.z or 0))
        end
        
        if cameraData.z then
            table.insert(lines, "Left Vector (z):")
            table.insert(lines, string.format("  x: %.4f", cameraData.z.x or 0))
            table.insert(lines, string.format("  y: %.4f", cameraData.z.y or 0))
            table.insert(lines, string.format("  z: %.4f", cameraData.z.z or 0))
        end
    else
        table.insert(lines, "Camera data not available")
    end
    
    table.insert(lines, "")
    table.insert(lines, "=== LoGetSelfData ===")
    
    if selfData then
        if selfData.Name then
            table.insert(lines, string.format("Name: %s", selfData.Name))
        end
        
        if selfData.Position then
            table.insert(lines, "Position:")
            table.insert(lines, string.format("  x: %.2f", selfData.Position.x or 0))
            table.insert(lines, string.format("  y: %.2f", selfData.Position.y or 0))
            table.insert(lines, string.format("  z: %.2f", selfData.Position.z or 0))
        end
        
        if selfData.Heading then
            table.insert(lines, string.format("Heading: %.2f° (%.4f rad)", math.deg(selfData.Heading), selfData.Heading))
        end
        
        if selfData.Pitch then
            table.insert(lines, string.format("Pitch: %.2f° (%.4f rad)", math.deg(selfData.Pitch), selfData.Pitch))
        end
        
        if selfData.Bank then
            table.insert(lines, string.format("Bank: %.2f° (%.4f rad)", math.deg(selfData.Bank), selfData.Bank))
        end



        -- Calculate aircraft orientation vectors from heading, pitch, and bank
        if selfData.Heading and selfData.Pitch and selfData.Bank then
            local heading = selfData.Heading
            local pitch = selfData.Pitch
            local roll = selfData.Bank
            
            local fwd, up, left = heading_pitch_roll_to_vectors(math.deg(heading), math.deg(pitch), math.deg(roll))
            table.insert(lines, "")
            table.insert(lines, "Aircraft Orientation Vectors:")
            table.insert(lines, "Forward:")
            table.insert(lines, string.format("  x: %.4f", fwd[1]))
            table.insert(lines, string.format("  y: %.4f", fwd[2]))
            table.insert(lines, string.format("  z: %.4f", fwd[3]))
            table.insert(lines, "Up:")
            table.insert(lines, string.format("  x: %.4f", up[1]))
            table.insert(lines, string.format("  y: %.4f", up[2]))
            table.insert(lines, string.format("  z: %.4f", up[3]))
            table.insert(lines, "Left:")
            table.insert(lines, string.format("  x: %.4f", left[1]))
            table.insert(lines, string.format("  y: %.4f", left[2]))
            table.insert(lines, string.format("  z: %.4f", left[3]))
        end
        
        -- Display VR adjusted camera (if VR mode enabled)
        table.insert(lines, "")
        table.insert(lines, "=== VR Adjusted Camera ===")
        
        local vrCamera = AccModOverlayManager:getVRCameraAdjustedForAircraft()
        if vrCamera then
            table.insert(lines, "Position (p):")
            table.insert(lines, string.format("  x: %.2f", vrCamera.p.x))
            table.insert(lines, string.format("  y: %.2f", vrCamera.p.y))
            table.insert(lines, string.format("  z: %.2f", vrCamera.p.z))
            table.insert(lines, "Forward Vector (x):")
            table.insert(lines, string.format("  x: %.4f", vrCamera.x.x))
            table.insert(lines, string.format("  y: %.4f", vrCamera.x.y))
            table.insert(lines, string.format("  z: %.4f", vrCamera.x.z))
            table.insert(lines, "Up Vector (y):")
            table.insert(lines, string.format("  x: %.4f", vrCamera.y.x))
            table.insert(lines, string.format("  y: %.4f", vrCamera.y.y))
            table.insert(lines, string.format("  z: %.4f", vrCamera.y.z))
            table.insert(lines, "Left Vector (z):")
            table.insert(lines, string.format("  x: %.4f", vrCamera.z.x))
            table.insert(lines, string.format("  y: %.4f", vrCamera.z.y))
            table.insert(lines, string.format("  z: %.4f", vrCamera.z.z))
        else
            table.insert(lines, "VR mode disabled or not initialized")
        end
        
        -- Display delta rotation matrix
        table.insert(lines, "")
        table.insert(lines, "=== VR Delta Rotation Matrix ===")
        if vrCameraDeltaRotation then
            table.insert(lines, string.format("[%.4f, %.4f, %.4f]", 
                vrCameraDeltaRotation[1][1], vrCameraDeltaRotation[1][2], vrCameraDeltaRotation[1][3]))
            table.insert(lines, string.format("[%.4f, %.4f, %.4f]", 
                vrCameraDeltaRotation[2][1], vrCameraDeltaRotation[2][2], vrCameraDeltaRotation[2][3]))
            table.insert(lines, string.format("[%.4f, %.4f, %.4f]", 
                vrCameraDeltaRotation[3][1], vrCameraDeltaRotation[3][2], vrCameraDeltaRotation[3][3]))
        else
            table.insert(lines, "Not captured")
        end
        
        if selfData.LatLongAlt then
            table.insert(lines, "")
            table.insert(lines, "Lat/Long/Alt:")
            table.insert(lines, string.format("  Lat: %.6f°", math.deg(selfData.LatLongAlt.Lat or 0)))
            table.insert(lines, string.format("  Long: %.6f°", math.deg(selfData.LatLongAlt.Long or 0)))
            table.insert(lines, string.format("  Alt: %.2f m", selfData.LatLongAlt.Alt or 0))
        end
    else
        table.insert(lines, "Self data not available")
    end
    
    -- Update each text line widget
    for i = 1, self.maxLines do
        if lines[i] then
            self.textLines[i]:setText(lines[i])
        else
            self.textLines[i]:setText("")
        end
    end
end

function DebugInfoPanel:closeWindow()
    if self.window then
        self.window:setVisible(false)
        self.window = nil
    end
end

function DebugInfoPanel:setMode(mode)
    if not self.window then
        return
    end
    
    if mode == _modes.hidden then
        self.window:setVisible(false)
    else
        self.window:setVisible(true)
    end
end


-- Line of sight check using only Export API functions
-- Since Export API doesn't provide terrain height or occlusion data,
-- this implements a simplified visibility check based on available data
function hasFullLOS(observerPos, targetPos, targetName)
    -- Validate positions
    return true
end


-- Helper function to build rotation matrix from heading/pitch/bank
local function buildRotationMatrix(heading, pitch, bank)
    local cosH = math.cos(heading)
    local sinH = math.sin(heading)
    local cosP = math.cos(pitch)
    local sinP = math.sin(pitch)
    local cosB = math.cos(bank)
    local sinB = math.sin(bank)
    
    -- Build rotation matrix (Yaw * Pitch * Roll)
    return {
        x = { -- Forward vector
            x = cosH * cosP,
            y = sinP,
            z = sinH * cosP
        },
        y = { -- Up vector
            x = cosH * sinP * sinB - sinH * cosB,
            y = cosP * sinB,
            z = sinH * sinP * sinB + cosH * cosB
        },
        z = { -- Right vector
            x = cosH * sinP * cosB + sinH * sinB,
            y = cosP * cosB,
            z = sinH * sinP * cosB - cosH * sinB
        }
    }
end

-- Function to calculate relative position and convert to PDL parameters
-- Returns forward/aft, up/down, left/right offsets in meters
local function calculateRelativePosition(playerPos, tankerPos, tankerHeading, tankerPitch, tankerBank)
    -- Reference offsets for KC-135 boom contact position (meters from tanker origin)
    -- Calculated from actual refueling position in dcs.log:
    -- At stable refueling, offsets were F:-21.53m, V:6.47m, L:-20.21m with old reference
    -- Old reference was: (-22.5, -6.5, 0)
    -- Actual position = offset + old_reference = (-21.53-22.5, 6.47-6.5, -20.21+0) = (-44.03, -0.03, -20.21)
    local refForward = 0  -- 44m behind tanker origin
    local refVertical = 0.0   -- at tanker centerline height
    local refLateral = 0  -- 20m left of centerline
    
    -- Build tanker orientation matrix
    local tankerMat = buildRotationMatrix(tankerHeading, tankerPitch, tankerBank)
    
    -- Relative vector from tanker origin to player
    local rel = {
        x = playerPos.x - tankerPos.x,
        y = playerPos.y - tankerPos.y,
        z = playerPos.z - tankerPos.z
    }
    
    -- Project onto tanker's local axes
    local forward = rel.x * tankerMat.x.x + rel.y * tankerMat.x.y + rel.z * tankerMat.x.z - refForward
    local vertical = rel.x * tankerMat.y.x + rel.y * tankerMat.y.y + rel.z * tankerMat.y.z - refVertical
    local lateral = rel.x * tankerMat.z.x + rel.y * tankerMat.z.y + rel.z * tankerMat.z.z - refLateral
    
    return forward, vertical, lateral
end

-- Function to convert geometric offsets to gauge position strings
-- Returns position strings based on GAUGE_STEP_METERS intervals per gauge unit
-- duPos: vertical position (U, U2, C, D2, D, or OFF)
-- faPos: forward/aft position (F, F2, C, A2, A, or OFF)
local function offsetsToGaugePosition(forward, vertical, lateral)
    -- Calculate boundaries based on step size
    local boundary1 = GAUGE_STEP_METERS * 2   -- e.g., 3m for step=2
    local boundary2 = GAUGE_STEP_METERS * 1   -- e.g., 1m for step=2
    local maxRange = GAUGE_STEP_METERS * 10   -- e.g., 5m for step=2
    
    -- Return OFF if out of reasonable range
    if math.abs(forward) > maxRange or math.abs(vertical) > maxRange or math.abs(lateral) > maxRange then
        return "OFF", "OFF"
    end
    
    -- Convert vertical offset to DU position string
    -- Negative = too high (U), Positive = too low (D)
    local duPos
    if vertical < -boundary1 then
        duPos = "U"      -- 2*step too high
    elseif vertical < -boundary2 then
        duPos = "U2"     -- 1*step too high
    elseif vertical <= boundary2 then
        duPos = "C"      -- Centered
    elseif vertical <= boundary1 then
        duPos = "D2"     -- 1*step too low
    else
        duPos = "D"      -- 2*step too low
    end
    
    -- Convert forward/aft offset to FA position string
    -- Negative = too close (F), Positive = too far (A)
    local faPos
    if forward < -boundary1 then
        faPos = "F"      -- 2*step too close
    elseif forward < -boundary2 then
        faPos = "F2"     -- 1*step too close
    elseif forward <= boundary2 then
        faPos = "C"      -- Centered
    elseif forward <= boundary1 then
        faPos = "A2"     -- 1*step too far
    else
        faPos = "A"      -- 2*step too far
    end
    
    return duPos, faPos
end

-- Function to find closest KC-135 and calculate geometric PDL position
function findClosestKC135()
  -- log.write('AccMod', log.INFO, "=== findClosestKC135: Starting search ===")
    
    -- Get player data
    local selfData = base.Export.LoGetSelfData()
    if not selfData or not selfData.LatLongAlt then
     --   log.write('AccMod', log.WARNING, "findClosestKC135: No player data available")
        return nil, nil, nil, nil
    end
    
 --   log.write('AccMod', log.INFO, string.format("findClosestKC135: Player data OK - Lat:%.4f, Long:%.4f, Alt:%.1f", 
    --    selfData.LatLongAlt.Lat, selfData.LatLongAlt.Long, selfData.LatLongAlt.Alt)
    
    -- Use aircraft position directly from selfData
    if not selfData.Position then
--        log.write('AccMod', log.WARNING, "findClosestKC135: No position data in selfData")
        return nil, nil, nil, nil
    end
    
    local playerPos = selfData.Position
  --  log.write('AccMod', log.INFO, string.format("findClosestKC135: Player position X:%.1f, Y:%.1f, Z:%.1f", 
    --    playerPos.x, playerPos.y, playerPos.z))
    
    local worldObjects = base.Export.LoGetWorldObjects()
    if not worldObjects then
       -- log.write('AccMod', log.WARNING, "findClosestKC135: No world objects available")
        return nil, nil, nil, nil
    end
    
    -- Count objects
    local objCount = 0
    for _ in pairs(worldObjects) do objCount = objCount + 1 end
   -- log.write('AccMod', log.INFO, string.format("findClosestKC135: Searching %d world objects", objCount))
    
    local closestTanker = nil
    local tankerUnitName = nil
    local closestDistance = 25 * 1852
    local closestTankerData = nil
    local tankersFound = 0
    
    for objID, objData in pairs(worldObjects) do
        if objData and objData.Type
            and objData.Type.level1 == 1
            and objData.Type.level2 == 1
            and objData.Name
            and objData.Position
        then
            local name = objData.Name:lower()
            
            -- Use plain string matching (not pattern matching) - 3rd param=true disables patterns
            local match1 = name:find("kc-135", 1, true)
            local match2 = name:find("kc135", 1, true)
            
            if match1 or match2 then
                tankersFound = tankersFound + 1
                log.write('AccMod', log.INFO, string.format("findClosestKC135: Found KC-135 #%d (ID:%s, Type:%s, UnitName:%s)", 
                    tankersFound, tostring(objID), objData.Name, objData.UnitName or "N/A"))
                
                -- Use Position directly from world object
                local dx = objData.Position.x - playerPos.x
                local dz = objData.Position.z - playerPos.z
                local distance = math.sqrt(dx*dx + dz*dz)
                local distanceNM = distance / 1852
                
                log.write('AccMod', log.INFO, string.format("findClosestKC135: Tanker #%d distance: %.1f nm", 
                    tankersFound, distanceNM))
                
                if distance < closestDistance then
                    closestDistance = distance
                    closestTanker = objID
                    tankerUnitName = objData.UnitName
                    closestTankerData = objData
                    log.write('AccMod', log.INFO, string.format("findClosestKC135: New closest tanker (ID:%s, UnitName:%s) at %.1f nm", 
                        tostring(objID), objData.UnitName or "N/A", distanceNM))
                end
            end
        end
    end
    
    log.write('AccMod', log.INFO, string.format("findClosestKC135: Search complete - found %d KC-135(s) total", tankersFound))
    
    -- If we found a tanker, calculate geometric offsets
    if closestTanker and closestTankerData then
        local distanceNM = closestDistance / 1852
        
        -- Calculate relative position using geometry
        local forward, vertical, lateral = calculateRelativePosition(
            playerPos,
            closestTankerData.Position,
            closestTankerData.Heading,
            closestTankerData.Pitch,
            closestTankerData.Bank
        )
        
        log.write('AccMod', log.INFO, string.format("findClosestKC135: Relative position - Fwd:%.2fm, Vert:%.2fm, Lat:%.2fm",
            forward, vertical, lateral))
        
        log.write('AccMod', log.INFO, string.format("findClosestKC135: RESULT - Closest KC-135 (ID:%s, UnitName:%s) at %.1f nm (GEOMETRIC)", 
            tostring(closestTanker), tankerUnitName or "unknown", distanceNM))
        
        return forward, vertical, lateral, distanceNM, closestTanker, tankerUnitName
    end
    
    log.write('AccMod', log.WARNING, "findClosestKC135: RESULT - No KC-135 found within 25 nm")
    return nil, nil, nil, nil, nil, nil
end

-- Helper function to convert draw argument value to gauge position string
-- drawArgValue: normalized value (typically 0-1 range)
-- Returns: position string (U, U2, C, D2, D for vertical; F, F2, C, A2, A for horizontal)
local function drawArgToGaugePosition(drawArgValue, axis)
    if not drawArgValue then
        return "OFF"
    end
    
    local value = base.tonumber(drawArgValue)
    if not value then
        return "OFF"
    end
    if value == 0 then 
        return "OFF"
    end
    -- Assuming draw arguments are normalized 0-1 where 0.5 is centered
    -- Adjust these thresholds based on actual tanker draw argument behavior
    if axis == "vertical" then
        -- DU (Down/Up) positions


        if value < 0.2 then
            return "D"      -- Too high
        elseif value < 0.4 then
            return "D2"     -- Slightly high
        elseif value <= 0.6 then
            return "C"      -- Centered
        elseif value <= 0.8 then
            return "U2"     -- Slightly low
        else
            return "U"      -- Too low
        end
    else
        -- FA (Forward/Aft) positions
        if value < 0.2 then
            return "F"      -- Too close
        elseif value < 0.4 then
            return "F2"     -- Slightly close
        elseif value <= 0.6 then
            return "C"      -- Centered
        elseif value <= 0.8 then
            return "A2"     -- Slightly far
        else
            return "A"      -- Too far
        end
    end
end

-- Function to get tanker gauge positions from a specific tanker ID using geometry
-- More efficient than searching all objects
-- Returns: duPos, faPos (position strings for vertical and forward/aft)
function getTankerGaugePosition(tankerUnitName)
    if not tankerUnitName then
        return nil, nil
    end
    
    -- Get player position
    local selfData = base.Export.LoGetSelfData()
    if not selfData or not selfData.Position then
        return nil, nil
    end
    
    local playerPos = selfData.Position
    
    -- Get all world objects and find our tanker by unit name
    local worldObjects = base.Export.LoGetWorldObjects()
    if not worldObjects then
        return nil, nil
    end
    
    local tankerData = nil
    for objID, objData in pairs(worldObjects) do
        if objData and objData.UnitName == tankerUnitName then
            tankerData = objData
            break
        end
    end
    
    if not tankerData or not tankerData.Position then
        -- Tanker no longer exists
        return nil, nil
    end
    
    -- Log detailed position and orientation data for analysis
    log.write('AccMod', log.INFO, string.format("PLAYER: Pos[X:%.2f Y:%.2f Z:%.2f] Hdg:%.4f Pitch:%.4f Roll:%.4f",
        playerPos.x, playerPos.y, playerPos.z,
        selfData.Heading or 0, selfData.Pitch or 0, selfData.Bank or 0))
    log.write('AccMod', log.INFO, string.format("TANKER: Pos[X:%.2f Y:%.2f Z:%.2f] Hdg:%.4f Pitch:%.4f Roll:%.4f",
        tankerData.Position.x, tankerData.Position.y, tankerData.Position.z,
        tankerData.Heading or 0, tankerData.Pitch or 0, tankerData.Bank or 0))
    
    -- Calculate relative position
    local forward, vertical, lateral = calculateRelativePosition(
        playerPos,
        tankerData.Position,
        tankerData.Heading,
        tankerData.Pitch,
        tankerData.Bank
    )
    
    -- Convert to gauge positions
    local duPos, faPos = offsetsToGaugePosition(forward, vertical, lateral)
    
    return duPos, faPos, forward, vertical, lateral
end

-- Function to get tanker gauge positions using draw arguments from mission environment
-- Same signature as getTankerGaugePosition but uses mission API instead of geometry
-- Returns: duPos, faPos (position strings for vertical and forward/aft)
function getTankerGaugePositionFromDrawArgs(tankerUnitName)
    if not tankerUnitName then
        return nil, nil
    end
    
    -- Get AccModBridge - try module scope first, then global
    local bridge = AccModBridge or base.AccModBridge or base._G.AccModBridge
    
    if not bridge then
        log.write('AccMod', log.WARNING, "getTankerGaugePositionFromDrawArgs: AccModBridge not available")
        return nil, nil
    end
    
    -- Get draw arguments from mission environment
    local arg1, arg2, errorMsg = getTankerDrawArguments(bridge, tankerUnitName)
    
    if errorMsg then
        log.write('AccMod', log.WARNING, "getTankerGaugePositionFromDrawArgs: " .. errorMsg)
        return nil, nil
    end
    
    -- Convert draw arguments to gauge positions
    local duPos = drawArgToGaugePosition(arg1, "vertical")
    local faPos = drawArgToGaugePosition(arg2, "horizontal")
    
    log.write('AccMod', log.INFO, string.format("getTankerGaugePositionFromDrawArgs: Draw args [%s, %s] -> Gauge [%s, %s]",
        tostring(arg1), tostring(arg2), duPos, faPos))
    
    return duPos, faPos
end

-- Function to convert gauge positions to PDL filename
-- duPos: position string (U, U2, C, D2, D, OFF) for vertical
-- faPos: position string (F, F2, C, A2, A, OFF) for forward/aft
-- Format: pdl_DU[position]_FA[position].jpg
-- Examples:
--   pdl_DUD_FAF.jpg — D/U at Down, F/A at Forward
--   pdl_DUOFF_FAOFF.jpg — both strips off
--   pdl_DUC_FAA.jpg — D/U at Centre, F/A at Aft
function positionsToPDLFilename(duPos, faPos)
    if not duPos or not faPos then
        return "pdl_DUOFF_FAOFF.jpg"
    end
    
    local filename = string.format("pdl_DU%s_FA%s.jpg", duPos, faPos)
    log.write('AccMod', log.INFO, string.format("PDL filename: %s (duPos=%s, faPos=%s)", 
        filename, duPos, faPos))
    
    return filename
end

local AccOverlay = {
}

function serializeTable(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0

    local tmp = string.rep(" ", depth)

    if name then tmp = tmp .. name .. " = " end

    if type(val) == "table" then
        tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")

        for k, v in pairs(val) do
            tmp =  tmp .. serializeTable(v, k, skipnewlines, depth + 1) .. "," .. (not skipnewlines and "\n" or "")
        end

        tmp = tmp .. string.rep(" ", depth) .. "}"
    elseif type(val) == "number" then
        tmp = tmp .. tostring(val)
    elseif type(val) == "string" then
        tmp = tmp .. string.format("%q", val)
    elseif type(val) == "boolean" then
        tmp = tmp .. (val and "true" or "false")
    else
        tmp = tmp .. "\"[inserializeable datatype:" .. type(val) .. "]\""
    end

    return tmp
end
AccOverlay = {};AccOverlay.__index = AccOverlay
function AccOverlay.new(filename,func,form,transform)
		o={}
		
      setmetatable(o, AccOverlay)
		o._isWindowCreated = false
		o._listenSocket = {}
	
		o.textStatic = nil -- single text widget
		o.currentMessage = "" -- single message string
		o._lastReceived = 0
		o._last = 0
		o.filename = filename or "bazinga"
		o.func = func or nil
		o.form = form or "%d"
		o.transform = transform or nil
      return o 
end


 
function AccOverlay:getFileName()
 return 'Config/'.. self.filename .. ' .lua'
end

function AccOverlay:loadConfiguration()
    self:log("Loading config file...")
    local tbl = Tools.safeDoFile(lfs.writedir() .. self:getFileName() , false)
    if (tbl and tbl.config) then
        self:log("Configuration exists..."..lfs.writedir() .. self:getFileName())
        self.config = tbl.config
		
    else
        self:log("Configuration not found, creating defaults...")
        self.config = {
            mode = "full",
            restoreAfterRestart = true,
            hotkey = "Ctrl+Shift+1",
            windowPosition = { x = 200, y = 200 },
			fontSize = 40,
			opacity = 0.5,
			func = self.func or "",
			format = self.form or "%.2f",
			transformName = "",
			windowHeight = HEIGHT,
			colorIndex = 1
        }
        
        self:saveConfiguration()
    end
    -- migration for config values added during an update
    if self.config and self.config.restoreAfterRestart == nil then
        self.config.restoreAfterRestart = true
        self:saveConfiguration()
    end
    if self.config and self.config.windowHeight == nil then
        self.config.windowHeight = HEIGHT
        self:saveConfiguration()
    end
    if self.config and self.config.colorIndex == nil then
        self.config.colorIndex = 1
        self:saveConfiguration()
    end
    if self.config and self.config.format == nil then
        self.config.format = self.form or "%.2f"
        self:saveConfiguration()
    end
    if self.config and self.config.transformName == nil then
        self.config.transformName = tostring(self.transform )
        self:saveConfiguration()
    end
    
    -- Apply config values to instance
    self.func = self.config.func
    self.form = self.config.format
    if self.config.transformName and self.config.transformName ~= "" then
        -- Look up transform by name
        for _, tf in ipairs(TRANSFORM_FUNCTIONS) do
            if tf.funcName == self.config.transformName then
                self.transform = tf.func
                break
            end
        end
    end
end

function AccOverlay:saveConfiguration()
    U.saveInFile(self.config, 'config', lfs.writedir() .. self:getFileName())
end

function AccOverlay:log(str)
    if not str then 
        return
    end

    log.write('AccMod', log.INFO, str)
end

function AccOverlay:error(str)
     if not str then 
        return
    end

    log.write('AccMod', log.ERROR, str)
end

-- Stub method for applying text color - to be implemented
function AccOverlay:applyTextColor()
    -- Trigger repaint to apply the new color
    self:paintRadio()
    local colorName = COLOR_LIST[self.config.colorIndex] or "Red"
    self:log("Applied text color: " .. colorName)
end


function combochange(amself)
	return function (comboself,item)

		if item then
			out = item:getText()
		end
		amself.config.func = out
		amself.func = out
		amself:paintRadio()
		amself:saveConfiguration()
		
		-- update the manager list to reflect the new function name
		if AccModOverlayManager and AccModOverlayManager.managerWindow then
			AccModOverlayManager:refreshOverlayList()
		end
	end
end

function transformchange(amself)
	return function (comboself, item)
		if item then
			local displayName = item:getText()
			amself:log("Transform combo changed to: " .. tostring(displayName))
			
			-- Look up the actual function in TRANSFORM_FUNCTIONS
			local transformFunc = nil
			local transformName = ""
			for _, tf in ipairs(TRANSFORM_FUNCTIONS) do
				if tf.name == displayName then
					transformFunc = tf.func
					transformName = tf.funcName
					amself:log("Found transform function: " .. tostring(transformName) .. ", func type: " .. type(transformFunc))
					break
				end
			end
			
			amself.config.transformName = transformName
			amself.transform = transformFunc
			amself:log("Set transformName=" .. tostring(transformName) .. ", transform type=" .. type(amself.transform))
			amself:paintRadio()
			amself:saveConfiguration()
		end
	end
end



function AccOverlay:paintRadio()

	local t

	if self.config.func and base.Export[self.config.func] then
		
		t= base.Export[self.config.func]()
	else 
		t = -1
	end
	local x = ""

	if t then

		if self.transform then
			t = self.transform(t)
		end
		if self.form then
		
			x = string.format(self.form, serializeTable(t))
		end
		
	else
		x = "-"
	end
	
	local textSkin = pNoVisible.eRedText:getSkin()
	textSkin.skinData.states.released[1].text.fontSize = self.config.fontSize
	
	-- Apply current color from config
	local colorIndex = self.config.colorIndex or 1
	local colorName = COLOR_LIST[colorIndex]
	local colorHex = COLOR_MAP[colorName] or COLOR_MAP["Red"]
	textSkin.skinData.states.released[1].text.color = colorHex
	
	-- Update window title to match selected function or filename
	if self.window then
		local title = (self.config.func and self.config.func ~= "") and self.config.func or "-"
		self.window:setText(title)
	end
	
	-- Update color button text to reflect current color
	if self.buttonColor then
		local colorIndex = self.config.colorIndex or 1
		self.buttonColor:setText("Color: " .. COLOR_LIST[colorIndex])
	end
	
	local winHeight = self.config.windowHeight or HEIGHT
	-- Line 1: Font, Opacity, and Color controls at y=140
	self.buttonDecr:setBounds(10, 140, 68, 20)
	self.buttonIncr:setBounds(79, 140, 68, 20)
	self.buttonDecOpa:setBounds(148, 140, 68, 20)
	self.buttonIncOpa:setBounds(217, 140, 68, 20)
	self.buttonColor:setBounds(286, 140, 134, 20)
	
	-- Line 2: Instrument combo at y=160
	self.comboExport:setBounds(10, 160, 410, 20)
	
	if self.config.func then
		self.comboExport:setText(self.config.func)
	end
	
	-- Line 3: Transform combo at y=180
	self.comboTransform:setBounds(10, 180, 410, 20)
	
	if self.config.transformName and self.config.transformName ~= "" then
		-- Look up display name from function name
		local displayName = "None"
		for _, tf in ipairs(TRANSFORM_FUNCTIONS) do
			if tf.funcName == self.config.transformName then
				displayName = tf.name
				break
			end
		end
		self.comboTransform:setText(displayName)
	else
		self.comboTransform:setText("None")
	end

    -- Update text display widget
	self.currentMessage = x
    if self.textStatic and self.currentMessage then
        self.textStatic:setSkin(textSkin)
        self.textStatic:setBounds(10, 0, WIDTH-10, 130)
        self.textStatic:setText(self.currentMessage)
		self.textStatic:setVisible(true)
		self.textStatic:setOpacity(self.config.opacity)
    end
	

end

function AccOverlay:createWindow()

    self.window = DialogLoader.spawnDialogFromFile(lfs.writedir() .. 'Mods\\Services\\DCS-AccWidg\\UI\\DCS-AccWidg.dlg', cdata)

    self.box         = self.window.Box
    pNoVisible  = self.window.pNoVisible --PlaceHolder - Not Visible

    self.window:setVisible(true) -- if you make the self.window invisible, its destroyed
    
    -- Set initial window title
    local title = (self.config and self.config.func and self.config.func ~= "") and self.config.func or self.filename
    self.window:setText(title)
    
    skinModeFull = pNoVisible.windowModeFull:getSkin()
    skinMinimum = pNoVisible.windowModeMin:getSkin()

    -- Create single text display widget
    self.textStatic = Static.new()
    self.box:insertWidget(self.textStatic)
	
	
	self.buttonIncr = Button.new("+ Font")
	self.box:insertWidget(self.buttonIncr)

	
	self.buttonIncr:addChangeCallback(function () self.config.fontSize = math.min(100,self.config.fontSize+5) end)
	
	self.buttonDecr = Button.new("- Font")
	self.box:insertWidget(self.buttonDecr)
	
	self.buttonDecr:addChangeCallback(  function () self.config.fontSize = math.max(8,self.config.fontSize-5) end )
	
	self.buttonIncOpa = Button.new("+ Opacity")
	self.box:insertWidget(self.buttonIncOpa)
	self.buttonIncOpa:addChangeCallback(  function () self.config.opacity = math.min(1,self.config.opacity+0.05) end )
	
	
	self.buttonDecOpa = Button.new("- Opacity")
	self.box:insertWidget(self.buttonDecOpa)
	self.buttonDecOpa:addChangeCallback(  function () self.config.opacity = math.max(0,self.config.opacity-0.05) end )
	
	-- Color cycling button
	self.buttonColor = Button.new("Color: " .. COLOR_LIST[self.config.colorIndex or 1])
	self.box:insertWidget(self.buttonColor)
	local overlayInstance = self
	self.buttonColor:addChangeCallback(function()
		-- Cycle to next color
		overlayInstance.config.colorIndex = (overlayInstance.config.colorIndex or 1) % #COLOR_LIST + 1
		-- Update button text
		overlayInstance.buttonColor:setText("Color: " .. COLOR_LIST[overlayInstance.config.colorIndex])
		overlayInstance:saveConfiguration()
		overlayInstance:applyTextColor()
	end)
	
	self.comboExport = ComboList.new()
	self.window:insertWidget(self.comboExport)
    local sortme = {}
	for k, v in pairs(base.Export) do
		if type(v) == "function" then
            table.insert(sortme, k)
		end
	end
	
	-- Sort alphabetically
	table.sort(sortme)

    for _, f in ipairs(sortme) do
        self.comboExport:newItem(f)
    end
	
	self.comboExport.onChange = combochange(self)
	
	-- Transform function selector
	self.comboTransform = ComboList.new()
	self.window:insertWidget(self.comboTransform)
	for _, tf in ipairs(TRANSFORM_FUNCTIONS) do
		self.comboTransform:newItem(tf.name)
	end
	self.comboTransform.onChange = transformchange(self)
    w, h = Gui.GetWindowSize()
            
    self:resize(w, h)
    
   -- local enabled = base.OptionsData.getPlugin("DCS-SRS","AccOverlayEnabled")

 
    
	curry = self:positionCallback()
    self.window:addPositionCallback(curry)     
	curry()

    -- Debug hotkeys for window size adjustment
    self.window:addHotKeyCallback("Ctrl+Up", function()
        self.config.windowHeight = self.config.windowHeight + 20
        self:saveConfiguration()
        self:resize(w, h)
        self:log("Window height increased to " .. self.config.windowHeight)
    end)
    
    self.window:addHotKeyCallback("Ctrl+Down", function()
        self.config.windowHeight = math.max(150, self.config.windowHeight - 20)
        self:saveConfiguration()
        self:resize(w, h)
        self:log("Window height decreased to " .. self.config.windowHeight)
    end)

    self._isWindowCreated = true

    self:log("acc Window created")

	-- lazily create the manager window once the first overlay window exists
	if AccModOverlayManager and not AccModOverlayManager.managerWindow then
		AccModOverlayManager:createManagerWindow()
	end

end


function AccOverlay:setMode(mode)
    self:log("setMode called "..mode)
    
    local oldMode = self.config.mode
    self.config.mode = mode 
    
    if self.window == nil then
        return
    end

    -- Adjust window position to keep text in same place
    local x, y = self.window:getPosition()
    local yOffset = 0
    
    -- If switching from full to minimal, move up 20 pixels
    if oldMode == _modes.full and mode ~= _modes.full then
        yOffset = 20
    -- If switching from minimal to full, move down 20 pixels
    elseif oldMode and oldMode ~= _modes.full and mode == _modes.full then
        yOffset = -20
    end
    
    if yOffset ~= 0 then
        y = y + yOffset
        self.config.windowPosition.y = y
        self.window:setPosition(x, y)
    end
    
    if self.config.mode == _modes.hidden then

        self.box:setVisible(false)
   --     pDown:setVisible(false)
        self.window:setSize(0,0) -- Make it tiny!
        self.window:setHasCursor(false) -- hide cursor

        self.window:setSkin(Skin.windowSkinChatMin())

    else
        self.box:setVisible(true)
        self.window:setSize(WIDTH, HEIGHT)

        if self.config.mode == _modes.minimum or self.config.mode == _modes.minimum_vol or self.config.mode == _modes.txrx_only then

            self.box:setSkin(skinMinimum)

         --   pDown:setVisible(false)

            self.window:setSkin(Skin.windowSkinChatMin())

            self.window:setHasCursor(false) -- hide cursor

			self.buttonIncr:setVisible(false)
			self.buttonDecr:setVisible(false)
			self.buttonDecOpa:setVisible(false)
			self.buttonIncOpa:setVisible(false)
			self.buttonColor:setVisible(false)
            --  DCS.banMouse(false)
			self.comboExport:setVisible(false)
			self.comboTransform:setVisible(false)
			--self.window:setOpacity(self.config.opacity or 0.95)
        end
        
        if self.config.mode == _modes.full then
            self.box:setSkin(skinModeFull)

            self.box:setVisible(true)
            self.window:setSkin(Skin.windowSkinChatWrite())

            self.window:setHasCursor(true) -- show cursor
			
			self.buttonIncr:setVisible(true)
			self.buttonDecr:setVisible(true)
			self.buttonDecOpa:setVisible(true)
			self.buttonIncOpa:setVisible(true)
			self.buttonColor:setVisible(true)
			self.comboExport:setVisible(true)
			self.comboTransform:setVisible(true)
        end    
    end

    self.window:setVisible(true) -- if you make the window invisible, its destroyed

  

    self:paintRadio()
    self:saveConfiguration()
end

function AccOverlay:getMode()
    return self.config.mode
end

function AccOverlay:onHotkey()

		if (self:getMode() == _modes.full) then
			self:setMode(_modes.minimum)
		elseif (self:getMode() == _modes.minimum) then
			self:setMode(_modes.hidden)
		else
			self:setMode(_modes.full)
		end 
	
end

function AccOverlay:resize(w, h)
    self.window:setBounds(self.config.windowPosition.x, self.config.windowPosition.y, WIDTH, HEIGHT)
    self.box:setBounds(0, 0, WIDTH, HEIGHT)
end

function AccOverlay:positionCallback()
	local _self = self
	return function () 
		local x, y = _self.window:getPosition()

		x = math.max(math.min(x, w-WIDTH), 0)
		y = math.max(math.min(y, h-HEIGHT), 0)

		_self.window:setPosition(x, y)

		_self.config.windowPosition = { x = x, y = y }
		_self:saveConfiguration()
	end
end
-------
AccModOverlayManager = {
    windows = {},
    first = true,
    managerWindow = nil, -- new GUI for creating/removing panels
    managerConfig = nil,
    managerWindowWidth = 320,
    managerWindowHeight = 330,
    globalMode = "hidden", -- global mode for all panels
    panelsEnabled = true,
    windowRenderMode = WINDOW_RENDER_MODE_DOTS_ONLY,
    layerRenderMode = LAYER_RENDER_MODE_DOTS_LABELS_CLOSEST_RING,
    pdlImagePanel = nil, -- Active PDL image panel for continuous monitoring
    unitHighlightPanel = nil, -- Active unit highlighter panel
    debugInfoPanel = nil, -- Active debug info panel
    lastTankerCheckTime = 0, -- Track when we last checked for tankers
    autoShowEnabled = true, -- Enable automatic panel display on precontact
    autoShowDistance = 2.7, -- Distance in nautical miles to trigger auto-show (5km precontact range)
    -- VR mode variables
    vrModeEnabled = 0, -- VR mode: 0=OFF, 1=ON (window overlay), 2=ON LAYER (OpenXR layer)
    vrCameraOffsetLocal = nil, -- Camera offset in aircraft local coordinates (forward, up, right)
    vrCameraOrientationLocal = nil, -- Camera orientation vectors in aircraft local coordinates
    vrButtonWidget = nil, -- Reference to VR toggle button
    vrResetButtonWidget = nil, -- Reference to reset button
    -- OpenXR Layer UDP socket
    openxrUDP = nil, -- UDP socket for sending to OpenXR layer (port 7779)
    openxrLayerAvailable = nil, -- nil=unchecked, true=available, false=unavailable
    openxrLastCheckTime = 0, -- Last time we checked for OpenXR layer
    openxrStatusWidget = nil -- Status display widget
}

function AccModOverlayManager:loadConfiguration()
    local tbl = Tools.safeDoFile(lfs.writedir() .. 'Config\\AccModManager.lua', false)
    if tbl and tbl.config then
        self.managerConfig = tbl.config
        if not self.managerConfig.selectedTab then
            self.managerConfig.selectedTab = "accessibility"
        end
        if self.managerConfig.panelsEnabled == nil then
            self.managerConfig.panelsEnabled = true
        end
        self.panelsEnabled = self.managerConfig.panelsEnabled
        -- Load global mode from manager config
        if tbl.config.globalMode then
            self.globalMode = tbl.config.globalMode
        end
        
        -- Load panels from config (just filenames)
        if tbl.config.panels then
            for _, filename in ipairs(tbl.config.panels) do
                -- Load the individual panel config to get its settings
                local panelConfigPath = lfs.writedir() .. 'Config/' .. filename .. ' .lua'
                local panelTbl = Tools.safeDoFile(panelConfigPath, false)
                if panelTbl and panelTbl.config then
                    local cfg = panelTbl.config
                    local transformFunc = nil
                    if cfg.transformName and cfg.transformName ~= "" then
                        -- Look up transform by name from TRANSFORM_FUNCTIONS table
                        for _, tf in ipairs(TRANSFORM_FUNCTIONS) do
                            if tf.funcName == cfg.transformName then
                                transformFunc = tf.func
                                break
                            end
                        end
                    end
                    self:createPanel(cfg.func or "", cfg.format or "%.2f", transformFunc, filename)
                end
            end
        end
    else
        self.managerConfig = {
            managerVisible = true,
            windowPosition = { x = 0, y = 0 },
            globalMode = "visible",
            selectedTab = "accessibility",
            panelsEnabled = true,
            panels = {}
        }
    
        self.globalMode = "visible"
        self.panelsEnabled = true

        self:saveConfiguration()
    end
end

function AccModOverlayManager:saveConfiguration()
    if self.managerConfig then
        self.managerConfig.globalMode = self.globalMode
        self.managerConfig.selectedTab = self.managerConfig.selectedTab or "accessibility"
        self.managerConfig.panelsEnabled = self.panelsEnabled
        
        -- Save panel list (just filenames - individual configs have all the details)
        self.managerConfig.panels = {}
        for _, win in ipairs(self.windows) do
            table.insert(self.managerConfig.panels, win.filename)
        end
        
        U.saveInFile(self.managerConfig, 'config', lfs.writedir() .. 'Config\\AccModManager.lua')
    end
end

function AccModOverlayManager:getManagedPanelsMode()
    if self.panelsEnabled == false then
        return _modes.hidden
    end

    return self.globalMode
end

function AccModOverlayManager:applyManagedPanelsMode()
    local mode = self:getManagedPanelsMode()

    for _, win in ipairs(self.windows) do
        if win and win.window then
            win:setMode(mode)
        end
    end
end

local function getManagerWindowTitle()
    local revisionData = Tools.safeDoFile(
        lfs.writedir() .. 'Mods\\Services\\DCS-AccWidg\\Scripts\\BuildRevision.lua',
        false
    )

    if revisionData and revisionData.revision and revisionData.revision ~= "" then
        return string.format("Accessibility Widget v%s", revisionData.revision)
    end

    return "Accessibility Widget"
end

function AccModOverlayManager:createManagerWindow()
    -- Load manager configuration
    self:loadConfiguration()
    
    -- if already created, just ensure it's visible and return
    if self.managerWindow then 
        self.managerWindow:setText(getManagerWindowTitle())
        self.managerWindow:setVisible(true)
        return 
    end -- already created

    self.managerWindow = DialogLoader.spawnDialogFromFile(lfs.writedir() .. 'Mods\\Services\\DCS-AccWidg\\UI\\DCS-AccWidg-ManagerTabs.dlg', cdata)
    if not self.managerWindow then
        log.write('AccMod', log.ERROR, 'Failed to load manager dialog: DCS-AccWidg-ManagerTabs.dlg')
        return
    end
    self.managerWindow:setText(getManagerWindowTitle())


	
	
    local box = self.managerWindow.Box
    pNoVisible  = self.managerWindow.pNoVisible
    skinModeFull = pNoVisible.windowModeFull:getSkin()
    skinMinimum = pNoVisible.windowModeMin:getSkin()
	box:setSkin(skinModeFull)
    local panelTabs = box.panelTabs
    local accessibilityPanel = box.panelAccessibility
    local labelsPanel = box.panelLabels
    local toolsPanel = box.panelTools
    local tabAccessibility = panelTabs.tabAccessibility
    local tabLabels = panelTabs.tabLabels
    local tabTools = panelTabs.tabTools

    local managerTabs = {
        accessibility = { tab = tabAccessibility, panel = accessibilityPanel },
        tools = { tab = tabTools, panel = toolsPanel },
        labels = { tab = tabLabels, panel = labelsPanel },
    }
    local isSwitchingManagerTab = false
    local managerInstance = self

    tabAccessibility:setBounds(0, 0, 98, 24)
    tabTools:setBounds(100, 0, 98, 24)
    tabLabels:setBounds(200, 0, 98, 24)
    accessibilityPanel:setBounds(10, 40, 300, 238)
    toolsPanel:setBounds(10, 40, 300, 238)
    labelsPanel:setBounds(10, 40, 300, 238)

    local function selectManagerTab(selectedName)
        if isSwitchingManagerTab then
            return
        end

        if not managerTabs[selectedName] then
            selectedName = "accessibility"
        end

        isSwitchingManagerTab = true
        managerInstance.managerConfig.selectedTab = selectedName

        for name, info in pairs(managerTabs) do
            local isSelected = (name == selectedName)
            info.tab:setState(isSelected)
            if isSelected then
                info.tab:onShow()
            else
                info.tab:onHide()
            end
        end

        isSwitchingManagerTab = false
        managerInstance:saveConfiguration()
    end

    for name, info in pairs(managerTabs) do
        function info.tab:onShow()
            info.panel:setVisible(true)
            if managerInstance.managerConfig and managerInstance.managerConfig.selectedTab ~= name then
                managerInstance.managerConfig.selectedTab = name
                managerInstance:saveConfiguration()
            end
        end

        function info.tab:onHide()
            info.panel:setVisible(false)
        end

        info.tab:addChangeCallback(function()
            if isSwitchingManagerTab then
                return
            end

            if info.tab:getState() then
                selectManagerTab(name)
            else
                info.tab:setState(true)
            end
        end)
    end

    local winWidth, winHeight = self.managerWindowWidth, self.managerWindowHeight
    box:setBounds(0, 0, winWidth, winHeight)
    self.managerWindow:setHasCursor(true)
	
	-- Restore position from config or center if first time
	local w, h = Gui.GetWindowSize()
	if not self.managerConfig.windowPosition or (self.managerConfig.windowPosition.x == 0 and self.managerConfig.windowPosition.y == 0) then
		-- First time - center the window
		local posX, posY = math.floor((w - winWidth) / 2), math.floor((h - winHeight) / 2)
		self.managerConfig.windowPosition = { x = posX, y = posY }
	end
	
	-- Manager window must stay visible to receive hotkeys, but hide it off-screen when not in full mode
	local shouldShow = (self.globalMode == _modes.full)
	if shouldShow then
		-- Show manager window at saved position
		self.managerWindow:setBounds(self.managerConfig.windowPosition.x, self.managerConfig.windowPosition.y, winWidth, winHeight)
	else
		-- Keep visible but move off-screen so hotkeys still work
		self.managerWindow:setBounds(-10000, -10000, winWidth, winHeight)
	end
	self.managerWindow:setVisible(true)  -- Always visible to receive hotkeys

    if not self.managerConfig.selectedTab or not managerTabs[self.managerConfig.selectedTab] then
        self.managerConfig.selectedTab = "accessibility"
    end

    selectManagerTab(self.managerConfig.selectedTab)
	
	-- Add position callback to save window position when moved
	self.managerWindow:addPositionCallback(function()
		local x, y = managerInstance.managerWindow:getPosition()
		-- Only save position if window is actually visible (not off-screen)
		if x > -5000 and y > -5000 then
			x = math.max(math.min(x, w - winWidth), 0)
			y = math.max(math.min(y, h - winHeight), 0)
			managerInstance.managerWindow:setPosition(x, y)
			managerInstance.managerConfig.windowPosition = { x = x, y = y }
			managerInstance:saveConfiguration()
		end
	end)
    
    -- listbox showing all current overlays
    self.listOverlays = ComboList.new()
    accessibilityPanel:insertWidget(self.listOverlays)
    self.listOverlays:setBounds(10, 10, 200, 22)
    
    -- Add hotkey display text
    local hotkeyText = Static.new()
    accessibilityPanel:insertWidget(hotkeyText)
    hotkeyText:setBounds(10, 40, 300, 20)
    hotkeyText:setText("Show/Transparent/Hide Shortcut: Ctrl+Shift+1")
    local textSkin = pNoVisible.eWhiteText:getSkin()
    textSkin.skinData.states.released[1].text.fontSize = 12
    hotkeyText:setSkin(textSkin)

    -- populate list with window titles (ensure configs are loaded first)
    for i, win in ipairs(self.windows) do
        -- Load config if not already loaded
        if not win.config then
            win:loadConfiguration()
        end
        local displayName
        if win.window then
            displayName = win.window:getText()
        else
            displayName = (win.config and win.config.func and win.config.func ~= "") and win.config.func or win.filename
        end
        self.listOverlays:newItem(displayName)
    end

    -- Add Panel button
    local btnAdd = Button.new("Add Panel")
    accessibilityPanel:insertWidget(btnAdd)
    btnAdd:setBounds(10, 70, 140, 28)
    local managerInstance = self
    btnAdd:addChangeCallback(function()
        -- create a new generic panel; function can be selected in the panel itself
        managerInstance:createPanel(nil, "%.2f", nil)
        managerInstance:refreshOverlayList()
    end)

    -- Remove Panel button
    local btnRemove = Button.new("Remove Panel")
    accessibilityPanel:insertWidget(btnRemove)
    btnRemove:setBounds(160, 70, 140, 28)
    btnRemove:addChangeCallback(function()
        -- get selected index and remove the panel (ComboList uses 1-based indexing)
        local item = managerInstance.listOverlays:getSelectedItem()
        if not item then return end
        
        -- Find the index by comparing the display name
        local selectedText = item:getText()
        for i, win in ipairs(managerInstance.windows) do
            local winTitle
            if win.window then
                winTitle = win.window:getText()
            else
                winTitle = (win.config and win.config.func and win.config.func ~= "") and win.config.func or win.filename
            end
            
            if winTitle == selectedText then
                managerInstance:removePanel(i)
                managerInstance:refreshOverlayList()
                break
            end
        end
    end)

    local btnPanelsEnabled = Button.new(self.panelsEnabled and "Panels: Enabled" or "Panels: Disabled")
    accessibilityPanel:insertWidget(btnPanelsEnabled)
    btnPanelsEnabled:setBounds(10, 110, 290, 28)
    btnPanelsEnabled:addChangeCallback(function()
        managerInstance.panelsEnabled = (managerInstance.panelsEnabled == false)
        btnPanelsEnabled:setText(managerInstance.panelsEnabled and "Panels: Enabled" or "Panels: Disabled")
        managerInstance:applyManagedPanelsMode()
        managerInstance:saveConfiguration()
    end)

    -- Show Image button
    local btnShowImage = Button.new("A2A Refuel PDL")
    toolsPanel:insertWidget(btnShowImage)
    btnShowImage:setBounds(10, 40, 140, 28)
    btnShowImage:addChangeCallback(function()
        -- Close existing PDL panel if any
        if managerInstance.pdlImagePanel and managerInstance.pdlImagePanel.window then
            managerInstance.pdlImagePanel:closeWindow()
            managerInstance.pdlImagePanel = nil
            log.write('AccMod', log.INFO, "Closed PDL panel")
            return
        end
        
        -- Find closest KC-135 and get its offsets
        local forward, vertical, lateral, distance, tankerID, tankerUnitName = findClosestKC135()
        
       fullPath = "Mods\\Services\\DCS-AccWidg\\Theme\\pdl_DUOFF_FAOFF.jpg"
        if forward and vertical and lateral and tankerUnitName then
            --log.write('AccMod', log.INFO, string.format("Showing PDL image: %s (tanker: %s at %.1f nm)", filename, tankerUnitName, distance))
        else
            log.write('AccMod', log.WARNING, "No KC-135 found within 25 nm")
            tankerUnitName = nil
        end
        
        -- Create and show image panel
        local imagePanel = ImagePanel.new(fullPath)
        imagePanel:createWindow()
        
        -- Store the tanker unit name for efficient tracking
        imagePanel.tankerUnitName = tankerUnitName    
        
        -- Initialize search timer
        if not tankerUnitName then
            -- No tanker found, start the 60-second re-search timer
            imagePanel.lastSearchTime = os.clock()
            log.write('AccMod', log.INFO, "PDL panel created - no tanker found, will re-search every 60 seconds")
        else
            log.write('AccMod', log.INFO, "PDL panel created and monitoring started")
        end
        
        -- Store reference for continuous monitoring
        managerInstance.pdlImagePanel = imagePanel
    end)

    -- Render mode button for Unit Highlighter
    local btnShowLabels = Button.new(getManagerRenderModeButtonText(managerInstance, managerInstance.unitHighlightPanel))
    labelsPanel:insertWidget(btnShowLabels)
    btnShowLabels:setBounds(10, 40, 140, 28)
    btnShowLabels:addChangeCallback(function()
        local vrMode = managerInstance.vrModeEnabled or 0

        if vrMode == 2 then
            cycleLayerRenderMode()
        else
            cycleWindowRenderMode()
        end
    end)
    self.btnShowLabels = btnShowLabels

    -- Debug Info button
    local btnDebugInfo = Button.new("Debug Info")
    toolsPanel:insertWidget(btnDebugInfo)
    btnDebugInfo:setBounds(160, 40, 140, 28)
    btnDebugInfo:addChangeCallback(function()
        -- Toggle debug info panel
        if managerInstance.debugInfoPanel and managerInstance.debugInfoPanel.window then
            managerInstance.debugInfoPanel:closeWindow()
            managerInstance.debugInfoPanel = nil
            log.write('AccMod', log.INFO, "Closed Debug Info panel")
        else
            -- Create and show debug info panel
            local debugPanel = DebugInfoPanel.new()
            debugPanel:createWindow()
            managerInstance.debugInfoPanel = debugPanel
            log.write('AccMod', log.INFO, "Debug Info panel created")
        end
    end)

    local function reloadAllWindows()
        log.write('AccMod', log.INFO, "Reload All button pressed - destroying and reloading all windows")
        managerInstance:destroyAllWindows()
        -- Call bootstrap from global environment to reload everything
        if bootstrap  then
            bootstrap(bootstrap)
            log.write('AccMod', log.INFO, "Bootstrap complete - all windows reloaded")
        else
            log.write('AccMod', log.ERROR, "bootstrap() function not found in global environment")
        end
        DCS.reloadUserScripts()
    end

    local btnReloadTools = Button.new("Reload All Windows")
    toolsPanel:insertWidget(btnReloadTools)
    btnReloadTools:setBounds(10, 80, 290, 28)
    btnReloadTools:addChangeCallback(reloadAllWindows)

    -- Reload All button
    local btnReload = Button.new("Reload All Windows")
    box:insertWidget(btnReload)
    btnReload:setBounds(10, 288, 300, 28)
    btnReload:addChangeCallback(reloadAllWindows)

    -- FOV display and adjustment controls
    local fovText = Static.new()
    labelsPanel:insertWidget(fovText)
    fovText:setBounds(10, 85, 140, 25)
    fovText:setText(string.format("FOV: %.0f°", manualFOVOffset))
    local fovSkin = pNoVisible.eWhiteText:getSkin()
    fovSkin.skinData.states.released[1].text.fontSize = 16
    fovText:setSkin(fovSkin)
    fovText:setVisible(true)
    self.fovTextWidget = fovText
    -- FOV decrease button
    local btnFovDec = Button.new("FOV -")
    labelsPanel:insertWidget(btnFovDec)
    btnFovDec:setBounds(160, 85, 70, 25)
    btnFovDec:setVisible(true)
    btnFovDec:addChangeCallback(function()
        manualFOVOffset = math.max(-100, manualFOVOffset - 5)
        fovText:setText(string.format("FOV: %.0f°", manualFOVOffset))
        log.write('AccMod', log.INFO, string.format("FOV decreased to %.0f° (offset: %+.0f°)", manualFOVOffset, manualFOVOffset))
    end)
    
    -- FOV increase button
    local btnFovInc = Button.new("FOV +")
    labelsPanel:insertWidget(btnFovInc)
    btnFovInc:setBounds(240, 85, 70, 25)
    btnFovInc:setVisible(true)
    btnFovInc:addChangeCallback(function()
        manualFOVOffset = math.min(100, manualFOVOffset + 5)
        fovText:setText(string.format("FOV: %.0f°", manualFOVOffset))
        log.write('AccMod', log.INFO, string.format("FOV increased to %.0f° (offset: %+.0f°)", manualFOVOffset, manualFOVOffset))
    end)

    -- OpenXR Layer status display
    local openxrStatusText = Static.new()
    labelsPanel:insertWidget(openxrStatusText)
    openxrStatusText:setBounds(10, 125, 290, 18)
    openxrStatusText:setText("OpenXR Layer: Checking...")
    local statusSkin = pNoVisible.eWhiteText:getSkin()
    statusSkin.skinData.states.released[1].text.fontSize = 12
    openxrStatusText:setSkin(statusSkin)
    openxrStatusText:setVisible(true)
    self.openxrStatusWidget = openxrStatusText

    -- Reset VR Offset button (created before VR Mode button so it exists for callback)
    local btnVRReset = Button.new("Reset VR Offset")
    labelsPanel:insertWidget(btnVRReset)
    btnVRReset:setBounds(160, 155, 140, 28)
    btnVRReset:setVisible(false)  -- Initially hidden since VR mode starts at OFF
    btnVRReset:addChangeCallback(function()
        if managerInstance.vrModeEnabled > 0 then
            managerInstance:captureVRReference()
            log.write('AccMod', log.INFO, "VR reference recaptured")
        else
            log.write('AccMod', log.INFO, "VR reset clicked (VR mode not active)")
        end
    end)
    self.vrResetButtonWidget = btnVRReset

    -- VR Mode toggle button (cycles through OFF -> ON -> ON LAYER -> OFF)
    local btnVRMode = Button.new("VR Mode: OFF")
    labelsPanel:insertWidget(btnVRMode)
    btnVRMode:setBounds(10, 155, 140, 28)
    btnVRMode:setVisible(true)
    btnVRMode:addChangeCallback(function()
        -- Check OpenXR layer availability on first toggle
        if managerInstance.openxrLayerAvailable == nil then
            managerInstance:checkOpenXRLayerAvailable()
            -- Update status display
            if managerInstance.openxrStatusWidget then
                if managerInstance.openxrLayerAvailable == true then
                    managerInstance.openxrStatusWidget:setText("OpenXR Layer: Available (LAYER mode enabled)")
                elseif managerInstance.openxrLayerAvailable == false then
                    managerInstance.openxrStatusWidget:setText("OpenXR Layer: Not detected (Window overlay enabled)")
                else
                    managerInstance.openxrStatusWidget:setText("OpenXR Layer: Unknown status")
                end
            end
        end
        
        -- Cycle to next available mode
        local startMode = managerInstance.vrModeEnabled
        local attempts = 0
        
        repeat
            managerInstance.vrModeEnabled = (managerInstance.vrModeEnabled + 1) % 3
            attempts = attempts + 1
            
            -- Skip mode 1 (window overlay) if OpenXR layer is available
            -- Skip mode 2 (LAYER) if OpenXR layer is NOT available
            if managerInstance.vrModeEnabled == 1 and managerInstance.openxrLayerAvailable == true then
                -- Layer is available, skip window overlay mode
                managerInstance.vrModeEnabled = (managerInstance.vrModeEnabled + 1) % 3
            elseif managerInstance.vrModeEnabled == 2 and managerInstance.openxrLayerAvailable == false then
                -- Layer not available, skip LAYER mode
                managerInstance.vrModeEnabled = (managerInstance.vrModeEnabled + 1) % 3
            end
            
        until managerInstance.vrModeEnabled ~= startMode or attempts > 3
        
        -- Clear OpenXR circles when switching modes
        if managerInstance.openxrUDP then
            managerInstance.openxrUDP:sendto("A", "127.0.0.1", 7779)
            log.write('AccMod', log.INFO, "Cleared OpenXR circles on mode switch")
        end
        
        if managerInstance.vrModeEnabled == 0 then
            -- VR OFF
            btnVRMode:setText("VR Mode: OFF")
            btnVRReset:setVisible(false)  -- Hide reset button when VR is off
            log.write('AccMod', log.INFO, "VR Mode: OFF")
        elseif managerInstance.vrModeEnabled == 1 then
            -- VR ON (window overlay) - only available if layer is NOT present
            managerInstance:captureVRReference()
            btnVRReset:setVisible(true)  -- Show reset button when VR is active
            if managerInstance.openxrLayerAvailable == false then
                btnVRMode:setText("VR Mode: ON")
                log.write('AccMod', log.INFO, "VR Mode: ON (window overlay - no OpenXR layer)")
            else
                btnVRMode:setText("VR Mode: ON (overlay)")
                log.write('AccMod', log.INFO, "VR Mode: ON (window overlay)")
            end
        elseif managerInstance.vrModeEnabled == 2 then
            -- VR ON LAYER (OpenXR layer) - only available if layer IS present
            managerInstance:captureVRReference()
            btnVRReset:setVisible(false)  -- Hide reset button in LAYER mode (not needed for head-locked overlay)
            -- Initialize OpenXR UDP socket if not already created
            if not managerInstance.openxrUDP then
                managerInstance.openxrUDP = socket.udp()
                managerInstance.openxrUDP:settimeout(0)
                log.write('AccMod', log.INFO, "OpenXR UDP socket created")
            end
            if managerInstance.openxrLayerAvailable == true then
                btnVRMode:setText("VR Mode: LAYER")
                log.write('AccMod', log.INFO, "VR Mode: ON LAYER (OpenXR layer active)")
            else
                btnVRMode:setText("VR Mode: LAYER (?)")
                log.write('AccMod', log.WARNING, "VR Mode: LAYER selected but OpenXR layer status unknown")
            end
        end

        ensureUnitHighlightPanelForMode()
        syncManagerRenderModeUi()
    end)
    self.vrButtonWidget = btnVRMode

    -- Register hotkey on manager window so it works even when panels are hidden
    self.managerWindow:addHotKeyCallback("Ctrl+Shift+1", AccModOverlayManager.onHotKey)
    
    -- Register FOV adjustment hotkeys
    self.managerWindow:addHotKeyCallback("Ctrl+Shift+2", function()
        manualFOVOffset = math.max(-100, manualFOVOffset - 1)
        fovText:setText(string.format("FOV: %.0f°", manualFOVOffset))
        log.write('AccMod', log.INFO, string.format("Hotkey: FOV decreased to %.0f° (offset: %+.0f°)", manualFOVOffset, manualFOVOffset))
    end)
    
    self.managerWindow:addHotKeyCallback("Ctrl+Shift+3", function()
        manualFOVOffset = math.min(100, manualFOVOffset +1)
        fovText:setText(string.format("FOV: %.0f°", manualFOVOffset))
        log.write('AccMod', log.INFO, string.format("Hotkey: FOV increased to %.0f° (offset: %+.0f°)", manualFOVOffset, manualFOVOffset))
    end)
    
    net.log("AccMod: Manager window created, hotkeys registered (Ctrl+Shift+1/2/3), globalMode: " .. tostring(self.globalMode))
    
    -- Perform initial OpenXR layer check
    self:checkOpenXRLayerAvailable()
    if self.openxrStatusWidget then
        if self.openxrLayerAvailable == true then
            self.openxrStatusWidget:setText("OpenXR Layer: Available (LAYER mode enabled)")
            log.write('AccMod', log.INFO, "Initial check: OpenXR layer is available - LAYER mode enabled")
        elseif self.openxrLayerAvailable == false then
            self.openxrStatusWidget:setText("OpenXR Layer: Not detected (Window overlay only)")
            log.write('AccMod', log.INFO, "Initial check: OpenXR layer not available - Window overlay mode only")
        else
            self.openxrStatusWidget:setText("OpenXR Layer: Status unknown")
        end
    end

    ensureUnitHighlightPanelForMode()
    syncManagerRenderModeUi()
end

-- Check if OpenXR layer is available
-- Returns: true if layer is available, false otherwise
function AccModOverlayManager:checkOpenXRLayerAvailable()
    -- Only check once every 5 seconds to avoid spam
    local currentTime = DCS.getModelTime()
    if self.openxrLayerAvailable ~= nil and (currentTime - self.openxrLastCheckTime) < 5.0 then
        return self.openxrLayerAvailable
    end
    
    self.openxrLastCheckTime = currentTime
    
    -- Try to create a test UDP socket and send a ping
    local testSocket = socket.udp()
    if not testSocket then
        log.write('AccMod', log.WARNING, "OpenXR check: Failed to create test UDP socket")
        self.openxrLayerAvailable = false
        return false
    end
    
    testSocket:settimeout(0.1)  -- 100ms timeout
    
    -- Send a PING message to the OpenXR layer
    local success, err = pcall(function()
        testSocket:sendto("PING", "127.0.0.1", 7779)
    end)
    
    if not success then
        log.write('AccMod', log.WARNING, string.format("OpenXR check: Failed to send ping - %s", tostring(err)))
        testSocket:close()
        self.openxrLayerAvailable = false
        return false
    end
    
    -- Try to receive a response (expecting "PONG" from layer)
    local response, err = testSocket:receive()
    testSocket:close()
    
    if response == "PONG" then
        log.write('AccMod', log.INFO, "OpenXR layer detected via PING/PONG")
        self.openxrLayerAvailable = true
        return true
    else
        -- No response doesn't necessarily mean layer isn't available
        -- The layer might not implement PONG yet, so we assume it's available
        -- if we can send without error
        log.write('AccMod', log.INFO, "OpenXR layer check: No PONG response (layer may not support ping yet, assuming available)")
        self.openxrLayerAvailable = true
        return true
    end
end

function AccModOverlayManager:refreshOverlayList()
    self.listOverlays:clear()
    for i, win in ipairs(self.windows) do
        -- Get the display name from the window title if available
        local displayName
        if win.window then
            displayName = win.window:getText()
        else
            displayName = (win.config and win.config.func and win.config.func ~= "") and win.config.func or win.filename
        end
        self.listOverlays:newItem(displayName)
    end
end

-- Function to get tanker draw arguments via mission environment injection
-- Returns: arg1, arg2, errorMessage (if error, arg1 and arg2 are nil)
function getTankerDrawArguments(bridge,tanker)
    if not bridge then
        return nil, nil, "AccModBridge not available"
    end
    if not tanker then tanker = 'KC-135' end
    log.write('AccMod', log.INFO, "getTankerDrawArguments: Executing mission code...")
    
    -- Build code to execute in mission environment
    -- Use a_do_script format for mission environment execution
    local innerCode = string.format([[
local tankerName = '%s'
local result = {}

-- Check if Unit table exists
if not Unit then
    result = nil
    log.write('ACCMOD-MISSION', log.ERROR, "ERROR: Unit API not available in mission environment")
end

if result then
    -- Get unit directly by name
    local foundUnit = Unit.getByName(tankerName)
    
    if not foundUnit then
        result = nil
        log.write('ACCMOD-MISSION', log.ERROR, "Unit not found by name: " .. tankerName)
    elseif not foundUnit:isExist() then
        result = nil
        log.write('ACCMOD-MISSION', log.ERROR, "Unit exists but not active: " .. tankerName)
    else
        -- Check if unit has getDrawArgumentValue
        if not foundUnit.getDrawArgumentValue then
            result = nil
            log.write('ACCMOD-MISSION', log.ERROR, "Unit found but getDrawArgumentValue not available. Unit: " .. foundUnit:getName())
        else
            -- Try to get draw arguments
            local args = {73, 74.75}

            for _, argNum in ipairs(args) do
                local value = foundUnit:getDrawArgumentValue(argNum)
                if value then
                    result[#result + 1] = value
                end
            end

            if #result == 0 then
                result = nil
                log.write('ACCMOD-MISSION', log.ERROR, "Found unit: " .. foundUnit:getName() .. " but no non-zero draw arguments in range checked")
            end
        end
    end
end

if result then
    return "SUCCESS:" .. tostring(result[1]) .. "," .. tostring(result[2]), 1
else
    return nil, 1
end
]], tanker)
    
    -- this is for do_script funkiness makes no fucking sense what is going o nhere
    local missionCode = "local a,b= a_do_script([=[" .. innerCode .. "]=]) \n return b"
    
    log.write('AccMod', log.INFO, "Executing mission code to get draw arguments")
    
    local result, success = bridge.execInEnv("mission", missionCode)
    
    if not success then
        return nil, nil, "Bridge execution failed"
    end
    
    if result == nil or result == "" then
        log.write('AccMod', log.ERROR, "No draw arguments returned from mission environment (result is nil or empty)")
        return nil, nil, "No draw arguments retrieved from mission\n\nCheck DCS.log for 'ACCMOD-MISSION' errors.\n\nPossible causes:\n- No KC-135 in mission\n- Tanker out of range\n- Unit API not available\n- getDrawArgumentValue not available for AI units"
    elseif type(result) == "string" and result:match("^SUCCESS:") then
        local values = result:sub(9)  -- Remove "SUCCESS:" prefix
        local arg1, arg2 = values:match("([^,]+),([^,]+)")
        log.write('AccMod', log.INFO, "Draw arguments retrieved: " .. tostring(result))
        return arg1, arg2, nil
    else
        log.write('AccMod', log.ERROR, "Failed to get draw arguments - unexpected format: " .. tostring(result))
        return nil, nil, "Unexpected result format\n" .. tostring(result)
    end
end

function AccModOverlayManager:createPanel(funcName, format, transform, filename)
    local newWindow = AccOverlay.new(
        filename or ("AccModDisplay"..(math.random(9999999))),
        funcName,
        format or "%.2f",
        transform or nil
    )
    table.insert(self.windows, newWindow)
    
    -- Load/create config and set to visible if new panel
    if not filename then  -- only for newly created panels, not loaded ones
        newWindow:loadConfiguration()
        newWindow:createWindow()
        -- Set new panel to global mode
        self.globalMode = _modes.full
        newWindow:setMode(self:getManagedPanelsMode())
        -- Update all other panels to match
        self:applyManagedPanelsMode()
        -- Show manager window at saved position
        if self.managerWindow then
            local posX = self.managerConfig.windowPosition.x
            local posY = self.managerConfig.windowPosition.y
            self.managerWindow:setBounds(posX, posY, self.managerWindowWidth, self.managerWindowHeight)
        end
        self:saveConfiguration()
    else
        -- Loading from config - just store the window info, will be created in onSimulationFrame
    end
end

function AccModOverlayManager:removePanel(index)
    if self.windows[index] then
        local win = self.windows[index]
        if win.window then
            win.window:setVisible(false)
        end
        -- Delete the config file
        local configPath = lfs.writedir() .. win:getFileName()
        os.remove(configPath)
        table.remove(self.windows, index)
        
        -- Save updated panel list
        self:saveConfiguration()
    end
end

function AccModOverlayManager:destroyAllWindows()
    log.write('AccMod', log.INFO, "Destroying all windows...")
    
    -- Close all overlay panels
    for i, win in ipairs(self.windows) do
        if win.window then
            win.window:setVisible(false)
            win.window = nil
        end
    end
    
    -- Close PDL image panel if exists
    if self.pdlImagePanel and self.pdlImagePanel.window then
        self.pdlImagePanel:closeWindow()
        self.pdlImagePanel = nil
    end
    
    -- Close unit highlighter panel if exists
    if self.unitHighlightPanel and self.unitHighlightPanel.window then
        self.unitHighlightPanel:closeWindow()
        self.unitHighlightPanel = nil
    end
    
    -- Close debug info panel if exists
    if self.debugInfoPanel and self.debugInfoPanel.window then
        self.debugInfoPanel:closeWindow()
        self.debugInfoPanel = nil
    end
    
    -- Close manager window
    if self.managerWindow then
        self.managerWindow:setVisible(false)
        self.managerWindow = nil
    end
    
    -- Clear windows array
    self.windows = {}
    
    log.write('AccMod', log.INFO, "All windows destroyed")
end

function AccModOverlayManager:captureVRReference()
    local camera = base.Export.LoGetCameraPosition()
    local selfData = base.Export.LoGetSelfData()

    
    if not camera or not camera.p then
        log.write('AccMod', log.WARNING, "Cannot capture VR reference - no camera data")
        self.vrCameraOffsetLocal = nil
        vrCameraDeltaRotation = nil
        return false
    end
    
    if not selfData or not selfData.Position then
        log.write('AccMod', log.WARNING, "Cannot capture VR reference - no aircraft data")
        self.vrCameraOffsetLocal = nil
        vrCameraDeltaRotation = nil
        return false
    end
    
    -- Calculate aircraft orientation vectors from heading, pitch, and bank
    if not (selfData.Heading and selfData.Pitch and selfData.Bank and camera.x and camera.y and camera.z) then
        log.write('AccMod', log.WARNING, "Cannot capture VR reference - missing orientation data")
        self.vrCameraOffsetLocal = nil
        vrCameraDeltaRotation = nil
        return false
    end
    
    local acft_fwd, acft_up, acft_left = heading_pitch_roll_to_vectors(
        math.deg(selfData.Heading), 
        math.deg(selfData.Pitch), 
        math.deg(selfData.Bank)
    )
    
    -- Build aircraft rotation matrix (columns are basis vectors)
    local R_aircraft = {
        {acft_fwd[1], acft_up[1], acft_left[1]},
        {acft_fwd[2], acft_up[2], acft_left[2]},
        {acft_fwd[3], acft_up[3], acft_left[3]}
    }
    
    -- Calculate world space offset from aircraft to camera
    local world_offset = {
        camera.p.x - selfData.Position.x,
        camera.p.y - selfData.Position.y,
        camera.p.z - selfData.Position.z
    }
    
    -- Transform world offset into aircraft's local coordinate system
    -- local_offset = R_aircraft^T * world_offset
    local R_aircraft_T = matrix_transpose(R_aircraft)
    local local_offset = matrix_multiply_vector(R_aircraft_T, world_offset)
    
    self.vrCameraOffsetLocal = {
        forward = local_offset[1],
        up = local_offset[2],
        right = local_offset[3]
    }
    
    -- Calculate orientation delta
    -- Calculate orientation delta
    -- Build rotation matrices from orientation vectors
    -- Camera rotation matrix (columns are the basis vectors)
    local R_camera = {
        {camera.x.x, camera.y.x, camera.z.x},
        {camera.x.y, camera.y.y, camera.z.y},
        {camera.x.z, camera.y.z, camera.z.z}
    }
    
    -- Calculate delta rotation: R_delta = R_camera * R_aircraft^T
    -- (Since rotation matrices are orthogonal, inverse = transpose)
    vrCameraDeltaRotation = matrix_multiply_matrix( R_aircraft_T, R_camera )
    
    
    -- Verify: R_camera_reconstructed = R_delta * R_aircraft (should equal R_camera)
    --[[
    local R_camera_verify = matrix_multiply_matrix(vrCameraDeltaRotation, R_aircraft)
    local error_sum = 0
    for i = 1, 3 do
        for j = 1, 3 do
            error_sum = error_sum + math.abs(R_camera_verify[i][j] - R_camera[i][j])
        end
    end
    --]]
    
    --log.write('AccMod', log.INFO, "VR camera delta rotation matrix captured:")
    --log.write('AccMod', log.INFO, string.format("  [%.4f, %.4f, %.4f]", 
    --    vrCameraDeltaRotation[1][1], vrCameraDeltaRotation[1][2], vrCameraDeltaRotation[1][3]))
    --log.write('AccMod', log.INFO, string.format("  [%.4f, %.4f, %.4f]", 
    --    vrCameraDeltaRotation[2][1], vrCameraDeltaRotation[2][2], vrCameraDeltaRotation[2][3]))
    --log.write('AccMod', log.INFO, string.format("  [%.4f, %.4f, %.4f]", 
    --    vrCameraDeltaRotation[3][1], vrCameraDeltaRotation[3][2], vrCameraDeltaRotation[3][3]))
    --log.write('AccMod', log.INFO, string.format("Verification error (should be ~0): %.6f", error_sum))
    --log.write('AccMod', log.INFO, string.format("Position offset (local): fwd=%.4f up=%.4f right=%.4f", 
    --    local_offset[1], local_offset[2], local_offset[3]))
    
    return true
end

-- Update VR camera to follow aircraft movement
-- Applies delta rotation matrix to current aircraft orientation
function AccModOverlayManager:getVRCameraAdjustedForAircraft()
    -- Check if VR mode is enabled and we have stored delta rotation
    if not self.vrModeEnabled or self.vrModeEnabled == 0 or not self.vrCameraOffsetLocal or not vrCameraDeltaRotation then
        return nil
    end
    
    local selfData = base.Export.LoGetSelfData()
    if not selfData or not selfData.Position then
        return nil
    end
    
    if not selfData.Heading or not selfData.Pitch or not selfData.Bank then
        return nil
    end
    
    -- Calculate current aircraft orientation vectors from heading/pitch/bank
    local acft_fwd, acft_up, acft_left = heading_pitch_roll_to_vectors(
        math.deg(selfData.Heading), 
        math.deg(selfData.Pitch), 
        math.deg(selfData.Bank)
    )
    
    -- Check if basis vectors are orthonormal (debug)
    --[[
    local fwd_len = math.sqrt(acft_fwd[1]^2 + acft_fwd[2]^2 + acft_fwd[3]^2)
    local up_len = math.sqrt(acft_up[1]^2 + acft_up[2]^2 + acft_up[3]^2)
    local left_len = math.sqrt(acft_left[1]^2 + acft_left[2]^2 + acft_left[3]^2)
    local dot_fwd_up = acft_fwd[1]*acft_up[1] + acft_fwd[2]*acft_up[2] + acft_fwd[3]*acft_up[3]
    local dot_fwd_left = acft_fwd[1]*acft_left[1] + acft_fwd[2]*acft_left[2] + acft_fwd[3]*acft_left[3]
    local dot_up_left = acft_up[1]*acft_left[1] + acft_up[2]*acft_left[2] + acft_up[3]*acft_left[3]
    
    --if math.abs(fwd_len - 1.0) > 0.01 or math.abs(up_len - 1.0) > 0.01 or math.abs(left_len - 1.0) > 0.01 or
    --   math.abs(dot_fwd_up) > 0.01 or math.abs(dot_fwd_left) > 0.01 or math.abs(dot_up_left) > 0.01 then
    --    log.write('AccMod', log.WARNING, string.format("Basis vectors not orthonormal! len(fwd)=%.4f len(up)=%.4f len(left)=%.4f dot(f,u)=%.4f dot(f,l)=%.4f dot(u,l)=%.4f",
    --        fwd_len, up_len, left_len, dot_fwd_up, dot_fwd_left, dot_up_left))
    --end
    --]]
    
    -- Build current aircraft rotation matrix (columns are basis vectors)
    local R_aircraft_current = {
        {acft_fwd[1], acft_up[1], acft_left[1]},
        {acft_fwd[2], acft_up[2], acft_left[2]},
        {acft_fwd[3], acft_up[3], acft_left[3]}
    }
    
    -- Apply delta rotation: R_camera = R_delta * R_aircraft
    local R_camera = matrix_multiply_matrix( R_aircraft_current,vrCameraDeltaRotation)
    
    -- Extract camera basis vectors from rotation matrix (columns)
    local cam_fwd = {R_camera[1][1], R_camera[2][1], R_camera[3][1]}
    local cam_up = {R_camera[1][2], R_camera[2][2], R_camera[3][2]}
    local cam_left = {R_camera[1][3], R_camera[2][3], R_camera[3][3]}
    
    -- Transform local offset back to world space
    -- world_offset = R_aircraft * local_offset
    local local_offset_vec = {
        self.vrCameraOffsetLocal.forward,
        self.vrCameraOffsetLocal.up,
        self.vrCameraOffsetLocal.right
    }
    local world_offset = matrix_multiply_vector(R_aircraft_current, local_offset_vec)
    
    -- Calculate camera position: aircraft position + world offset
    local cam_pos = {
        x = selfData.Position.x + world_offset[1],
        y = selfData.Position.y + world_offset[2],
        z = selfData.Position.z + world_offset[3]
    }
    
    -- Debug: compare with actual camera if available
    --[[
    local actual_camera = base.Export.LoGetCameraPosition()
    if actual_camera and actual_camera.x then
        local fwd_err = math.sqrt((cam_fwd[1]-actual_camera.x.x)^2 + (cam_fwd[2]-actual_camera.x.y)^2 + (cam_fwd[3]-actual_camera.x.z)^2)
        local up_err = math.sqrt((cam_up[1]-actual_camera.y.x)^2 + (cam_up[2]-actual_camera.y.y)^2 + (cam_up[3]-actual_camera.y.z)^2)
        local left_err = math.sqrt((cam_left[1]-actual_camera.z.x)^2 + (cam_left[2]-actual_camera.z.y)^2 + (cam_left[3]-actual_camera.z.z)^2)
        if fwd_err > 0.001 or up_err > 0.001 or left_err > 0.001 then
            log.write('AccMod', log.WARNING, string.format("VR camera mismatch - fwd:%.4f up:%.4f left:%.4f", fwd_err, up_err, left_err))
        end
    end
    --]]
    
    -- Return camera structure compatible with LoGetCameraPosition format
    return {
        p = cam_pos,                              -- position
        x = {x = cam_fwd[1], y = cam_fwd[2], z = cam_fwd[3]},  -- forward vector
        y = {x = cam_up[1], y = cam_up[2], z = cam_up[3]},     -- up vector
        z = {x = cam_left[1], y = cam_left[2], z = cam_left[3]} -- left vector
    }
end

-- Transform LoGetSelfData position into camera vector space
-- Returns aircraft position adjusted for the camera's position and orientation
function AccModOverlayManager.onHotKey()
		net.log("AccMod: Hotkey pressed! Current mode: " .. tostring(AccModOverlayManager.globalMode))
		
		-- Cycle through global mode
		if AccModOverlayManager.globalMode == _modes.full then
			AccModOverlayManager.globalMode = _modes.minimum
		elseif AccModOverlayManager.globalMode == _modes.minimum then
			AccModOverlayManager.globalMode = _modes.hidden

		else
			AccModOverlayManager.globalMode = _modes.full
		end
		
		net.log("AccMod: Switched to mode: " .. tostring(AccModOverlayManager.globalMode))
		
		-- Apply global mode to all panels
        AccModOverlayManager:applyManagedPanelsMode()

		-- Apply mode to PDL image panel if it exists
		if AccModOverlayManager.pdlImagePanel and AccModOverlayManager.pdlImagePanel.window then
			AccModOverlayManager.pdlImagePanel:setMode(AccModOverlayManager.globalMode)
		end
		
		-- Apply mode to Unit Highlighter panel if it exists
		if AccModOverlayManager.unitHighlightPanel and AccModOverlayManager.unitHighlightPanel.window then
            AccModOverlayManager.unitHighlightPanel:setMode(_modes.full)
		end

        -- show manager window only when global mode is full
        if AccModOverlayManager.managerWindow then
            local shouldShow = (AccModOverlayManager.globalMode == _modes.full)
            if shouldShow then
                -- Show manager window at saved position
                local posX = AccModOverlayManager.managerConfig.windowPosition.x
                local posY = AccModOverlayManager.managerConfig.windowPosition.y
                AccModOverlayManager.managerWindow:setBounds(posX, posY, AccModOverlayManager.managerWindowWidth, AccModOverlayManager.managerWindowHeight)
            else
                -- Keep visible but move off-screen so hotkeys still work
                AccModOverlayManager.managerWindow:setBounds(-10000, -10000, AccModOverlayManager.managerWindowWidth, AccModOverlayManager.managerWindowHeight)
            end
            AccModOverlayManager:saveConfiguration()
        end
end
function AccModOverlayManager.onSimulationFrame()
    ensureUnitHighlightPanelForMode()

	for _i,_s in pairs(AccModOverlayManager.windows) do
		_s._last = _s._last or 0
		if _s.config == nil then
			_s:loadConfiguration()	
			
		end
		
		if not _s.window then
			if _s._isWindowCreated == false then
				net.log("AccMod: Creating window for " .. tostring(_s.filename))
				_s:createWindow()
				-- Apply global mode after window creation
                _s:setMode(AccModOverlayManager:getManagedPanelsMode())
                net.log("AccMod: Window created and set to mode: " .. tostring(AccModOverlayManager:getManagedPanelsMode()))
			end
		end

		
		local _now = os.clock()

		if _now - _s._last > 0.25 then
			_s._last = _now
			_s:paintRadio()
		end
	end
	
	-- Update PDL image panel if active (only within 1km for performance)
	if AccModOverlayManager.pdlImagePanel and AccModOverlayManager.pdlImagePanel.window then
		local panel = AccModOverlayManager.pdlImagePanel
		
		-- Check distance to tanker before updating
		if panel.tankerUnitName then
			local selfData = base.Export.LoGetSelfData()
			local shouldUpdate = false
			
			if selfData and selfData.Position then
				local worldObjects = base.Export.LoGetWorldObjects()
				if worldObjects then
					for objID, objData in pairs(worldObjects) do
						if objData and objData.UnitName == panel.tankerUnitName and objData.Position then
							local dx = objData.Position.x - selfData.Position.x
							local dz = objData.Position.z - selfData.Position.z
							local distance_m = math.sqrt(dx*dx + dz*dz)
							local distance_km = distance_m / 1000
							
							-- Only update if within 1km
							if distance_km <= 1.0 then
								shouldUpdate = true
							end
							break
						end
					end
				end
			end
			
			if shouldUpdate then
				panel:updateFromTanker()
			end
		else
			-- No tanker tracked yet, still allow updates to search for one
			panel:updateFromTanker()
		end
	end
	
	-- Auto-show PDL panel when tanker is nearby (precontact detection)
	if AccModOverlayManager.autoShowEnabled then
		local _now = os.clock()
		-- Check for tankers every 5 seconds
		if _now - AccModOverlayManager.lastTankerCheckTime > 5.0 then
			AccModOverlayManager.lastTankerCheckTime = _now
			
			-- Only auto-show if panel doesn't exist yet
			if not AccModOverlayManager.pdlImagePanel or not AccModOverlayManager.pdlImagePanel.window then
				-- Check for nearby tanker
				local forward, vertical, lateral, distance, tankerID, tankerUnitName = findClosestKC135()
				
				-- If tanker found within precontact range, auto-show the panel
				if distance and distance <= AccModOverlayManager.autoShowDistance and tankerUnitName then
					log.write('AccMod', log.INFO, string.format("PRECONTACT: Tanker detected at %.1f nm (%.1f km) - auto-showing PDL panel", distance, distance * 1.852))
					
					-- Create PDL panel automatically
					local fullPath = "Mods\\Services\\DCS-AccWidg\\Theme\\pdl_DUOFF_FAOFF.jpg"
					local imagePanel = ImagePanel.new(fullPath)
					imagePanel:createWindow()
					
					-- Store the tanker unit name for efficient tracking
					imagePanel.tankerUnitName = tankerUnitName
					
					-- Set panel to current global mode
					imagePanel:setMode(AccModOverlayManager.globalMode)
					
					-- Store reference for continuous monitoring
					AccModOverlayManager.pdlImagePanel = imagePanel
					
					log.write('AccMod', log.INFO, "PDL panel auto-created for precontact - monitoring tanker: " .. tostring(tankerUnitName))
				end
			end
		end
	end
	if      AccModOverlayManager.fovTextWidget then
        AccModOverlayManager.fovTextWidget:setText(string.format("FOV: %.0f°", manualFOVOffset))
    end
    
    	-- Update Unit Highlighter panel if active
	if AccModOverlayManager.unitHighlightPanel and AccModOverlayManager.unitHighlightPanel.window then
		AccModOverlayManager.unitHighlightPanel:update()
	end
	
	-- Update Debug Info panel if active
	if AccModOverlayManager.debugInfoPanel and AccModOverlayManager.debugInfoPanel.window then
		AccModOverlayManager.debugInfoPanel:update()
	end

end
function tomiles(x)
  return x * 1.94384   
end
function tofeet(x)
  return x*3.28084
end

-- create initial panels via the manager so they can be managed (created/removed) uniformly

-- create the manager window at startup so it's immediately available
AccModOverlayManager:createManagerWindow()
DCS.setUserCallbacks(AccModOverlayManager)

net.log("Loaded - AccMod")

function JankyJoy:onSimulationFrame()
    if not ensureJoystickUdpSocket(false) then
        return
    end

    local msg = udp:receive()
    if msg == nil then
        return
    end
    msg2 = udp:receive()
    while msg2 ~= nil do
        msg = msg2
        msg2 = udp:receive()
    end     

    local buttonId, eventState = msg:match("^(BTN_%d+)_(%u+)$")
    if buttonId and (eventState == "PRESSED" or eventState == "RELEASED") then
        setJankyJoyButtonState(buttonId, eventState == "PRESSED")
        fireJoyButtonEvent(buttonId, eventState, msg)
    end

    local axis, value = msg:match("AXIS_(%d+)_([%-%.%d]+)")
    if base.tonumber(axis) == 2 then
        JankyJoy.currentZoomAxis = base.tonumber(value)
        local function calcY(x)
            return 32.2624 * math.exp(0.9241 * x) - 6.1548
        end

        -- Only update FOV from the axis when the zoom button is NOT held.
        -- While the button is held, manualFOVOffset is frozen at the calibrated
        -- zoom value to keep dots anchored. Axis messages keep arriving from the
        -- bridge even during button hold, which previously caused projection thrash.
        if not JankyJoy.zoomButtonOn then
            manualFOVOffset = calcY(base.tonumber(value))
        end

    end
end

-- Cleanup AccJoyBridge when simulation stops.
-- Leave the UDP socket open so the next mission load can reuse it immediately
-- without hitting a bind race against the OS port-release delay.
function JankyJoy:onSimulationStop()
    cleanupAccJoyBridge()
end

DCS.setUserCallbacks(JankyJoy)
-- 1.0 76
-- .72 55
-- .26 35
-- -.18 22
-- -.44 16
-- -.8 9
-- -1 6

-- Export AccMod namespace to global scope (for hook compatibility) without using module()
base.package.loaded.AccMod = AccMod
base.AccMod = AccMod