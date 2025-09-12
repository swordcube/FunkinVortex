-- TODO: this code is an absolute mess i NEED to clean it up when i can
-- this actually sucks
-- ...mostly because i've never used imgui before and i wanted to get something working quick

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

require("thirdparty.autobatch")
local imgui = require("thirdparty.cimgui")
local json = require("thirdparty.json") --- @type thirdparty.Json
local nativefs = require("thirdparty.nativefs") --- @type thirdparty.NativeFS
local native = require("thirdparty.native") --- @type thirdparty.Native

local conductorcl = require("conductor")
local conductor = conductorcl:new() --- @type Conductor
conductor.autoIncrement = false
conductorcl.instance = conductor

local notecontainer = require("containers.notecontainer"):new() --- @type containers.notecontainer

local endStep = 4

local curEngine = 1
local curEngineList = {
    "FNF Legacy",
    "FNF V-Slice",
    "Psych Engine (pre-1.x)",
    "Psych Engine (1.x)",
    "Troll Engine (1.x)",
    "Codename Engine",
    "Friday Again Garfie Baby", -- hey guys it's me! sword!
}
local engineShorthands = {
    ["FNF Legacy"] = "fnflegacy",
    ["FNF V-Slice"] = "fnfvslice",
    ["Psych Engine (pre-1.x)"] = "psych",
    ["Psych Engine (1.x)"] = "psych1x",
    ["Troll Engine (1.x)"] = "troll1x",
    ["Codename Engine"] = "codename",
    ["Friday Again Garfie Baby"] = "garfiebaby",
}
local metaRequiredFormats = {
    ["FNF V-Slice"] = true,
    ["Codename Engine"] = true,
    ["Friday Again Garfie Baby"] = true,
}
local dynamicStrumlineFormats = {
    ["Codename Engine"] = true,
}
local difficultySeparatedFormats = {
    ["FNF Legacy"] = true,
    ["Psych Engine (pre-1.x)"] = true,
    ["Psych Engine (1.x)"] = true,
    ["Troll Engine (1.x)"] = true,
    ["Codename Engine"] = true,
}
local selectEngineActivePtr = ffi.new("bool[1]", true)
local curEnginePtr = ffi.new("int[1]", curEngine)

local currentChart = nil
local storedCharts = {}
local currentDifficulty = "normal"

local inst = nil --- @type love.Source
local vocals = {} --- @type table<string, love.Source>

