
log.write('ACC-OverlayGameGUI', log.INFO, "ACCMODS ")

local base = _G

package.path  = package.path..";.\\LuaSocket\\?.lua;"..'.\\Scripts\\?.lua;'.. '.\\Scripts\\UI\\?.lua;'
package.cpath = package.cpath..";.\\LuaSocket\\?.dll;"

module("AccMod")

local require           = base.require
local os                = base.os
local io                = base.io
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

-- ImagePanel class for displaying images in a subpanel
local ImagePanel = {}
ImagePanel.__index = ImagePanel

function ImagePanel.new(imagePath)
    local o = {}
    setmetatable(o, ImagePanel)
    o.imagePath = imagePath
    o.window = nil
    o.imageStatic = nil
    o.lastUpdateTime = 0
    o.currentFilename = ""
    o.tankerID = nil  -- Store the tracked tanker ID
    o.lastSearchTime = 0  -- Track when we last searched for a tanker
    return o
end

function ImagePanel:createWindow()
    local xbound = 120
    local ybound = 360
    -- Create a simple window programmatically
    local Window = require('Window')
    self.window = Window.new()
    self.window:setBounds(100, 100, xbound, ybound)
    self.window:setText("PDL Display")
    self.window:setSkin(Skin.windowSkinChatWrite())
    self.window:setVisible(true)
    self.window:setHasCursor(true)
    
    -- Create a panel to hold the image
    local panel = Panel.new()
    self.window:insertWidget(panel)
    panel:setBounds(0, 0, xbound, ybound)
    
    -- Create static widget for displaying the image
    self.imageStatic = Static.new()
    panel:insertWidget(self.imageStatic)
    self.imageStatic:setBounds(0, 0, xbound, ybound)
    
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
    
    local xbound = 120
    local ybound = 360
    
    -- Create and apply the picture
    local Size = require('Size')
    local picture = Picture.new(
        lfs.writedir() .. imagePath,
        "0xffffffff",  -- White color (no tint)
        nil,            -- Horizontal alignment
        nil,            -- Vertical alignment
        Size.new(xbound, ybound),  -- Size to fit the window
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
    
    -- Get PDL parameters from the tracked tanker
    if self.tankerID then
        local param73, param74 = getTankerParams(self.tankerID)
        
        if param73 and param74 then
            -- Convert params to filename
            local filename = paramsToPDLFilename(param73, param74)
            local fullPath = "Mods\\Services\\DCS-AccWidg\\Theme\\" .. filename
            
            -- Update the image
            self:updateImage(fullPath)
        else
            -- Tanker no longer available, clear ID and show OFF image
            log.write('AccMod', log.INFO, "Tanker lost, will re-search in 60 seconds")
            self:updateImage("Mods\\Services\\DCS-AccWidg\\Theme\\pdl_DUOFF_FAOFF.jpg")
            self.tankerID = nil
            self.lastSearchTime = now  -- Start re-search timer
        end
    else
        -- No tanker tracked - check if it's time to search again
        if now - self.lastSearchTime >= 60 then
            -- Re-search for tanker every 60 seconds
            log.write('AccMod', log.INFO, "Re-searching for KC-135 tanker...")
            local param73, param74, distance, tankerID = findClosestKC135()
            
            if tankerID and param73 and param74 then
                -- Found a tanker!
                self.tankerID = tankerID
                log.write('AccMod', log.INFO, string.format("Found KC-135 (ID:%s) at %.1f nm", tostring(tankerID), distance))
                
                -- Update image immediately
                local filename = paramsToPDLFilename(param73, param74)
                local fullPath = "Mods\\Services\\DCS-AccWidg\\Theme\\" .. filename
                self:updateImage(fullPath)
            else
                -- Still no tanker found
                self:updateImage("Mods\\Services\\DCS-AccWidg\\Theme\\pdl_DUOFF_FAOFF.jpg")
            end
            
            self.lastSearchTime = now
        else
            -- Not time to search yet, show OFF image
            self:updateImage("Mods\\Services\\DCS-AccWidg\\Theme\\pdl_DUOFF_FAOFF.jpg")
        end
    end
end

function ImagePanel:closeWindow()
    if self.window then
        self.window:setVisible(false)
        self.window = nil
    end
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
    local refForward = -22.5  -- behind tanker
    local refVertical = -6.5  -- below tanker
    local refLateral = 0      -- centerline
    
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

-- Function to convert geometric offsets to PDL-like parameters
-- Maps position offsets to 0.0-1.0 range similar to PDL indicators
local function offsetsToPDLParams(forward, vertical, lateral)
    -- Forward/Aft control (param73 equivalent - DU strip)
    -- Negative = too far forward, Positive = too far aft
    -- Map -3m to +3m range to 0.0-1.0
    local param73
    if vertical < -1.5 then
        param73 = 0.2  -- U (Up)
    elseif vertical < -0.5 then
        param73 = 0.4  -- U2
    elseif vertical <= 0.5 then
        param73 = 0.6  -- C (Center)
    elseif vertical <= 1.5 then
        param73 = 0.8  -- D2
    else
        param73 = 1.0  -- D (Down)
    end
    
    -- Lateral control (param74 equivalent - FA strip)
    -- Negative = too far left, Positive = too far right
    local param74
    if forward < -1.5 then
        param74 = 0.2  -- F (Forward - too close)
    elseif forward < -0.5 then
        param74 = 0.4  -- F2
    elseif forward <= 0.5 then
        param74 = 0.6  -- C (Center)
    elseif forward <= 1.5 then
        param74 = 0.8  -- A2
    else
        param74 = 1.0  -- A (Aft - too far back)
    end
    
    -- Return OFF if out of reasonable range (beyond 5m in any axis)
    if math.abs(forward) > 5 or math.abs(vertical) > 5 or math.abs(lateral) > 5 then
        return 0.0, 0.0
    end
    
    return param73, param74
end

-- Function to find closest KC-135 and calculate geometric PDL position
function findClosestKC135()
    log.write('AccMod', log.INFO, "=== findClosestKC135: Starting search ===")
    
    -- Get player data
    local selfData = base.Export.LoGetSelfData()
    if not selfData or not selfData.LatLongAlt then
        log.write('AccMod', log.WARNING, "findClosestKC135: No player data available")
        return nil, nil, nil, nil
    end
    
    log.write('AccMod', log.INFO, string.format("findClosestKC135: Player data OK - Lat:%.4f, Long:%.4f, Alt:%.1f", 
        selfData.LatLongAlt.Lat, selfData.LatLongAlt.Long, selfData.LatLongAlt.Alt))
    
    -- Use aircraft position directly from selfData
    if not selfData.Position then
        log.write('AccMod', log.WARNING, "findClosestKC135: No position data in selfData")
        return nil, nil, nil, nil
    end
    
    local playerPos = selfData.Position
    log.write('AccMod', log.INFO, string.format("findClosestKC135: Player position X:%.1f, Y:%.1f, Z:%.1f", 
        playerPos.x, playerPos.y, playerPos.z))
    
    local worldObjects = base.Export.LoGetWorldObjects()
    if not worldObjects then
        log.write('AccMod', log.WARNING, "findClosestKC135: No world objects available")
        return nil, nil, nil, nil
    end
    
    -- Count objects
    local objCount = 0
    for _ in pairs(worldObjects) do objCount = objCount + 1 end
    log.write('AccMod', log.INFO, string.format("findClosestKC135: Searching %d world objects", objCount))
    
    local closestTanker = nil
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
                log.write('AccMod', log.INFO, string.format("findClosestKC135: Found KC-135 #%d (ID:%s, Name:%s)", 
                    tankersFound, tostring(objID), objData.Name))
                
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
                    closestTankerData = objData
                    log.write('AccMod', log.INFO, string.format("findClosestKC135: New closest tanker (ID:%s) at %.1f nm", 
                        tostring(objID), distanceNM))
                end
            end
        end
    end
    
    log.write('AccMod', log.INFO, string.format("findClosestKC135: Search complete - found %d KC-135(s) total", tankersFound))
    
    -- If we found a tanker, calculate geometric PDL position
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
        
        -- Convert offsets to PDL-like parameters
        local param73, param74 = offsetsToPDLParams(forward, vertical, lateral)
        
        log.write('AccMod', log.INFO, string.format("findClosestKC135: RESULT - Closest KC-135 (ID:%s) at %.1f nm, param73=%.2f, param74=%.2f (GEOMETRIC)", 
            tostring(closestTanker), distanceNM, param73, param74))
        
        return param73, param74, distanceNM, closestTanker
    end
    
    log.write('AccMod', log.WARNING, "findClosestKC135: RESULT - No KC-135 found within 25 nm")
    return nil, nil, nil, nil
end

-- Function to get tanker parameters from a specific tanker ID using geometry
-- More efficient than searching all objects
function getTankerParams(tankerID)
    if not tankerID then
        return nil, nil
    end
    
    -- Get player position
    local selfData = base.Export.LoGetSelfData()
    if not selfData or not selfData.Position then
        return nil, nil
    end
    
    local playerPos = selfData.Position
    
    -- Get all world objects and find our tanker
    local worldObjects = base.Export.LoGetWorldObjects()
    if not worldObjects then
        return nil, nil
    end
    
    local tankerData = worldObjects[tankerID]
    if not tankerData or not tankerData.Position then
        -- Tanker no longer exists
        return nil, nil
    end
    
    -- Calculate relative position
    local forward, vertical, lateral = calculateRelativePosition(
        playerPos,
        tankerData.Position,
        tankerData.Heading,
        tankerData.Pitch,
        tankerData.Bank
    )
    
    -- Convert to PDL parameters
    local param73, param74 = offsetsToPDLParams(forward, vertical, lateral)
    
    return param73, param74
end

-- Mapping tables for PDL indicator positions
-- Parameters range from 0.0 to 1.0 with 0.2 increments
-- param73 controls DU (Down/Up strip - left strip)
-- param74 controls FA (Forward/Aft strip - right strip)

-- Function to convert parameter value (0.0-1.0) to position name for DU strip
function paramToDUPosition(value)
    if not value or value <= 0.05 then
        return "OFF"
    elseif value >= 0.15 and value <= 0.25 then
        return "U"      -- Up (top segment)
    elseif value >= 0.35 and value <= 0.45 then
        return "U2"     -- Second from top
    elseif value >= 0.55 and value <= 0.65 then
        return "C"      -- Centre
    elseif value >= 0.75 and value <= 0.85 then
        return "D2"     -- Second from bottom
    elseif value >= 0.95 then
        return "D"      -- Down (bottom segment)
    else
        return "OFF"
    end
end

-- Function to convert parameter value (0.0-1.0) to position name for FA strip
function paramToFAPosition(value)
    if not value or value <= 0.05 then
        return "OFF"
    elseif value >= 0.15 and value <= 0.25 then
        return "F"      -- Forward
    elseif value >= 0.35 and value <= 0.45 then
        return "F2"     -- Second from forward
    elseif value >= 0.55 and value <= 0.65 then
        return "C"      -- Centre
    elseif value >= 0.75 and value <= 0.85 then
        return "A2"     -- Second from aft
    elseif value >= 0.95 then
        return "A"      -- Aft
    else
        return "OFF"
    end
end

-- Function to convert model params to PDL filename
-- Format: pdl_DU[position]_FA[position].jpg
-- Example: pdl_DUD_FAF.jpg (DU at Down, FA at Forward)
function paramsToPDLFilename(param73, param74)
    -- Convert parameter values to position names
    local duPos = paramToDUPosition(param73)
    local faPos = paramToFAPosition(param74)
    
    local filename = string.format("pdl_DU%s_FA%s.jpg", duPos, faPos)
    log.write('AccMod', log.INFO, string.format("PDL filename: %s (param73=%.2f -> %s, param74=%.2f -> %s)", 
        filename, param73 or 0, duPos, param74 or 0, faPos))
    
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
			self:setMode(_modes.minimum_vol)
		elseif (self:getMode() == _modes.minimum_vol) then
			self:setMode(_modes.txrx_only)
		elseif (self:getMode() == _modes.txrx_only) then
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
    globalMode = "hidden", -- global mode for all panels
    pdlImagePanel = nil -- Active PDL image panel for continuous monitoring
}

