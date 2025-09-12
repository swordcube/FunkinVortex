--[[
    chip.lua: a simple 2D game framework built off of Love2D
    Copyright (C) 2024  swordcube

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
]]

local gfx = love.graphics
local _gcCount_ = "count"

local ffi = require("ffi")

local loveC = ffi.os == 'Windows' and ffi.load('love') or ffi.C
local SDL3 = ffi.load("SDL3")

ffi.cdef [[\
	// sdl3 api
	typedef struct SDL_Window SDL_Window;
	SDL_Window *SDL_GL_GetCurrentWindow(void);

	bool SDL_ShowWindow(SDL_Window *window);
	bool SDL_HideWindow(SDL_Window *window);

	void SDL_DelayPrecise(uint64_t ns);
	uint64_t SDL_GetTicksNS(void);

	typedef struct SDL_DialogFileFilter
	{
		const char *name;
		const char *pattern;
	} SDL_DialogFileFilter;

	typedef enum SDL_FileDialogType
	{
		SDL_FILEDIALOG_OPENFILE,
		SDL_FILEDIALOG_SAVEFILE,
		SDL_FILEDIALOG_OPENFOLDER
	} SDL_FileDialogType;

	typedef void (*SDL_DialogFileCallback)(void *userdata, const char * const *filelist, int filter);
	typedef uint32_t SDL_PropertiesID;

	SDL_PropertiesID SDL_CreateProperties(void);
	void SDL_DestroyProperties(SDL_PropertiesID props);

	void SDL_ShowFileDialogWithProperties(SDL_FileDialogType type, SDL_DialogFileCallback callback, void *userdata, SDL_PropertiesID props);
	
	bool SDL_SetStringProperty(SDL_PropertiesID props, const char *name, const char *value);
	bool SDL_SetBooleanProperty(SDL_PropertiesID props, const char *name, bool value);

	bool SDL_SetPointerProperty(SDL_PropertiesID props, const char *name, void *value);
	bool SDL_SetNumberProperty(SDL_PropertiesID props, const char *name, int64_t value);

	const char* SDL_GetError(void);
]]

---
--- @class thirdparty.Native
---
--- A class for easily accessing native system functionality.
---
local Native = {}
Native.ConsoleColor = {
	BLACK = 0,
	DARK_BLUE = 1,
	DARK_GREEN = 2,
	DARK_CYAN = 3,
	DARK_RED = 4,
	DARK_MAGENTA = 5,
	DARK_YELLOW = 6,
	LIGHT_GRAY = 7,
	GRAY = 8,
	BLUE = 9,
	GREEN = 10,
	CYAN = 11,
	RED = 12,
	MAGENTA = 13,
	YELLOW = 14,
	WHITE = 15,
	NONE = -1
}
Native.AnsiColorCodes = {
    ["0"] = {fgColor = string.char(27) .. "[30m", bgColor = string.char(27) .. "[40m"},
    ["1"] = {fgColor = string.char(27) .. "[34m", bgColor = string.char(27) .. "[44m"},
    ["2"] = {fgColor = string.char(27) .. "[32m", bgColor = string.char(27) .. "[42m"},
    ["3"] = {fgColor = string.char(27) .. "[36m", bgColor = string.char(27) .. "[46m"},
    ["4"] = {fgColor = string.char(27) .. "[31m", bgColor = string.char(27) .. "[41m"},
    ["5"] = {fgColor = string.char(27) .. "[35m", bgColor = string.char(27) .. "[45m"},
    ["6"] = {fgColor = string.char(27) .. "[33m", bgColor = string.char(27) .. "[43m"},
    ["7"] = {fgColor = string.char(27) .. "[37m", bgColor = string.char(27) .. "[47m"},
    ["8"] = {fgColor = string.char(27) .. "[90m", bgColor = string.char(27) .. "[100m"},
    ["9"] = {fgColor = string.char(27) .. "[94m", bgColor = string.char(27) .. "[104m"},
    ["10"] = {fgColor = string.char(27) .. "[92m", bgColor = string.char(27) .. "[102m"},
    ["11"] = {fgColor = string.char(27) .. "[96m", bgColor = string.char(27) .. "[106m"},
    ["12"] = {fgColor = string.char(27) .. "[91m", bgColor = string.char(27) .. "[101m"},
    ["13"] = {fgColor = string.char(27) .. "[95m", bgColor = string.char(27) .. "[105m"},
    ["14"] = {fgColor = string.char(27) .. "[93m", bgColor = string.char(27) .. "[103m"},
    ["15"] = {fgColor = string.char(27) .. "[97m", bgColor = string.char(27) .. "[107m"},
    ["-1"] = {fgColor = string.char(27) .. "[0m",  bgColor = string.char(27) .. "[10m"}
}

-- function Native.askOpenFile(title, fileTypes)
-- 	return ""
-- end
-- function Native.askSaveAsFile(title, fileTypes, initialFile)
-- 	return ""
-- end

local function isempty(str)
	return type(str) == "string" and (str == "" or str == nil)
end

Native.eventCallbackStorage = {}

