-- Desktop LÖVE only (LoveDOS never reads conf.lua)
function love.conf(t)
	t.identity = "mod-player"         -- save folder for settings.txt and the sample .wavs
	t.window.title = "MOD PLAYER by SiENcE.github.io"
	t.window.width = 1280             -- 640x400 canvas at 2x
	t.window.height = 800
	t.window.minwidth = 640
	t.window.minheight = 400
	t.window.resizable = true
	t.console = true           -- Attach a console (boolean, Windows only)
	t.window.vsync = 1
end
