
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
local HEIGHT = 220

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
        self.config.transformName = ""
        if self.transform == tomiles then
            self.config.transformName = "tomiles"
        elseif self.transform == tofeet then
            self.config.transformName = "tofeet"
        end
        self:saveConfiguration()
    end
    
    -- Apply config values to instance
    self.func = self.config.func
    self.form = self.config.format
    if self.config.transformName and self.config.transformName ~= "" then
        self.transform = _G[self.config.transformName]
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

	for k, v in pairs(base.Export) do
		if type(v) == "function" then
		
			self.comboExport:newItem(tostring(k))
		end
	end
	
	self.comboExport.onChange = combochange(self)
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
    globalMode = "hidden" -- global mode for all panels
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
                        transformFunc = _G[cfg.transformName]
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
			AccModOverlayManager.globalMode = _modes.full

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