local shortcutActions = {
    open = function()
        selectEngineActivePtr[0] = true
    end,
    exit = function()
        love.event.quit(0)
    end,
    playPause = function()
        if not conductor.music then
            return
        end
        if conductor.music:isPlaying() then
            conductor.music:pause()
            for _, track in pairs(vocals) do
                track:pause()
            end
        else
            conductor.music:play()
            for _, track in pairs(vocals) do
                track:seek(conductor.music:tell("seconds"), "seconds")
                track:play()
            end
        end
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
local musicTimePtr = ffi.new("float[1]", 0)

local gfx = love.graphics
local img = love.image

local bgDesat = gfx.newImage("res/images/bg_desat.png", {linear = true})

local gridCellSize = 80
local halfGridCellSize = gridCellSize / 2

local lineWidth = 2
local gridImageData = img.newImageData((gridCellSize * 4.5) + (lineWidth * 2), gridCellSize * 10)
for x = 1, gridImageData:getWidth() do
    for y = 1, gridImageData:getHeight() do
        local color = {248 / 255, 248 / 255, 248 / 255, 1}
        if math.floor((((x - lineWidth) + (math.floor((y % gridCellSize) / halfGridCellSize) * halfGridCellSize)) % gridCellSize) / halfGridCellSize) == 0 then
            color = {217 / 255, 217 / 255, 217 / 255, 1}
        end
        if x <= (lineWidth + 1) or (x >= (gridImageData:getWidth() - lineWidth)) or (x >= (gridImageData:getWidth() - halfGridCellSize - (lineWidth / 2) - 1) and x <= (gridImageData:getWidth() - halfGridCellSize + (lineWidth / 2) - 1)) or (x >= (gridCellSize * 2) - (lineWidth / 2) and x <= (gridCellSize * 2) + (lineWidth / 2)) then
            color = {170 / 255, 170 / 255, 170 / 255, 1}
        end
        gridImageData:setPixel(x - 1, y - 1, color)
    end
end
local gridImage = gfx.newImage(gridImageData)
gridImageData:release()

function formatTime(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, secs)
    end
    return string.format("%d:%02d", minutes, secs)
end

function isUIFocused()
    return imgui.love.GetWantCaptureKeyboard() or imgui.love.GetWantCaptureMouse()
end
local audioFilters = {
    {"OGG Vorbis (*.ogg)", "ogg"},
    {"WAV (*.wav)", "wav"},
    {"MP3 (*.mp3)", "mp3"}
}

--- @param path string
--- @param type "stream"|"static"
--- @return love.Source, string
local function loadExternalSource(path, type)
    path = path:replace("\\", "/")
    local dir = string.sub(path, 1, string.lastIndexOf(path, "/"))
    if not nativefs.mount(dir, "__nativefs__temp__") then
        return nil, "Could not mount " .. dir
    end
    local item = string.sub(path, string.lastIndexOf(path, "/") + 1)
    local source = love.audio.newSource("__nativefs__temp__/" .. item, type)
    nativefs.unmount(dir)
    if source then
        return source, nil
    end
    return nil, nil
end

love.load = function()
    love.keyboard.setKeyRepeat(true)
    love.keyboard.setTextInput(true)
    imgui.love.Init()
end

local scrollY = 0
love.update = function(dt)
    if conductor.music then
        conductor.music:setPitch(playbackRatePtr[0])
    end
    for name, track in pairs(vocals) do
        local diff = track:tell("seconds") - inst:tell("seconds")
        if math.abs(diff) >= 0.03 then
            print("Resyncing " .. name .. " to " .. math.truncate(inst:tell("seconds") * 1000.0, 3) .. "ms, was " .. math.truncate(diff * 1000.0, 3) .. "ms offset")
            track:seek(inst:tell("seconds"), "seconds")
        end
        track:setPitch(playbackRatePtr[0])
    end
    conductor.rate = playbackRatePtr[0]
    conductor:update(dt)
    scrollY = conductor.curDecStep * halfGridCellSize

    notecontainer:update(dt)

    imgui.love.Update(dt)
    imgui.NewFrame()

    musicTimePtr[0] = conductor.music and conductor.music:tell("seconds") or 0.0
end

local function setupChart(chart)
    currentChart = chart

    conductor:reset(currentChart.meta.song.timingPoints[1].bpm, currentChart.meta.song.timingPoints[1].timeSignature)
    conductor:setupTimingPoints(currentChart.meta.song.timingPoints)

    notecontainer.notes = currentChart.notes[currentDifficulty]
    endStep = conductor:getStepAtTime(inst:getDuration("seconds") * 1000.0)
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
        local trackCount = 0
        for name, _ in pairs(vocals) do
            if imgui.MenuItem_Bool("Mute " .. name) then
            end
            trackCount = trackCount + 1
        end
        if trackCount ~= 0 then
            imgui.Separator()
        end
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
            playPauseShortcut.action()
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
local playbarIcons = {
    ["start"] = love.graphics.newImage("res/images/playbar/start.png"),
    ["backward"] = love.graphics.newImage("res/images/playbar/backward.png"),
    ["pause"] = love.graphics.newImage("res/images/playbar/pause.png"),
    ["play"] = love.graphics.newImage("res/images/playbar/play.png"),
    ["forward"] = love.graphics.newImage("res/images/playbar/forward.png"),
    ["end"] = love.graphics.newImage("res/images/playbar/end.png"),
}
love.handlers.handlecustomfiledialog = function()
    local data = native.eventCallbackStorage[1]
    if data and data.f then
        data.f(table.unpack(data.args))
    end
    table.remove(native.eventCallbackStorage, 1)
end
love.draw = function()
    -- menu bar
    if imgui.BeginMainMenuBar() then
        -- shortcuts
        openShortcut = imgui.love.Shortcut({"ctrl"}, "o", shortcutActions.open)
        exitShortcut = imgui.love.Shortcut({"ctrl"}, "q", shortcutActions.exit)
        playPauseShortcut = imgui.love.Shortcut(nil, "space", shortcutActions.playPause)

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
        imgui.SameLine(imgui.GetWindowWidth() - (menuWidth + 12))
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
        local viewport = imgui.GetMainViewport()
        
        -- viewport.GetCenter() isn't an actual function i can call, so i have to calculate
        -- the center myself, no big deal though
        local center = imgui.ImVec2_Float(viewport.WorkPos.x + (viewport.WorkSize.x / 2), viewport.WorkPos.y + (viewport.WorkSize.y / 2))
        imgui.SetNextWindowPos(center, imgui.ImGuiCond_Appearing, imgui.ImVec2_Float(0.5, 0.5))

        if imgui.Begin("Select an engine to use", selectEngineActivePtr, bit.bor(imgui.ImGuiWindowFlags_AlwaysAutoResize, imgui.ImGuiWindowFlags_NoResize)) then
            imgui.Text("Select an engine to make a chart for from the list below:")
            -- TODO: allow for dynamic strumline counts
            if dynamicStrumlineFormats[curEngineList[curEngine]] then
                imgui.Text("NOTE: Dynamic strumlines aren't supported!")
            end
            for i = 1, #curEngineList do
                if imgui.RadioButton_IntPtr(curEngineList[i], curEnginePtr, i) then
                    curEngine = curEnginePtr[0] -- it's this one bro
                end
            end
            imgui.SetCursorPosX(imgui.GetContentRegionAvail().x - (imgui.CalcTextSize("OK").x + imgui.CalcTextSize("Cancel").x + (imgui.GetStyle().ItemSpacing.x * 2)))

            if imgui.Button("OK") then
                -- we confirming it
                selectEngineActivePtr[0] = false
                
                local function selectVocalTracks(metaPath, chartPaths, instPath)
                    native.showFileDialog("openfile", function(vocalPaths)
                        local format = require("formats." .. engineShorthands[curEngineList[curEngine]])

                        -- load inst
                        if inst then
                            inst:release()
                        end
                        inst = loadExternalSource(instPath, "stream")
                        conductor.music = inst

                        -- load vocals
                        for _, track in pairs(vocals) do
                            track:release()
                        end
                        vocals = {}
                        for _, path in ipairs(vocalPaths) do
                            path = path:replace("\\", "/")
                            
                            local item = string.sub(path, string.lastIndexOf(path, "/") + 1)
                            vocals[item] = loadExternalSource(path, "stream")
                        end

                        -- load chart(s)
                        -- try to guess each difficulty (defaults to normal)
                        local guessedDifficulties = {}
                        local allChartDifficulties = {}
                        for _, path in ipairs(chartPaths) do
                            path = path:replace("\\", "/")

                            local item = string.sub(path, string.lastIndexOf(path, "/") + 1)
                            item = string.sub(item, 1, string.lastIndexOf(item, ".") - 1)
                            
                            local split = item:split("-")
                            if #split < 2 then
                                split = {"normal"}
                            end
                            allChartDifficulties[path] = split[#split]
                            table.insert(guessedDifficulties, split[#split])
                        end
                        -- re-order the difficulties to easy, normal, hard, then any other extras after
                        if table.contains(guessedDifficulties, "hard") then
                            table.removeItem(guessedDifficulties, "hard")
                            table.insert(guessedDifficulties, 1, "hard")
                        end
                        if table.contains(guessedDifficulties, "normal") then
                            table.removeItem(guessedDifficulties, "normal")
                            table.insert(guessedDifficulties, 1, "normal")
                        end
                        if table.contains(guessedDifficulties, "easy") then
                            table.removeItem(guessedDifficulties, "easy")
                            table.insert(guessedDifficulties, 1, "easy")
                        end
                        -- parse each chart
                        local sharts = {}
                        local shartsByDifficulty = {}
                        for _, path in ipairs(chartPaths) do
                            path = path:replace("\\", "/")

                            -- guessedDifficulties will most likely go unused for
                            -- chart formats that have metadata files, as they usually specify difficulties themselves!
                            local chart, meta = format.parse(path, metaPath, guessedDifficulties, allChartDifficulties[path])
                            chart.meta = meta
                            table.insert(sharts, chart)
                            shartsByDifficulty[allChartDifficulties[path]] = chart
                        end
                        storedCharts = sharts

                        local diffs = sharts[1].meta.song.difficulties
                        currentDifficulty = #diffs > 1 and diffs[2] or diffs[1] -- try to pick normal, if not pick easy

                        local shartIndex = table.indexOf(sharts, shartsByDifficulty[currentDifficulty])
                        if shartIndex == -1 then
                            shartIndex = 1
                        end
                        setupChart(sharts[shartIndex])
                    end, {title = "Select some vocal tracks (cancel to skip)", multiselect = true, defaultname = "Voices.ogg", filters = audioFilters})
                end
                local function selectInst(metaPath, chartPaths)
                    native.showFileDialog("openfile", function(files)
                        if #files == 0 then
                            selectEngineActivePtr[0] = true
                            return
                        end
                        selectVocalTracks(metaPath, chartPaths, files[1])
                    end, {title = "Select an instrumental", defaultname = "Inst.ogg", filters = audioFilters})
                end
                local function selectChart(metaPath)
                    native.showFileDialog("openfile", function(files)
                        if #files == 0 then
                            selectEngineActivePtr[0] = true
                            return
                        end
                        selectInst(metaPath, files)
                    end, {title = difficultySeparatedFormats[curEngineList[curEngine]] and "Select a chart file for each difficulty" or "Select a chart file", multiselect = difficultySeparatedFormats[curEngineList[curEngine]], defaultname = "chart.json", filters = {{"Funkin' Chart JSON (*.json)", "json"}}})
                end
                if metaRequiredFormats[curEngineList[curEngine]] then
                    native.showFileDialog("openfile", function(files)
                        if #files == 0 then
                            selectEngineActivePtr[0] = true
                            return
                        end
                        selectChart(files[1])
                    end, {title = "Select a chart metadata file", defaultname = "metadata.json", filters = {{"Funkin' Chart Metadata JSON (*.json)", "json"}}})
                else
                    selectChart(nil)
                end
            end
            imgui.SameLine()
            if imgui.Button("Cancel") then
                selectEngineActivePtr[0] = false
            end
        end
        imgui.End()
    end
    -- conductor stats
    imgui.SetNextWindowPos(imgui.ImVec2_Float(5, gfx.getHeight() - 135))
    imgui.SetNextWindowSize(imgui.ImVec2_Float(100, 65))
    imgui.PushStyleColor_Vec4(imgui.ImGuiCol_WindowBg, imgui.ImVec4_Float(36.0 / 255.0, 36.0 / 255.0, 36.0 / 255.0, 1.0))
    
    if imgui.Begin("Conductor Stats", nil, bit.bor(imgui.ImGuiWindowFlags_NoTitleBar, imgui.ImGuiWindowFlags_NoResize, imgui.ImGuiWindowFlags_NoMove)) then
        imgui.Text("Step: " .. conductor.curStep)
        imgui.Text("Beat: " .. conductor.curBeat)
        imgui.Text("Measure: " .. conductor.curMeasure)
        imgui.End()
    end
    
    -- playbar
    imgui.SetNextWindowPos(imgui.ImVec2_Float(0, gfx.getHeight() - 65))
    imgui.SetNextWindowSize(imgui.ImVec2_Float(gfx.getWidth(), 65))

    if imgui.Begin("Playbar", nil, bit.bor(imgui.ImGuiWindowFlags_NoTitleBar, imgui.ImGuiWindowFlags_NoResize, imgui.ImGuiWindowFlags_NoMove)) then
        -- imgui.Button("cum")
        local curTimeString = formatTime(conductor:getCurrentTime() / 1000.0)
        imgui.SetCursorPosX(((gfx.getWidth() - 400) / 2) - (imgui.CalcTextSize(curTimeString).x + 15))
        imgui.SetCursorPosY(imgui.GetCursorPosY() + 2)
        imgui.Text(curTimeString)

        local songLengthString = formatTime(conductor.music and conductor.music:getDuration("seconds") or 0.0)
        imgui.SameLine()
        imgui.SetCursorPosX(((gfx.getWidth() - 400) / 2) + 415)
        imgui.Text(songLengthString)
        
        local musicLength = conductor.music and conductor.music:getDuration("seconds") or 0.0
        imgui.SameLine()
        imgui.SetNextItemWidth(400)
        imgui.SetCursorPosY(imgui.GetCursorPosY() - 2)
        imgui.SetCursorPosX((gfx.getWidth() - 400) / 2)

        if imgui.SliderFloat("##TimeSlider", musicTimePtr, 0, musicLength, "") then
            if conductor.music then
                conductor.music:seek(musicTimePtr[0], "seconds")
            end
            for _, track in pairs(vocals) do
                track:seek(musicTimePtr[0], "seconds")
            end
            conductor:setCurrentRawTime(musicTimePtr[0] * 1000.0)
        end
        local buttonAreaWidth = ((15 + (imgui.GetStyle().ItemSpacing.x * 2)) * 5)
        imgui.SetCursorPosX((gfx.getWidth() - buttonAreaWidth) / 2)
        imgui.SetCursorPosY(imgui.GetCursorPosY() + 3)

        imgui.ImageButton("##Start", imgui.love.TextureRef(playbarIcons["start"]), imgui.ImVec2_Float(15, 15))
        imgui.SameLine()
        imgui.ImageButton("##Backward", imgui.love.TextureRef(playbarIcons["backward"]), imgui.ImVec2_Float(15, 15))
        imgui.SameLine()
        imgui.ImageButton("##PlayPause", imgui.love.TextureRef(playbarIcons["play"]), imgui.ImVec2_Float(15, 15))
        imgui.SameLine()
        imgui.ImageButton("##Forward", imgui.love.TextureRef(playbarIcons["forward"]), imgui.ImVec2_Float(15, 15))
        imgui.SameLine()
        imgui.ImageButton("##End", imgui.love.TextureRef(playbarIcons["end"]), imgui.ImVec2_Float(15, 15))

        local difficultyString = string.title(currentDifficulty)
        imgui.SetCursorPosX(gfx.getWidth() - (imgui.CalcTextSize(difficultyString).x + (imgui.GetStyle().ItemSpacing.x * 2)))
        imgui.SetCursorPosY(imgui.GetCursorPosY() - 22)
        imgui.Button(difficultyString)
        
        imgui.End()
    end
    imgui.PopStyleColor(1)

    -- render our own stuff just before imgui
    -- bg
    local bgScaleX = math.max(gfx.getWidth() / 1280, 1)
    local bgScaleY = math.max(gfx.getHeight() / 720, 1)

    local bgScale = (bgScaleY > bgScaleX) and bgScaleY or bgScaleX

    gfx.setColor(100 / 255, 57 / 255, 180 / 255, 1)
    gfx.draw(bgDesat, (gfx.getWidth() - (bgDesat:getWidth() * bgScale)) / 2, (gfx.getHeight() - (bgDesat:getHeight() * bgScale)) / 2, 0, bgScale)
    gfx.setColor(1, 1, 1, 1) -- restore to default coloring
    
    -- grid
    local gridCenterY = ((love.graphics.getHeight() - gridImage:getHeight()) / 2) + 35
    local gridScrollX = ((love.graphics.getWidth() - gridImage:getWidth()) / 2)
    local gridScrollY = gridCenterY - (scrollY % gridImage:getHeight())
    local gridScrollYNoWrap = gridCenterY - scrollY
    
    local repeatCount = math.ceil(gfx.getHeight() / 720)
    for i = 1, repeatCount do
        gfx.draw(gridImage, gridScrollX, gridScrollY - (gridImage:getHeight() * i))
        gfx.draw(gridImage, gridScrollX, gridScrollY + (gridImage:getHeight() * i))
    end
    gfx.draw(gridImage, gridScrollX, gridScrollY)
    
    -- beat & measure separators
    local curBeat = conductor.curBeat - 16
    local endBeat = conductor.curBeat + 16
    
    local curMeasure = conductor.curMeasure - 16
    local endMeasure = conductor.curMeasure + 16

    while curBeat < endBeat do
        local beatTime = conductor:getTimeAtBeat(curBeat)

        local posY = halfGridCellSize * conductor:getStepAtTime(beatTime)
        gfx.setColor(170 / 255, 170 / 255, 170 / 255, 1)
        gfx.rectangle("fill", gridScrollX, (gridScrollYNoWrap + (gridCellSize * 4)) + posY - 4, gridImage:getWidth(), 3)
        
        curBeat = curBeat + 1
    end
    while curMeasure < endMeasure do
        local measureTime = conductor:getTimeAtMeasure(curMeasure)
        
        local posY = halfGridCellSize * conductor:getStepAtTime(measureTime)
        gfx.setColor(100 / 255, 100 / 255, 100 / 255, 1)
        gfx.rectangle("fill", gridScrollX, (gridScrollYNoWrap + (gridCellSize * 4)) + posY - 6, gridImage:getWidth(), 5)

        curMeasure = curMeasure + 1
    end

    -- top area (indicating notes can't be placed before the song)
    gfx.setColor(0, 0, 0, 0.25)

    local coverHeight = gridCellSize * (gfx.getHeight() / 180)
    gfx.rectangle("fill", gridScrollX, (gridScrollYNoWrap + (gridCellSize * 4)) - coverHeight - 1, gridImage:getWidth(), coverHeight)
    gfx.rectangle("fill", gridScrollX, (gridScrollYNoWrap + (gridCellSize * 4)) - 4, gridImage:getWidth(), 3)

    -- bottom area (indicating notes can't be placed after the song)
    gfx.rectangle("fill", gridScrollX, (gridScrollYNoWrap + (gridCellSize * 4)) + (endStep * halfGridCellSize) - 1, gridImage:getWidth(), coverHeight)
    gfx.rectangle("fill", gridScrollX, (gridScrollYNoWrap + (gridCellSize * 4)) + (endStep * halfGridCellSize) - 1, gridImage:getWidth(), 3)
    gfx.setColor(1, 1, 1, 1) -- restore to default coloring
    
    -- notes & events
    notecontainer:draw(gridScrollX, gridScrollYNoWrap + (gridCellSize * 4))

    -- visual playhead bar thing
    gfx.setColor(189 / 255, 2 / 255, 49 / 255, 1)
    gfx.rectangle("fill", gridScrollX, (gridCenterY + (gridCellSize * 4)) - 5, gridImage:getWidth(), 3)
    gfx.setColor(1, 1, 1, 1) -- restore to default coloring
    
    -- code to render imgui
    imgui.Render()
    imgui.love.RenderDrawLists()

    local font = love.graphics.getFont()
    local str = tostring(love.timer.getFPS()) .. " FPS"
    gfx.print(str, (gfx.getWidth() - font:getWidth(str) - 5), gfx.getHeight() - 85)
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
    if not imgui.love.GetWantCaptureKeyboard() then
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