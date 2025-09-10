function love.conf(t)
    t.identity = "FunkinVortex"
    t.version = "12.0"
    t.console = false

    t.graphics.gammacorrect = false

    t.highdpi = false
    t.usedpiscale = false

    t.window.title = "Funkin' Vortex"

    t.window.width = 960
    t.window.height = 720

    t.window.minwidth = 200
    t.window.minheight = 0

    t.window.resizable = false
    t.window.fullscreen = false
    t.window.vsync = false
end