function AccModOverlayManager:loadConfiguration()
    local tbl = Tools.safeDoFile(lfs.writedir() .. 'Config\\AccModManager.lua', false)
    if tbl and tbl.config then
        self.managerConfig = tbl.config
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
            panels = {}
        }
    
        self.globalMode = "visible"

        self:saveConfiguration()
    end
end

function AccModOverlayManager:saveConfiguration()
    if self.managerConfig then
        self.managerConfig.globalMode = self.globalMode
        
        -- Save panel list (just filenames - individual configs have all the details)
        self.managerConfig.panels = {}
        for _, win in ipairs(self.windows) do
            table.insert(self.managerConfig.panels, win.filename)
        end
        
        U.saveInFile(self.managerConfig, 'config', lfs.writedir() .. 'Config\\AccModManager.lua')
    end
end
function AccModOverlayManager:createManagerWindow()
    -- Load manager configuration
    self:loadConfiguration()
    
    -- if already created, just ensure it's visible and return
    if self.managerWindow then 
        self.managerWindow:setVisible(true)
        return 
    end -- already created

    self.managerWindow = DialogLoader.spawnDialogFromFile(lfs.writedir() .. 'Mods\\Services\\DCS-AccWidg\\UI\\DCS-AccWidg.dlg', cdata)


	
	
    local box = self.managerWindow.Box
    pNoVisible  = self.managerWindow.pNoVisible
    skinModeFull = pNoVisible.windowModeFull:getSkin()
    skinMinimum = pNoVisible.windowModeMin:getSkin()
	box:setSkin(skinModeFull)

    -- size and position manager window
    local winWidth, winHeight = 320, 170
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
	
	-- Add position callback to save window position when moved
	local managerInstance = self
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
    box:insertWidget(self.listOverlays)
    self.listOverlays:setBounds(10, 10, 200, 22)
    
    -- Add hotkey display text
    local hotkeyText = Static.new()
    box:insertWidget(hotkeyText)
    hotkeyText:setBounds(10, 38, 300, 20)
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
    box:insertWidget(btnAdd)
    btnAdd:setBounds(10, 70, 140, 28)
    local managerInstance = self
    btnAdd:addChangeCallback(function()
        -- create a new generic panel; function can be selected in the panel itself
        managerInstance:createPanel(nil, "%.2f", nil)
        managerInstance:refreshOverlayList()
    end)

    -- Remove Panel button
    local btnRemove = Button.new("Remove Panel")
    box:insertWidget(btnRemove)
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

    -- Show Image button
    local btnShowImage = Button.new("Show PDL")
    box:insertWidget(btnShowImage)
    btnShowImage:setBounds(10, 105, 140, 28)
    btnShowImage:addChangeCallback(function()
        -- Close existing PDL panel if any
        if managerInstance.pdlImagePanel and managerInstance.pdlImagePanel.window then
            managerInstance.pdlImagePanel:closeWindow()
            managerInstance.pdlImagePanel = nil
            log.write('AccMod', log.INFO, "Closed PDL panel")
            return
        end
        
        -- Find closest KC-135 and get its PDL parameters
        local param73, param74, distance, tankerID = findClosestKC135()
        
        local fullPath
        if param73 and param74 and tankerID then
            -- Convert params to filename
            local filename = paramsToPDLFilename(param73, param74)
            fullPath = "Mods\\Services\\DCS-AccWidg\\Theme\\" .. filename
            log.write('AccMod', log.INFO, string.format("Showing PDL image: %s (tanker ID:%s at %.1f nm)", filename, tostring(tankerID), distance))
        else
            log.write('AccMod', log.WARNING, "No KC-135 found within 25 nm")
            -- Show default "OFF" image
            fullPath = "Mods\\Services\\DCS-AccWidg\\Theme\\pdl_DUOFF_FAOFF.jpg"
            tankerID = nil
        end
        
        -- Create and show image panel
        local imagePanel = ImagePanel.new(fullPath)
        imagePanel:createWindow()
        
        -- Store the tanker ID for efficient tracking
        imagePanel.tankerID = tankerID
        
        -- Initialize search timer
        if not tankerID then
            -- No tanker found, start the 60-second re-search timer
            imagePanel.lastSearchTime = os.clock()
            log.write('AccMod', log.INFO, "PDL panel created - no tanker found, will re-search every 60 seconds")
        else
            log.write('AccMod', log.INFO, "PDL panel created and monitoring started")
        end
        
        -- Store reference for continuous monitoring
        managerInstance.pdlImagePanel = imagePanel
    end)

    -- Register hotkey on manager window so it works even when panels are hidden
    self.managerWindow:addHotKeyCallback("Ctrl+Shift+1", AccModOverlayManager.onHotKey)
    net.log("AccMod: Manager window created, hotkey Ctrl+Shift+1 registered, globalMode: " .. tostring(self.globalMode))
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
        newWindow:setMode(self.globalMode)
        -- Update all other panels to match
        for _, win in ipairs(self.windows) do
            if win ~= newWindow and win.window then
                win:setMode(self.globalMode)
            end
        end
        -- Show manager window at saved position
        if self.managerWindow then
            local posX = self.managerConfig.windowPosition.x
            local posY = self.managerConfig.windowPosition.y
            self.managerWindow:setBounds(posX, posY, 320, 170)
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
		for _i,_s in pairs(AccModOverlayManager.windows) do
			_s:setMode(AccModOverlayManager.globalMode)
		end

        -- show manager window only when global mode is full
        if AccModOverlayManager.managerWindow then
            local shouldShow = (AccModOverlayManager.globalMode == _modes.full)
            if shouldShow then
                -- Show manager window at saved position
                local posX = AccModOverlayManager.managerConfig.windowPosition.x
                local posY = AccModOverlayManager.managerConfig.windowPosition.y
                AccModOverlayManager.managerWindow:setBounds(posX, posY, 320, 170)
            else
                -- Keep visible but move off-screen so hotkeys still work
                AccModOverlayManager.managerWindow:setBounds(-10000, -10000, 320, 170)
            end
            AccModOverlayManager:saveConfiguration()
        end
end
function AccModOverlayManager.onSimulationFrame()
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
				_s:setMode(AccModOverlayManager.globalMode)
				net.log("AccMod: Window created and set to mode: " .. tostring(AccModOverlayManager.globalMode))
			end
		end

		
		local _now = os.clock()

		if _now - _s._last > 0.25 then
			_s._last = _now
			_s:paintRadio()
		end
	end
	
	-- Update PDL image panel if active
	if AccModOverlayManager.pdlImagePanel and AccModOverlayManager.pdlImagePanel.window then
		AccModOverlayManager.pdlImagePanel:updateFromTanker()
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
