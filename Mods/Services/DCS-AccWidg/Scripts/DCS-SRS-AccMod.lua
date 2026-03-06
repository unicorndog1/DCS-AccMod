
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
function AccOverlay.new(filename,func,form,mod)
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
		o.mod  = mod or 1
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
            mode = "hidden",
            restoreAfterRestart = true,
            hotkey = "Ctrl+Shift+1",
            windowPosition = { x = 200, y = 200 },
			fontSize = 40,
			opacity = 0.5,
			func = "",
			windowHeight = HEIGHT
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


function combochange(amself)
	return function (comboself,item)

		if item then
			out = item:getText()
		end
		amself.config.func = out
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
	
	-- Update window title to match selected function or filename
	if self.window then
		local title = (self.config.func and self.config.func ~= "") and self.config.func or self.filename
		self.window:setText(title)
	end
	
	local winHeight = self.config.windowHeight or HEIGHT
	-- Line 1: Font and Opacity controls at y=140
	self.buttonDecr:setBounds(10, 140, 80, 20)
	self.buttonIncr:setBounds(91, 140, 80, 20)
	self.buttonDecOpa:setBounds(172, 140, 80, 20)
	self.buttonIncOpa:setBounds(253, 140, 80, 20)
	
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

    typesMessage =
    {
        normal        = pNoVisible.eYellowText:getSkin(),
        receive       = pNoVisible.eWhiteText:getSkin(),
        guard         = pNoVisible.eRedText:getSkin(),
    }
    
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
    self.config.mode = mode 
    
    if self.window == nil then
        return
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
    else
        self.managerConfig = {
            managerVisible = true,
            windowPosition = { x = 0, y = 0 },
            globalMode = "hidden"
        }
        self.globalMode = "hidden"
        self:saveConfiguration()
    end
end

function AccModOverlayManager:saveConfiguration()
    if self.managerConfig then
        self.managerConfig.globalMode = self.globalMode
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


	
	net.log( self.managerWindow)
    local box = self.managerWindow.Box
    pNoVisible  = self.managerWindow.pNoVisible
    skinModeFull = pNoVisible.windowModeFull:getSkin()
    skinMinimum = pNoVisible.windowModeMin:getSkin()
	box:setSkin(skinModeFull)

    -- size and position manager window
    local winWidth, winHeight = 320, 170
    box:setBounds(0, 0, winWidth, winHeight)
    self.managerWindow:setHasCursor(true)
	
	-- Manager window must stay visible to receive hotkeys, but hide it off-screen when not in full mode
	local shouldShow = (self.globalMode == _modes.full)
	if shouldShow then
		-- Show manager window in center of screen
		local w, h = Gui.GetWindowSize()
		local posX, posY = math.floor((w - winWidth) / 2), math.floor((h - winHeight) / 2)
		self.managerWindow:setBounds(posX, posY, winWidth, winHeight)
	else
		-- Keep visible but move off-screen so hotkeys still work
		self.managerWindow:setBounds(-10000, -10000, winWidth, winHeight)
	end
	self.managerWindow:setVisible(true)  -- Always visible to receive hotkeys
    
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
        filename or ("config"..(#self.windows+1)),
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
        -- Show manager window
        if self.managerWindow then
            local w, h = Gui.GetWindowSize()
            local winWidth, winHeight = 320, 170
            local posX, posY = math.floor((w - winWidth) / 2), math.floor((h - winHeight) / 2)
            self.managerWindow:setBounds(posX, posY, winWidth, winHeight)
        end
        self:saveConfiguration()
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
    end
end
function AccModOverlayManager.onHotKey()
		net.log("AccMod: Hotkey pressed! Current mode: " .. tostring(AccModOverlayManager.globalMode))
		
		-- Cycle through global mode
		if AccModOverlayManager.globalMode == _modes.full then
			AccModOverlayManager.globalMode = _modes.minimum
		elseif AccModOverlayManager.globalMode == _modes.minimum then
			AccModOverlayManager.globalMode = _modes.minimum_vol
		elseif AccModOverlayManager.globalMode == _modes.minimum_vol then
			AccModOverlayManager.globalMode = _modes.txrx_only
		elseif AccModOverlayManager.globalMode == _modes.txrx_only then
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
                -- Show manager window in center of screen
                local w, h = Gui.GetWindowSize()
                local winWidth, winHeight = 320, 170
                local posX, posY = math.floor((w - winWidth) / 2), math.floor((h - winHeight) / 2)
                AccModOverlayManager.managerWindow:setBounds(posX, posY, winWidth, winHeight)
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
AccModOverlayManager:createPanel("LoGetTrueAirSpeed","%.2f",tomiles,"config1")
AccModOverlayManager:createPanel("LoGetAltitudeAboveGroundLevel","%.2f",tofeet,"config2")
-- create the manager window at startup so it's immediately available
AccModOverlayManager:createManagerWindow()
DCS.setUserCallbacks(AccModOverlayManager)

net.log("Loaded - AccMod")
