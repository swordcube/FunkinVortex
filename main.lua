require("tools.mathtools")
require("tools.stringtools")
require("tools.tabletools")

local ffi = require("ffi")
local bit = require("bit")

local libsDirectory = "libs"
if love.filesystem.isFused() and love.filesystem.mountFullPath then
    local sourceBaseDir = os.getenv("OWD") -- use OWD for linux app image support
    if not sourceBaseDir then
        sourceBaseDir = love.filesystem.getSourceBaseDirectory()
    end
    libsDirectory = sourceBaseDir .. "/libs"
    love.filesystem.mountFullPath(sourceBaseDir, "")
end
local extension = jit.os == "Windows" and "dll" or jit.os == "Linux" and "so" or jit.os == "OSX" and "dylib"
package.cpath = string.format("%s;%s/?.%s", package.cpath, libsDirectory, extension)

local imgui = require("thirdparty.cimgui")

local curEngine = 1
local curEngineList = {
    "FNF Legacy",
    "FNF V-Slice",
    "Psych Engine (pre-1.x)",
    "Psych Engine (1.x)",
    "Troll Engine (1.x)",
    "Codename Engine",
    "Friday Again Garfie Baby" -- hey guys it's me! sword!
}
local metaRequiredFormats = {
    ["FNF V-Slice"] = true,
    ["Codename Engine"] = true,
    ["Friday Again Garfie Baby"] = true
}
local difficultySeparatedFormats = {
    ["FNF Legacy"] = true,
    ["Psych Engine (pre-1.x)"] = true,
    ["Psych Engine (1.x)"] = true,
    ["Troll Engine (1.x)"] = true,
    ["Codename Engine"] = true
}
local selectEngineActivePtr = ffi.new("bool[1]", false)
local curEnginePtr = ffi.new("int[1]", curEngine)

local shortcutActions = {
    open = function()
        selectEngineActivePtr[0] = true
    end,
    exit = function()
        love.event.quit(0)
    end
}
local snaps = {
    4,
    8,
    12,
    16,
    20,
    24,
    32,
    48,
    64,
    192
}
local curSnap = 4

local noteTypes = {
    "Default"
}
local curNoteType = 1

local settings = {
    playOpponentHitsounds = true,
    playPlayerHitsounds = true,

    metronome = false,
    visualMetronome = false
}
-- 11th would be null byte, so should actually be 10 characters max
local playbackRateBuffer = ffi.new("char[11]", "1")
local playbackRatePtr = ffi.new("float[1]", 1)

love.load = function()
    love.keyboard.setKeyRepeat(true)
    love.keyboard.setTextInput(true)
    imgui.love.Init()
end

