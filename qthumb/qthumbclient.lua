-- qthumb client to do the dirty work

local fileLoaded = false
local isSeeking = true
local thumbGet = false
local spwan = false
local skip = mp.get_opt('qthumb_skip')
local ipcFile = mp.get_opt('qthumb_ipc')
local ipcTimer = nil
local ipcTick = 0.05

local function IpcControl()
	if isSeeking then return end
	local file = io.open(ipcFile, 'r')
	if not file then return end
	local subject = file:read('*l')
	local info = file:read('*l')
	file:close()
	if not (info and subject) then return end
	if subject ~= 'host' then return end
	if thumbGet then
		-- seek to next time pos
		isSeeking = true
		thumbGet = false
		mp.commandv('seek', skip)	-- relative seeking is much faster, though poor in accuracy
	else
		-- notify the host to get thumb
		info = mp.get_property('time-pos')
		if not info then info = 'end' end
		local file = io.open(ipcFile, 'w')
		file:write('client\n' .. info)
		file:close()
		thumbGet = true
		if info == 'end' then
			mp.commandv('quit')
		end
	end
end

local function FileLoaded()
	fileLoaded = true
end

local function Seeking(name, val)
	if not fileLoaded or val then return end
	isSeeking = val
end

mp.register_event('file-loaded', FileLoaded)
mp.observe_property('seeking', 'bool', Seeking)
ipcTimer = mp.add_periodic_timer(ipcTick, IpcControl)