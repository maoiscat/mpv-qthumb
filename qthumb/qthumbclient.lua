-- qthumb client to do the dirty work

local host = mp.get_opt('host')
local skip = mp.get_opt('skip')
local ready = false

local function FileLoaded()
	ready = true
end

local function Seeking(name, val)	-- file loaded will also trigger a seeking event
	if not ready or val then return end	-- val == false means seeking is over, then notify the host to get the thumb file
	local p = io.open(host, 'w')
	local time = mp.get_property('time-pos')	-- the time position is notified as well so that we can index a thumbnai by time
	if not time then return end
	p:write('script-message-to qthumb qthumb-get-data ' .. time .. '\n')
	p:close()
end

local function Next()
	mp.commandv('seek', skip)	-- relative seeking is much faster, though poor in accuracy
end

mp.register_event('file-loaded', FileLoaded)
mp.observe_property('seeking', 'bool', Seeking)
mp.register_script_message('qthumb-next', Next)