local renderingItem = false
local leftSidedItems = {
    {"File", function()
        if imgui.MenuItem_Bool("New", "Ctrl+N") then
        end
        imgui.Separator()
        if imgui.MenuItem_Bool("Open", "Ctrl+O") then
            openShortcut.action()
        end
        if imgui.MenuItem_Bool("Save", "Ctrl+S") then
        end
        imgui.Separator()
        if imgui.MenuItem_Bool("Save Chart As", "Ctrl+Shift+S") then
        end
        if imgui.MenuItem_Bool("Save Metadata As", "Ctrl+Alt+Shift+S") then
        end
        imgui.Separator()
        if imgui.MenuItem_Bool("Exit", "Alt+F4 / Ctrl+Q") then
            exitShortcut.action()
        end
    end},
    {"Edit", function()
        if imgui.MenuItem_Bool("Undo", "Ctrl+Z") then
        end
        if imgui.MenuItem_Bool("Redo", "Ctrl+Y") then
        end
        imgui.Separator()
        if imgui.MenuItem_Bool("Copy", "Ctrl+C") then
        end
        if imgui.MenuItem_Bool("Paste", "Ctrl+V") then
        end
        imgui.Separator()
        if imgui.MenuItem_Bool("Cut", "Ctrl+X") then
        end
        if imgui.MenuItem_Bool("Delete", "Delete") then
        end
    end},
    {"Chart", function()
        if imgui.MenuItem_Bool("Playtest", "Alt+Enter") then
        end
        if imgui.MenuItem_Bool("Playtest here", "Alt+Shift+Enter") then
        end
        imgui.Separator()
        if imgui.MenuItem_Bool("Edit chart metadata") then
        end
    end},
    {"View", function()
        if imgui.MenuItem_Bool("Zoom In", "Ctrl+[#+]") then
        end
        if imgui.MenuItem_Bool("Zoom Out", "Ctrl+[#-]") then
        end
        imgui.Separator()
        if imgui.MenuItem_Bool("Reset Zoom", "Ctrl+[#0]") then
        end
    end},
    {"Song", function()
        if imgui.MenuItem_Bool("Go back to the start", "Home") then
        end
        if imgui.MenuItem_Bool("Go to the end", "End") then
        end
        imgui.Separator()
        if imgui.MenuItem_Bool("Mute instrumental") then
        end
        imgui.Separator()
        -- TODO: actually get vocal tracks somehow
        if imgui.MenuItem_Bool("Mute Vocals.ogg") then
        end
        imgui.Separator()
        if imgui.MenuItem_Bool("Mute all vocal tracks") then
        end
    end},
    {"Note", function()
        if imgui.MenuItem_Bool("Add sustain length", "E") then
        end
        if imgui.MenuItem_Bool("Subtract sustain length", "Q") then
        end
        imgui.Separator()
        if imgui.MenuItem_Bool("Select all", "Ctrl+A") then
        end
        if imgui.MenuItem_Bool("Select measure", "Ctrl+Shift+A") then
        end
        imgui.Separator()
        for i = 1, #noteTypes do
            if imgui.MenuItem_Bool("(" .. i .. ") " .. noteTypes[i], nil, i == curNoteType) then
                curNoteType = i
            end
        end
    end},
    {"Help", function()
        if imgui.MenuItem_Bool("Shortcut List") then
        end
        imgui.Separator()
        if imgui.MenuItem_Bool("About Funkin' Vortex") then
        end
    end}
}
local rightSidedItems = {
    {"Snap >", function()
        if imgui.MenuItem_Bool("+ Grid Snap", "X") then
        end
        if imgui.MenuItem_Bool("  Reset Grid Snap") then
        end
        if imgui.MenuItem_Bool("- Grid Snap", "Z") then
        end
        imgui.Separator()
        for i = 1, #snaps do
            if imgui.MenuItem_Bool(tostring(snaps[i]) .. "x Grid Snap", nil, i == curSnap) then
                curSnap = i
            end
        end
    end},
    tostring(snaps[curSnap]) .. "x",
    {"Playback >", function()
        if imgui.MenuItem_Bool("Play/Pause", "Space") then
        end
        imgui.Separator()
        if imgui.MenuItem_Bool("Go back a beat", "Up") then
        end
        if imgui.MenuItem_Bool("Go forward a beat", "Down") then
        end
        imgui.Separator()
        if imgui.MenuItem_Bool("Go back a measure", "A") then
        end
        if imgui.MenuItem_Bool("Go forward a measure", "D") then
        end
        imgui.Separator()
        if imgui.MenuItem_Bool("Play opponent hitsounds", nil, settings.playOpponentHitsounds) then
            settings.playOpponentHitsounds = not settings.playOpponentHitsounds
        end
        if imgui.MenuItem_Bool("Play player hitsounds", nil, settings.playPlayerHitsounds) then
            settings.playPlayerHitsounds = not settings.playPlayerHitsounds
        end
        imgui.Separator()
        if imgui.MenuItem_Bool("Metronome", nil, settings.metronome) then
            settings.metronome = not settings.metronome
        end
        if imgui.MenuItem_Bool("Visual metronome", nil, settings.visualMetronome) then
            settings.visualMetronome = not settings.visualMetronome
        end
    end},
    function()
        local width = imgui.CalcTextSize(ffi.string(playbackRateBuffer)).x + 10
        imgui.SetNextItemWidth(width)
        if renderingItem then
            if imgui.InputText("##PlaybackRateInput", playbackRateBuffer, 11, bit.bor(imgui.ImGuiInputTextFlags_CharsDecimal, imgui.ImGuiInputTextFlags_EnterReturnsTrue)) then
                local playbackRate = tonumber(ffi.string(playbackRateBuffer))
                if not playbackRate then
                    playbackRate = 1
                end
                playbackRatePtr[0] = math.truncate(math.max(math.min(playbackRate, 3), 0.25), 3)
                ffi.copy(playbackRateBuffer, tostring(math.truncate(playbackRatePtr[0], 3)))
            end
        end
        return width
    end,
    function()
        local width = 100
        imgui.SetNextItemWidth(width)
        if renderingItem then
            if imgui.SliderFloat("##PlaybackRateSlider", playbackRatePtr, 0.25, 3, "") then
                ffi.copy(playbackRateBuffer, tostring(math.truncate(playbackRatePtr[0], 3)))
            end
        end
        return width
    end
}
love.draw = function()
    -- menu bar
    if imgui.BeginMainMenuBar() then
        -- shortcuts
        openShortcut = imgui.love.Shortcut({"ctrl"}, "o", shortcutActions.open)
        exitShortcut = imgui.love.Shortcut({"ctrl"}, "q", shortcutActions.exit)

        -- left sided items
        for i = 1, #leftSidedItems do
            local item = leftSidedItems[i]
            if type(item) == "table" then
                if imgui.BeginMenu(item[1]) then
                    item[2]()
                    imgui.EndMenu()
                end
            elseif type(item) == "function" then
                item()
            else
                imgui.Text(tostring(item))
            end
        end
        -- right sided items
        renderingItem = false
        local menuWidth = 0
        for i = 1, #rightSidedItems do
            local item = rightSidedItems[i]
            local itemRet = type(item) == "function" and item() or ""
            if type(itemRet) == "number" then
                menuWidth = menuWidth + itemRet
            else
                menuWidth = menuWidth + (imgui.CalcTextSize(type(item) == "table" and item[1] or (type(item) == "function" and (tostring(itemRet) or tostring(item)) or tostring(item))).x + (imgui.GetStyle().ItemSpacing.x * 2))
            end
        end
        imgui.SameLine(imgui.GetWindowWidth() - (menuWidth + 8))
        renderingItem = true
        for i = 1, #rightSidedItems do
            local item = rightSidedItems[i]
            if type(item) == "table" then
                if imgui.BeginMenu(item[1]) then
                    item[2]()
                    imgui.EndMenu()
                end
            elseif type(item) == "function" then
                item()
            else
                imgui.Text(tostring(item))
            end
        end
        imgui.EndMainMenuBar()
    end
    -- open dialog window
    if selectEngineActivePtr[0] then
        if imgui.Begin("Select an engine to use", selectEngineActivePtr, bit.bor(imgui.ImGuiWindowFlags_AlwaysAutoResize, imgui.ImGuiWindowFlags_NoResize)) then
            for i = 1, #curEngineList do
                if imgui.RadioButton_IntPtr(curEngineList[i], curEnginePtr, i) then
                    curEngine = curEnginePtr[0] -- it's this one bro
                end
            end
            if imgui.Button("OK") then
                -- we confirming it
                selectEngineActivePtr[0] = false

                local function selectChart()
                    love.window.showFileDialog("openfile", function(files)
                        if #files == 0 then
                            return
                        end
                    end, {title = difficultySeparatedFormats[curEngineList[curEngine]] and "Select a chart file for each difficulty" or "Select a chart file", multiselect = true, defaultname = "chart.json", filters = {["Funkin' Chart JSON (*.json)"] = ".json"}})
                end
                if metaRequiredFormats[curEngineList[curEngine]] then
                    love.window.showFileDialog("openfile", function(files)
                        if #files == 0 then
                            return
                        end
                        -- do this last!
                        selectChart()
                    end, {title = "Select a chart metadata file", defaultname = "metadata.json", filters = {["Funkin' Chart Metadata JSON (*.json)"] = ".json"}})
                else
                    selectChart()
                end
            end
            imgui.SameLine()
            if imgui.Button("Cancel") then
                selectEngineActivePtr[0] = false
            end
            imgui.End()
        end
    end

    -- code to render imgui
    imgui.Render()
    imgui.love.RenderDrawLists()

    love.graphics.print(tostring(love.timer.getFPS()) .. " FPS", 10, 720 - 25)
