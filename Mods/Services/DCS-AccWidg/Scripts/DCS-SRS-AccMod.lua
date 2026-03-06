
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
local HEIGHT = 200



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
	
		o._listStatics = {} -- placeholder objects
		o._listMessages = {} -- data
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
            mode = "full",
            restoreAfterRestart = true,
            hotkey = "Ctrl+Shift+1",
            windowPosition = { x = 200, y = 200 },
			fontSize = 40,
			opacity = 0.5,
			func = ""
        }
        self:saveConfiguration()
    end
    -- migration for config values added during an update
    if self.config and self.config.restoreAfterRestart == nil then
        self.config.restoreAfterRestart = true
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
	
	end
end



function AccOverlay:paintRadio()

    local offset = 0
   
    for k,v in pairs(self._listStatics) do

        v:setText("")
    end
	self._listMessages  = {}	
	local t

	if self.config.func and base.Export[self.config.func] then
		
		t= base.Export[self.config.func]()
	else 
		t = -1
	end
	local x = ""
	--table.insert(self._listMessages , {message = "IAS", skin =typesMessage.guard, height = 50 })
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
	
	local curStatic = 1
	t= pNoVisible.eRedText:getSkin()

	t.skinData.states.released[1].text.fontSize = self.config.fontSize
	table.insert(self._listMessages , {message = x, skin =t, height = HEIGHT -100   })
	
	if self.config.func then
		self.comboExport:setText(self.config.func)
	end
	
	
	self.buttonDecr:setBounds(10,HEIGHT -100,80,20)
	self.buttonIncr:setBounds(81,HEIGHT -100,80,20)
	self.buttonDecOpa:setBounds(161,HEIGHT -100,80,20)
	self.buttonIncOpa:setBounds(241,HEIGHT -100,80,20)
	self.comboExport:setBounds(340,HEIGHT -100,80,20)


    for _i,_msg in pairs(self._listMessages ) do		
        if(_msg~=nil and _msg.message ~= nil and  self._listStatics[curStatic] ~= nil ) then
            self._listStatics[curStatic]:setSkin(_msg.skin)
            self._listStatics[curStatic]:setBounds(10,offset,WIDTH-10,_msg.height)
            self._listStatics[curStatic]:setText(_msg.message)
			self._listStatics[curStatic]:setOpacity(self.config.opacity)
            --10 padding
            offset = offset +20
            curStatic = curStatic +1
        end
    end
	

end

function AccOverlay:createWindow()

    self.window = DialogLoader.spawnDialogFromFile(lfs.writedir() .. 'Mods\\Services\\DCS-AccWidg\\UI\\DCS-AccWidg.dlg', cdata)

    self.box         = self.window.Box
    pNoVisible  = self.window.pNoVisible --PlaceHolder - Not Visible

    self.window:setVisible(true) -- if you make the self.window invisible, its destroyed
    
    skinModeFull = pNoVisible.windowModeFull:getSkin()
    skinMinimum = pNoVisible.windowModeMin:getSkin()

    typesMessage =
    {
        normal        = pNoVisible.eYellowText:getSkin(),
        receive       = pNoVisible.eWhiteText:getSkin(),
        guard         = pNoVisible.eRedText:getSkin(),
    }
    
    self._listStatics = {}
    
    for i = 1, 1 do
        local staticNew = Static.new()
        table.insert(self._listStatics, staticNew)
        self.box:insertWidget(staticNew)
    end
	
	
	self.buttonIncr = Button.new("+ Fosdfndt")
	self.box:insertWidget(self.buttonIncr)

	
	self.buttonIncr:addChangeCallback(function () self.config.fontSize = math.min(100,self.config.fontSize+5) end)
	
	self.buttonDecr = Button.new("- Font")
	self.box:insertWidget(self.buttonDecr)
	
	self.buttonDecr:addChangeCallback(  function () self.config.fontSize = math.max(8,self.config.fontSize-5) end )
	
	self.buttonIncOpa = Button.new("+ Opacity")
	self.box:insertWidget(self.buttonIncOpa)
	self.buttonIncOpa:addChangeCallback(  function () self.config.opacity = math.max(0,self.config.opacity-0.05) end )
	
	
	self.buttonDecOpa = Button.new("- Opacity")
	self.box:insertWidget(self.buttonDecOpa)
	self.buttonDecOpa:addChangeCallback(  function () self.config.opacity = math.min(1,self.config.opacity+0.05) end )
	
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
}
function AccModOverlayManager:createManagerWindow()
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

    -- size and position manager window so it is clearly visible
    local w, h = Gui.GetWindowSize()
    local winWidth, winHeight = 320, 140
    local posX, posY = math.floor((w - winWidth) / 2), math.floor((h - winHeight) / 2)
    self.managerWindow:setBounds(posX, posY, winWidth, winHeight)
    box:setBounds(0, 0, winWidth, winHeight)
    self.managerWindow:setHasCursor(true)
	self.managerWindow:setVisible(true)
    -- listbox showing all current overlays
    self.listOverlays = ComboList.new()
    box:insertWidget(self.listOverlays)
    self.listOverlays:setBounds(10, 10, 200, 22)

    -- populate list
    for i, win in ipairs(self.windows) do
        self.listOverlays:newItem(win.filename)
    end

    -- Add Panel button
    local btnAdd = Button.new("Add Panel")
    box:insertWidget(btnAdd)
    btnAdd:setBounds(10, 40, 140, 24)
    btnAdd:addChangeCallback(function()
        -- create a new generic panel; function can be selected in the panel itself
        self:createPanel(nil, "%.2f", nil)
        self:refreshOverlayList()
    end)

    -- Remove Panel button
    local btnRemove = Button.new("Remove Panel")
    box:insertWidget(btnRemove)
    btnRemove:setBounds(160, 40, 140, 24)
    btnRemove:addChangeCallback(function()
        -- get selected item and remove the matching panel by filename
        local item = self.listOverlays:getSelectedItem()
        if not item then
            return
        end
        local name = item:getText()
        if not name then
            return
        end

        for i, win in ipairs(self.windows) do
            if win.filename == name then
                self:removePanel(i)
                break
            end
        end

        self:refreshOverlayList()
    end)

    self.managerWindow:setVisible(true)
end

function AccModOverlayManager:refreshOverlayList()
    self.listOverlays:clear()
    for i, win in ipairs(self.windows) do
        self.listOverlays:newItem(win.filename)
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
end

function AccModOverlayManager:removePanel(index)
    if self.windows[index] then
        local win = self.windows[index]
        if win.window then
            win.window:close()
        end
        table.remove(self.windows, index)
    end
end
function AccModOverlayManager.onHotKey()

		for _i,_s in pairs(AccModOverlayManager.windows) do
			_s:onHotkey()
		end

        -- show manager window only when overlays are in full mode
        if AccModOverlayManager.managerWindow then
            local first = AccModOverlayManager.windows[1]
            if first and first:getMode() == _modes.full then
                AccModOverlayManager.managerWindow:setVisible(true)
            else
                AccModOverlayManager.managerWindow:setVisible(false)
            end
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
				_s:createWindow()
				if AccModOverlayManager.first then
					_s.window:addHotKeyCallback(_s.config.hotkey, AccModOverlayManager.onHotKey)
				end
				AccModOverlayManager.first = false
			end 
		    _s:setMode(_s.config.mode)
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