--- Reimplementation of love.window.showFileDialog
---
--- Main difference is the `filters` being an array instead of a map (they're unordered with no way to make them ordered in LuaJIT because `__pairs` isn't real!)
---
--- @param type "openfile"|"openfolder"|"savefile" File dialog type.
--- @param callback function  Function with 3 parameters: files (array of full platform-dependent paths to selected files, empty if the dialog is canceled by the user), filtername (nil if not set), and errorstring (nil if no error)
--- @param settings table  Look here for the fields of this parameter: https://www.love2d.org/wiki/love.window.showFileDialog
function Native.showFileDialog(type, callback, settings)
	-- referenced from https://github.com/love2d/love/blob/main/src/modules/window/sdl/Window.cpp#L1564
	local sdltype = 0
	if type == "openfile" then
		sdltype = 0
	elseif type == "openfolder" then
		sdltype = 1
	elseif type == "savefile" then
		sdltype = 2
	end
	local props = SDL3.SDL_CreateProperties()
	if not isempty(settings.title) then
		SDL3.SDL_SetStringProperty(props, "SDL.filedialog.title", settings.title)
	end
	if not isempty(settings.acceptlabel) then
		SDL3.SDL_SetStringProperty(props, "SDL.filedialog.accept", settings.acceptlabel)
	end
	if not isempty(settings.cancellabel) then
		SDL3.SDL_SetStringProperty(props, "SDL.filedialog.cancel", settings.cancellabel)
	end
	if not isempty(settings.defaultname) then
		SDL3.SDL_SetStringProperty(props, "SDL.filedialog.location", settings.defaultname)
	end
	if settings.attachtowindow then
		SDL3.SDL_SetBoolProperty(props, "SDL.filedialog.window", SDL3.SDL_GL_GetCurrentWindow())
	end
	if settings.filters and #settings.filters ~= 0 then
		local data = ffi.new("SDL_DialogFileFilter[" .. #settings.filters .. "]")
		for i = 1, #settings.filters do
			local f = ffi.new("SDL_DialogFileFilter")
			f.name = settings.filters[i][1]
			f.pattern = settings.filters[i][2]
			data[i - 1] = f
		end
		SDL3.SDL_SetPointerProperty(props, "SDL.filedialog.filters", data)
		SDL3.SDL_SetNumberProperty(props, "SDL.filedialog.nfilters", #settings.filters)
	end
	if settings.multiselect then
		SDL3.SDL_SetBooleanProperty(props, "SDL.filedialog.many", 1)
	end
	SDL3.SDL_ShowFileDialogWithProperties(sdltype, ffi.cast("SDL_DialogFileCallback", function(userdata, filelist, filter)
		local files = {}
		local err = nil

		if filelist ~= nil then
			local i = 0
			while filelist[i] ~= nil do
				table.insert(files, ffi.string(filelist[i]))
				i = i + 1
			end
		else
			err = ffi.string(SDL3.SDL_GetError())
		end
		table.insert(Native.eventCallbackStorage, {
			f = callback,
			args = {files, settings.filters[filter + 1], err}
		})
		love.event.push("handlecustomfiledialog")
		SDL3.SDL_DestroyProperties(props)
	end), nil, props)
end
function Native.setCursor(type) end
function Native.setDarkMode(enable) end
function Native.forceWindowRedraw()
    -- Needed for dark mode to apply correctly
    -- on Windows 10, not needed on Windows 11
    local w, h, f = love.window.getMode()
	f.borderless = not f.borderless
    love.window.setMode(w, h, f)

	f.borderless = not f.borderless
    love.window.setMode(w, h, f)
end
function Native.setConsoleColors(fgColor, bgColor)
	local fgColorStr = tostring(fgColor)
	local bgColorStr = tostring(bgColor)

	local fgColorCodes = Native.AnsiColorCodes[fgColorStr]
	if not fgColorCodes then
		fgColorCodes = Native.AnsiColorCodes[tostring(Native.ConsoleColor.NONE)]
	end
	local bgColorCodes = Native.AnsiColorCodes[bgColorStr]
	if not bgColorCodes then
		bgColorCodes = Native.AnsiColorCodes[tostring(Native.ConsoleColor.NONE)]
	end
	io.stdout:write(fgColorCodes.fgColor .. bgColorCodes.bgColor)
	io.stdout:flush()
end
function Native.getProcessMemory()
	return collectgarbage(_gcCount_) + gfx.getStats().texturememory
end
function Native.showWindow()
	SDL3.SDL_ShowWindow(SDL3.SDL_GL_GetCurrentWindow())
end
function Native.hideWindow()
	SDL3.SDL_HideWindow(SDL3.SDL_GL_GetCurrentWindow())
end
function Native.nanoSleep(ns)
	SDL3.SDL_DelayPrecise(ns)
end
function Native.getTicksNS()
	return tonumber(SDL3.SDL_GetTicksNS())
end

-----------------------------------------
-- Don't worry about the stuff below!! --
-----------------------------------------

local osNative = {}
local osName = love.system.getOS()

if osName == "Windows" then
	osNative = require((...) .. "." .. "Windows")
end

local retNative = {}
for key, value in pairs(Native) do
	if osNative[key] then
		retNative[key] = osNative[key]
	else
		retNative[key] = value
	end
end

return retNative