-- qthumb is a simple thumbnail generator for mpv
-- by maoiscat
-- ver 2.0

local utils = require 'mp.utils'

local opts = {			-- options are applied only when a new file is loaded
	mpvPath = 'mpv',	-- full path or single file name. file extension does not matter
	tmpPath = nil,		-- temp file path, end with '\' or '//'. nil for auto detection
	oid = 10,			-- overlay id
	width = 200,		-- thumb width
	height = 200,		-- thumb height, not used currently
	skip = 10			-- seconds between two thumbnails
	}

local pid = utils.getpid()	-- use pid as unique pattern
local ipcTimer = nil		-- a timer to operate ipcFile
local ipcTick = 0.05		-- ipc timer interval
local ipcFile				-- ipc file for communication, tmpFile.ipc
local mpvPath, tmpPath, oid, width, height, skip -- copy of opts
local tmpFile				-- prefix of temp files
local outFile				-- output file, tmpFile.out
local stride				-- overlay parameter, eqs 4*width
local estSkip				-- estimate real skip value due to keyframe seeking methods
local visible = false		-- thumbnail visibility
local pHost, pClient		-- host pipe name, client pipe name
local count					-- total thumbnail count
local times					-- thumbnail time tab
local data					-- thumbnail data
local pData					-- thumb data reference(pointer)
local autoPath

local args = { mpvPath, fname, tmpFile, vf, scriptopts,
		'--script=' .. mp.get_script_directory() ..'/qthumbclient.lua',
		'--ovc=rawvideo',	'--of=image2',	'--ofopts=update=1',	'--pause',	'--idle',	
		'--no-config',		'--no-ytdl',	'--no-sub',	'--no-audio',	'--no-osc',
		'--load-stats-overlay=no',	'--load-osd-console=no',	'--load-auto-profiles=no',	'--load-scripts=no',
		'--really-quiet',		'--no-terminal',			
		}

-- get current system type
local function GetOS()
	local pattern = package.cpath:match('[.](%a+)')
	if pattern == 'dll' then
		return 'windows'
	elseif pattern == 'so' then
		return 'linux'
	elseif pattern == 'dylib' then
		return 'macos'
	end
	return nil
end

local system = GetOS()
if system == 'windows' then
	autoPath = os.getenv('TEMP') .. '\\'
elseif system == 'linux' then
	autoPath = '/tmp/'
elseif system == 'macos' then
	autoPath = os.getenv('TMPDIR')	-- not sure if it works
else
	mp.msg.error('Unknown os type')
	return
end


-- set option params
-- allow partial settings
function QthumbSetParam(options)
	for k, v in pairs(options) do
		opts[k] = v
	end
end

-- set opts params using script message, data is in json format
local function SetParam2(data)
	local var = utils.parse_json(data)
	print(utils.to_string(var))
	QthumbSetParam(var)
end

-- get real thumbnail params
function QthumbGetParam()
	return {
		width = width,
		height = height,
		estSkip = estSkip
		}
end

-- remove temp files
local function Cleanup()
	if ipcTimer then
		ipcTimer:kill()
		ipcTimer = nil
	end
	os.remove(outFile)
	os.remove(ipcFile)
end

-- collect thumbnail data
local function GetData(time)
	count = count + 1
	times[count] = tonumber(time)
	-- average estimated skip may change as more data are captured
	estSkip = (time + skip) / count
	-- read the temp file as a frame of thumbnails
	local file = io.open(outFile, 'rb')
	data[count] = file:read('*a')
	file:close()
	pData[count] = string.format('&%p', data[count])
end

local function IpcControl()
	local file = io.open(ipcFile, 'r')
	if not file then return end
	local subject = file:read('*l')
	local info = file:read('*l')
	local time
	file:close()
	-- sometimes got nil info, ignore
	if not (subject and info) then return end
	-- check if client says something
	if subject ~= 'client' then return end
	-- if client exits, use the last thumb to complete the timeline
	if info == 'end' then
		time = mp.get_property_native('duration')
	else
		time = info
	end
	if time then GetData(time) end
	-- to tell ui scripts to update
	local json, err = utils.format_json(QthumbGetParam())
	mp.commandv('script-message', 'qthumb-params', json)
	if info == 'end' then
		-- all thumbs got
		Cleanup()
	else
		-- tell client to get next thumb
		file = io.open(ipcFile, 'w')
		file:write('host\nnext')
		file:close()
	end
