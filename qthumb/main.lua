-- qthumb is a simple thumbnail generator for mpv
-- maoiscat: valarmor@163.com

local utils = require 'mp.utils'

local opts = {			-- options are applied only when a new file is loaded
	mpvPath = 'mpv',	-- full path or single file name. file extension does not matter
	tmpPath = nil,		-- temp file path, end with / or \\. nil for auto detection
	oid = 10,			-- overlay id
	width = 200,		-- thumb width
	height = 200,		-- thumb height, not used currently
	skip = 10			-- seconds between two thumbnails
	}

local pid = utils.getpid()	-- use pid as unique pattern
local mpvPath, tmpPath, tmpFile, oid, width, height, skip -- copy of opts
local stride, estSkip	-- stride: overlay param, eqs 4*width, estSkip: estimate real skip value due to keyframe seeking methods
local pHost, pClient, fClient	-- host pipe name, client pipe name, client pipe file handle
local count, times, data, pData	-- total thumb count, thumb time, thumb data, thumb data reference(pointer)
local autoPipe = {	-- only tested on windows
		windows = '\\\\.\\pipe\\mpv\\' .. pid,
		linux = '/tmp/mpv-' .. pid,
		macos = '/tmp/mpv-' .. pid,
		}
local autoPath = {	-- only tested on windows
		windows = {os.getenv('TEMP') .. '\\', os.getenv('windir') .. '\\TEMP\\', '.\\'},
		linux = {'/proc/', '/tmp/', '/var/', './'},
		macos = {'/proc/', '/tmp/', '/var/', './'},
		}
local args = { mpvPath, fname, tmpFile, vf, inputipc, scriptopts,	-- volatile params, others are fixed params
		'--script=' .. mp.get_script_directory() ..'/qthumbclient.lua', '--ovc=rawvideo', '--of=image2', '--ofopts=update=1', '--pause', '--no-config', '--load-scripts=no', '--really-quiet', '--no-terminal', '--osc=no', '--ytdl=no', '--load-stats-overlay=no', '--load-osd-console=no', '--load-auto-profiles=no', '--no-sub', '--no-audio'
		}

function QthumbSetParam(options)	-- set opts params, allow partial settings
	for k, v in pairs(options) do
		opts[k] = v
	end
end

function QthumbGetParam()			-- get real params
	return {
		width = width,
		height = height,
		estSkip = estSkip
		}
end

local function SMSetParam(data)		-- set opts params using script message, data is in json format
	local var = utils.parse_json(data)
	QthumbSetParam(var)
end

local function Cleanup()			-- remove temp files
	if tmpFile then
		os.remove(tmpFile)
	end
end

local function GetOS()				-- only tested on windows
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

local function FileLoaded()
	Cleanup()
	-- initialize working vars
	mpvPath = opts.mpvPath
	tmpPath = opts.tmpPath
	oid = opts.oid
	width = math.floor(opts.width+0.5)
	skip = opts.skip
	count, times, data, pData =0, {}, {}, {}
	-- if tmpPath is nil, it will use the first available path in autoPath 
	local path = tmpPath or autoPath[GetOS()]
	for k, v in ipairs(path) do
		tmpFile = string.format('%smpv-%d.out', v, pid)
		local file = io.open(tmpFile, 'w')
		if file then
			tmpPath = v
			file:close()
			break
		end
		tmpFile = nil
	end
	if not tmpFile then
		mp.msg.error('Cannot creat temp file.')
		return
	end
	
	local fname = mp.get_property_native('path')
	if not fname then
		mp.msg.error('No file name.')
		return
	end
	-- it is strange that some times video-params don't have aspect ratio 
	local vp = mp.get_property_native('video-params')
	if not (vp and vp.w and vp.w>0 and vp.h and vp.h>0) then
		mp.msg.error('Bad video params.')
		return
	end
	height = math.floor(vp.h / vp.w * width + 0.5)
	stride = 4*width
	-- set arguments for client mpv process. the client writes images to a temp file, from which the host reads as thumbnails
	args[1] = mpvPath
	args[2] = fname
	args[3] = '--o=' .. tmpFile
	args[4] = string.format('--vf=scale=w=%d:h=%d,format=bgra', width, height)
	args[5] = '--input-ipc-server=' .. pClient
	args[6] = '--script-opts=host=' .. pHost .. ',skip=' .. skip

	mp.command_native_async({name = 'subprocess', args = args})
end

local function GetData(time)	-- collect thumbnail data when ready, called by client from script message
	count = count + 1
	times[count] = tonumber(time)
	estSkip = (time + skip) / count -- average estimated skip may change as more data are captured
	
	local f = io.open(tmpFile, 'rb')	-- read the temp file as a frame of thumbnails
	data[count] = f:read('*a')
	pData[count] = string.format('&%p', data[count])
	f:close()

	local p = io.open(pClient, 'w')		-- to notify the client to generate next thumbnail frame
	p:write('script-message-to qthumbclient qthumb-next\n')
	p:close()
	local json, err = utils.format_json(QthumbGetParam())
	mp.commandv('script-message', 'qthumb-params', json)	-- to tell ui scripts that there are new params
end

function QthumbShow(x, y, second)	-- generate a thumb at (x, y) position around (second) time
	if not times[1] then return end	-- times[1] == nil means no thumb at all
	second = tonumber(second)
	local begin = math.max(1, math.floor(second / estSkip))	-- estimate the index among all thumbnails for faster search
	local ind
	if not times[begin] or times[begin] > second then	-- when given seconds is greater than estimated time, search downside
		ind = 1
		for i = begin, 1, -1 do
			if times[i] and times[i] <= second then
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
	-- then a thumbnail is generated
	mp.command_native({name = 'overlay-add', id = oid, x = x, y = y, file = pData[ind], offset = 28, fmt = 'bgra', w = width, h = height, stride = stride})
end

local function QthumbHide(x, y, second)	-- there is show, there is hide
	if oid then
		mp.command_native({name = 'overlay-remove', id = oid})
	end
end

-- Some event handlers
mp.register_event('file-loaded', FileLoaded)
mp.register_event('shutdown', Cleanup)
mp.register_script_message('qthumb-get-data', GetData)
mp.register_script_message('qthumb-show', QthumbShow)
mp.register_script_message('qthumb-hide', QthumbHide)
mp.register_script_message('qthumb-set-param', SMSetParam)

-- when initialized, the host mpv starts an input ipc server to interact with the client
local pipe = autoPipe[GetOS()]
pClient = pipe .. '.client'
pHost = pipe .. '.host'
mp.commandv('set', 'input-ipc-server', pHost)
