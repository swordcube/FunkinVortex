local format = {}

function format.createTemplate()
    return {
        notes = {},
        events = {},
        
        meta = {
            title = "N/A",
            artist = "N/A",
            charter = "N/A"
        },
        song = {
            timingPoints = {}
        }
    }
end

return format