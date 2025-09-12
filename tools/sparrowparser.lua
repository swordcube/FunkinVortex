local xml = require("thirdparty.xml") --- @type thirdparty.Xml

--- @class tools.SparrowParser
local parser = {}

-- NOTE: This doesn't support rotated frames, this was just made for note rendering!

local gfx = love.graphics
local fs = love.filesystem

--- @param imgpath string
--- @param xmlpath string
function parser.parse(imgpath, xmlpath)
    local img = gfx.newImage(imgpath)
    local rawXml = fs.read("string", xmlpath)

    local xmlData = xml.parse(rawXml)
    local atlas = {
        img = img,
        frames = {}
    }
    local rawFrames = xmlData.TextureAtlas.children
    for i = 1, #rawFrames do
        local child = rawFrames[i]

        local animName = string.sub(child.att.name, 1, string.len(child.att.name) - 4)
        if not atlas.frames[animName] then
            atlas.frames[animName] = {}
        end
        local frame = {
            id = tonumber(string.sub(child.att.name, string.len(child.att.name) - 3)),
            x = tonumber(child.att.x),
            y = tonumber(child.att.y),
            offsetX = -tonumber(child.att.frameX),
            offsetY = -tonumber(child.att.frameY),
            width = tonumber(child.att.width),
            height = tonumber(child.att.height),
            quad = nil --- @type love.Quad
        }
        frame.quad = gfx.newQuad(frame.x, frame.y, frame.width, frame.height, img:getDimensions())
        table.insert(atlas.frames[animName], frame)
    end
    for _, frames in pairs(atlas.frames) do
        table.sort(frames, function(a, b)
            return a.id < b.id
        end)
    end
    return atlas
end

return parser