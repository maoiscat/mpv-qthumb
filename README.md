update:

ver 2.0		use a seperate file to simulate ipc connection. this script now works in both windows and linux.

ver 1.1		some improvemnts on qthumbShow()

# mpv-qthumb

qthumb is a simple thumbnail generator that helps you to show small thumbnails over an osc/ui in mpv.

qthumb will **NOT** spawn real time thumbnails. when loading a file, it scans the file with a preconfigured skip time, and generates cached images as thumbnails.

qthumb needs **mpv version 0.35 and higher**. it uses an non-standard way to get the address of a variable, which is not implemented in standard lua.

qthumb is not fully tested. please feel free to report bugs.

![img](https://github.com/maoiscat/mpv-qthumb/blob/main/preview.jpg)

## Install

1. download the source files as zip package.
2. extrac the qthumb folder to ''\~\~/scripts'' folder of your mpv.
3. DO NOT rename the folder or any script within.
4. this script will autoload and run

## Usage

This script works with a custom osd/ui script.

Use the following lines to change options for qthumb. 

```
local opts = {width = 200, skip = 10}
local json, err = utils.format_json(opts)
mp.commandv('script-message-to', 'qthumb', 'qthumb-set-param', json)
```

A full list of opts includes

```
mpvPath = 'mpv',	-- full path or single file name. file extension does not matter
tmpPath = nil,		-- temp file path, end with / or \\. nil for auto detection
oid = 10,		-- overlay id
width = 200,		-- thumb width
height = 200,		-- thumb height, not used currently
skip = 10		-- seconds between two thumbnails, smaller means more thumbnails
```

You can apply your options at any time, but it only takes effect on loading a new file.

To check thumb status, use these to set up a ''param'' var to check thumbnail params

```
local param
mp.register_script_message('qthumb-params', function(json) param = utils.parse_json(json) end)
```

currently param includes:
```
	width	-- thumbnail real width
	height	-- thumbnail real height
	estSkip	-- estimated average skip time between thumbnail frames
```

This qthumb-params message will generate when a new frame of thumbnail is done, which may change the value of estSkip.

To show a thumbnail, use

```
mp.commandv('script-message-to', 'qthumb', 'qthumb-show', x, y, seconds)
```

here x, y are **INTEGERs**, while seconds can be decimal.

To hide it, just use

```
mp.commandv('script-message-to', 'qthumb', 'qthumb-hide')
```