end

love.update = function(dt)
    imgui.love.Update(dt)
    imgui.NewFrame()
end

love.mousemoved = function(x, y, ...)
    imgui.love.MouseMoved(x, y)
    if not imgui.love.GetWantCaptureMouse() then
        -- your code here
    end
end

love.mousepressed = function(x, y, button, ...)
    imgui.love.MousePressed(button)
    if not imgui.love.GetWantCaptureMouse() then
        -- your code here 
    end
end

love.mousereleased = function(x, y, button, ...)
    imgui.love.MouseReleased(button)
    if not imgui.love.GetWantCaptureMouse() then
        -- your code here 
    end
end

love.wheelmoved = function(x, y)
    imgui.love.WheelMoved(x, y)
    if not imgui.love.GetWantCaptureMouse() then
        -- your code here 
    end
end

love.keypressed = function(key, ...)
    imgui.love.KeyPressed(key)
    if not imgui.love.GetWantCaptureKeyboard() then
        imgui.love.RunShortcuts(key)
    end
end

love.keyreleased = function(key, ...)
    imgui.love.KeyReleased(key)
    if not imgui.love.GetWantCaptureKeyboard() then
        -- your code here 
    end
end

love.textinput = function(t)
    imgui.love.TextInput(t)
    if imgui.love.GetWantCaptureKeyboard() then
        -- your code here 
    end
end

love.focus = function(f)
    imgui.love.Focus(f)
end

love.quit = function()
    return imgui.love.Shutdown()
end

-- for gamepad support also add the following:

love.joystickadded = function(joystick)
    imgui.love.JoystickAdded(joystick)
    -- your code here 
end

love.joystickremoved = function(joystick)
    imgui.love.JoystickRemoved()
    -- your code here 
end

love.gamepadpressed = function(joystick, button)
    imgui.love.GamepadPressed(button)
    -- your code here 
end

love.gamepadreleased = function(joystick, button)
    imgui.love.GamepadReleased(button)
    -- your code here 
end

-- choose threshold for considering analog controllers active, defaults to 0 if unspecified
local threshold = 0.2 

love.gamepadaxis = function(joystick, axis, value)
    imgui.love.GamepadAxis(axis, value, threshold)
    -- your code here 
end