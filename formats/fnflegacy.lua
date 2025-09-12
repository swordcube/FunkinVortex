local generic = require("formats.generic")

local json = require("thirdparty.json") --- @type thirdparty.Json
local nativefs = require("thirdparty.nativefs") --- @type thirdparty.NativeFS

local format = {}

function format.parse(chartPath, _, guessedDifficulties, currentDifficulty)
    local json = json.parse(nativefs.read("string", chartPath)).song
    local chart, meta = generic.createTemplate()

    local sectionTime = 0
    local sectionBPM = json.bpm

    local lengthInSteps = json.notes[1].lengthInSteps or 16
    meta.song.title = json.song
    meta.song.timingPoints = {
        {
            time = 0,
            bpm = json.bpm,
            timeSignature = {4, lengthInSteps / 4}
        }
    }
    meta.song.difficulties = guessedDifficulties

    for i = 1, #guessedDifficulties do
        chart.notes[guessedDifficulties[i]] = {}
    end
    for i = 1, #json.notes do
        local section = json.notes[i]
        table.insert(chart.events, {
            time = sectionTime,
            name = "Camera Pan",
            params = {char = section.mustHitSection and 1 or 0}
        })
        for j = 1, #section.sectionNotes do
            local note = section.sectionNotes[j]
            local lane = note[2] % 8 --- 0-3 = opponent, 4-7 = player
            if section.mustHitSection then
                lane = (note[2] + 4) % 8 --- 0-3 = player, 4-7 = opponent
            end
            table.insert(chart.notes[currentDifficulty], {
                time = note[1],
                lane = lane,
                length = note[3],
                type = "Default"
            })
        end
        sectionTime = sectionTime + (60000 / sectionBPM) * (lengthInSteps / 4)
        
        local makeTimingPoint = false
        if section.changeBPM and section.bpm > 0 then
            sectionBPM = section.bpm
            makeTimingPoint = true
        end
        if lengthInSteps ~= section.lengthInSteps or 16 then
            lengthInSteps = section.lengthInSteps or 16
            makeTimingPoint = true
        end
        if makeTimingPoint then
            table.insert(meta.song.timingPoints, {
                time = sectionTime,
                bpm = sectionBPM,
                timeSignature = {4, lengthInSteps / 4}
            })
        end
    end
    table.sort(chart.notes[currentDifficulty], function(a, b)
        if a.time ~= b.time then
            return a.time < b.time
        end
        return a.lane < b.lane
    end)
    table.sort(meta.song.timingPoints, function(a, b)
        return a.time < b.time
    end)
    -- print(#chart.notes[currentDifficulty])
    return chart, meta
end

return format