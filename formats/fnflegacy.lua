local generic = require("formats.generic")

local json = require("thirdparty.json") --- @type thirdparty.Json
local nativefs = require("thirdparty.nativefs") --- @type thirdparty.NativeFS

local format = {}

function format.parse(chartPath, _)
    local json = json.parse(nativefs.read("string", chartPath))
    local chart = generic.createTemplate()

    return chart
end

return format