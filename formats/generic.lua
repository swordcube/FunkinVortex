local format = {}

function format.createTemplate()
    local chart = {
        notes = {},
        events = {},
    }
    local meta = {
        song = {
            title = "N/A",
            artist = "N/A",
            charter = "N/A",

            difficulties = {"easy", "normal", "hard"},
            timingPoints = {}
        },
        game = {
            scrollSpeed = {},
            characters = {
                opponent = "dad",
                player = "bf",
                spectator = "gf"
            }
        }
    }
    return chart, meta
end

return format