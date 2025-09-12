local conductor = require("conductor") --- @type Conductor
local class = require("thirdparty.middleclass") --- @type thirdparty.MiddleClass
local sparrowparser = require("tools.sparrowparser") --- @type tools.SparrowParser

local dirs = {"left", "down", "up", "right"}

--- @class containers.notecontainer
local notecontainer = class("notecontainer")

local gfx = love.graphics

function notecontainer:__init__()
    self.notes = {}
    self.atlas = sparrowparser.parse("res/images/notes.png", "res/images/notes.xml")
    self.atlas.img:setFilter("linear", "linear")

    self.beginIndex = 1
    self.endIndex = 1

    self.hitsound = love.audio.newSource("res/sfx/hitsound_tump.ogg", "static")
end

function notecontainer:update(dt)
    if #self.notes == 0 then
        self.beginIndex, self.endIndex = 1, 1
        return
    end
    local spacingMS = gfx.getHeight() * 2
    local c = conductor.instance --- @type Conductor
    
    -- would this be considered a binary search? idk but it works
    local beginIndex = 1
    while beginIndex < #self.notes and c:getCurrentPlayhead() > self.notes[beginIndex].time + (spacingMS + math.max(self.notes[beginIndex].length, 0)) do
        beginIndex = beginIndex + 1
    end
    local endIndex = beginIndex
    while endIndex < #self.notes and c:getCurrentPlayhead() > self.notes[endIndex].time - (spacingMS + math.max(self.notes[beginIndex].length, 0)) do
        endIndex = endIndex + 1
    end
    self.beginIndex, self.endIndex = beginIndex, endIndex
end

function notecontainer:draw(offsetX, offsetY)
    if #self.notes == 0 then
        return
    end
    local c = conductor.instance --- @type Conductor
    for i = self.beginIndex, self.endIndex do
        local note = self.notes[i]
        local mainFrame = self.atlas.frames[dirs[(note.lane % 4) + 1] .. " scroll"][1] -- holy shit i'm hacking into the mainframe oughghghgh
        
        local scaleX = 40 / mainFrame.width
        local scaleY = 40 / mainFrame.height
        
        local posX = (note.lane * 40) + (mainFrame.offsetX * (40 / mainFrame.width))
        local posY = (c:getStepAtTime(note.time) * 40) + (mainFrame.offsetY * (40 / mainFrame.height))
        
        local pr, pg, pb, pa = gfx.getColor()

        local prevWasHit = note.wasHit or false
        note.wasHit = c:getCurrentPlayhead() >= note.time and not ((not c.music or not c.music:isPlaying()) and c:getCurrentPlayhead() <= note.time)
        
        local canPlaySFX = (note.lane < 4 and settings.playOpponentHitsounds) or (note.lane > 3 and settings.playPlayerHitsounds)
        if canPlaySFX and c.music and c.music:isPlaying() and note.wasHit and note.wasHit ~= prevWasHit then
            self.hitsound:seek(0, "seconds")
            self.hitsound:play()
        end
        gfx.setColor(1, 1, 1, note.wasHit and 0.45 or 1)
        
        if note.length > 0 then
            local holdFrame = self.atlas.frames[dirs[(note.lane % 4) + 1] .. " hold"][1]
            local tailFrame = self.atlas.frames[dirs[(note.lane % 4) + 1] .. " tail"][1]
            gfx.draw(self.atlas.img, holdFrame.quad, posX + (((mainFrame.width * scaleX) - (holdFrame.width * scaleX)) / 2) + offsetX, posY + ((mainFrame.height * scaleY) / 2) + offsetY, 0, scaleX, (((note.length - tailFrame.height) + 2) / holdFrame.height) * scaleY)
            gfx.draw(self.atlas.img, tailFrame.quad, posX + (((mainFrame.width * scaleX) - (tailFrame.width * scaleX)) / 2) + offsetX, posY + ((mainFrame.height * scaleY) / 2) + ((note.length - tailFrame.height) * scaleY) + offsetY, 0, scaleX, scaleY)
        end
        gfx.draw(self.atlas.img, mainFrame.quad, posX + offsetX, posY + offsetY, 0, scaleX, scaleY)
        gfx.setColor(pr, pg, pb, pa)
    end
end

return notecontainer