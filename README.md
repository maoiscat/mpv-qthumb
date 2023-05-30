# mpv-qthumb

qthumb is a simple thumbnail generator that helps you to show small thumbnails over an osc/ui in mpv.

qthumb will NOT spwan real time thumbnails. when loading a file, it scans the file with a preconfigured skip time, and generates cached images as thumbnails. as a result, it may consume more memery but save some cpu time.

qthumb only works on windows by now, because the input-ipc-server option on linux actually creates a socket, rather than a pipe, which means the lua io functions cannot operate this file directly.

qthumb is not fully tested. please feel free to report bugs.

![img](https://github.com/maoiscat/mpv-qthumb/blob/main/preview.jpg)

## Install

1. download the source files as zip package.
2. extrac the qthumb folder to ''\~\~/scripts'' folder of your mpv.
3. DO NOT rename the folder or any script within.

## Usage

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

On the ui side, you can use these codes to check if thumbnails are generated.

```
local param = {width, height, estSkip}
local json, err = utils.format_json(thumbOpts)
mp.register_script_message('qthumb-params', function(data)
		param = utils.parse_json(data)
	end)
```

Here width and height are real geometries of the thumbnails. estSkip is the average estimated skip parameter. This qthumb-params message will generate when a new frame of thumbnail is done, which may change the value of estSkip.

To show a thumbnail, use

```
mp.commandv('script-message-to', 'qthumb', 'qthumb-show', x, y, seconds)
```

here x, y are integer, while seconds can be decimal.

To hide it, just use

```
mp.commandv('script-message-to', 'qthumb', 'qthumb-hide')
```