end

-- Show thumbnail of (second) time at (x, y) position
function QthumbShow(x, y, second)
	-- check if there are thumbnails
	if count == 0 then return end
	second = tonumber(second)
	-- check if there are thumbnails at given time
	if times[count] < second then
		QthumbHide()
		return
	end
	-- estimate the index among all thumbnails for faster search
	local begin = math.max(1, math.floor(second / estSkip))
	local ind = 1
	if times[begin] > second then	-- when given seconds is greater than estimated time, search downside
		for i = begin, 1, -1 do
			if times[i] <= second then
				ind = i
				break
			end
		end
	else	-- otherwise search upside
		for i = begin, count do
			if times[i] <= second then
				ind = i
			else
				break
			end
		end
	end
	-- show the thumb
	mp.command_native({name = 'overlay-add', id = oid, x = x, y = y, file = pData[ind], offset = 28, fmt = 'bgra', w = width, h = height, stride = stride})
	visible = true
end

-- Hide thumbnail
function QthumbHide()
	if visible and oid then
		mp.command_native({name = 'overlay-remove', id = oid})
		visible = false
	end
end

local function FileLoaded()
	QthumbHide()
	-- initialize working vars
	mpvPath = opts.mpvPath
	tmpPath = opts.tmpPath
	oid = opts.oid
	width = math.floor(opts.width+0.5)
	skip = opts.skip
	count, times, data, pData =0, {}, {}, {}
	-- if tmpPath is nil, use autoPath 
	local path = tmpPath or autoPath
	tmpFile = string.format('%smpv-%d', path, pid)
	-- check output file
	outFile = tmpFile .. '.out'
	local file = io.open(outFile, 'w')
	if not file then
		mp.msg.error('Cannot creat temp file.')
		outFile = nil
		return
	end
	file:close()
	-- check ipc file
	ipcFile = tmpFile .. '.ipc'	
	local file = io.open(ipcFile, 'w')
	if not file then
		mp.msg.error('Cannot creat ipc file.')
		ipcFile = nil
		return
	end
	file:write('host\ninit')
	file:close()
	-- check open file name
	local fileName = mp.get_property_native('path')
	if not fileName then
		mp.msg.error('No file name.')
		return
	end
	-- start a timer for ipc control
	ipcTimer = mp.add_periodic_timer(ipcTick, IpcControl)
	if not ipcTimer then
		mp.msg.error('IPC control timer error.')
		return
	end
	-- determine video aspect
	-- it is strange that some times video-params don't have aspect ratio param
	-- need to calculate 
	local vp = mp.get_property_native('video-params')
	if not (vp and vp.w and vp.w>0 and vp.h and vp.h>0) then
		mp.msg.error('Bad video params.')
		return
	end
	height = math.floor(vp.h / vp.w * width + 0.5)
	stride = 4*width
	-- set arguments for client mpv process. the client writes images to a temp file, from which the host reads as thumbnails
	args[1] = mpvPath
	args[2] = fileName
	args[3] = '--o=' .. outFile
	args[4] = string.format('--vf=scale=w=%d:h=%d,format=bgra', width, height)
	args[5] = '--script-opts=qthumb_skip=' .. skip .. ',qthumb_ipc=' .. ipcFile

	mp.command_native_async({name = 'subprocess', args = args})
end

-- Some event handlers
mp.register_event('file-loaded', FileLoaded)
mp.register_event('shutdown', Cleanup)
mp.register_script_message('qthumb-show', QthumbShow)
mp.register_script_message('qthumb-hide', QthumbHide)
mp.register_script_message('qthumb-get-data', GetData)
mp.register_script_message('qthumb-set-param', SetParam2)
