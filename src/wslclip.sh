# shellcheck shell=bash
content=""
clipboard_action="set"
get_image=""
get_image_set=0
content_set=0

help_short="wslclip [OPTIONS] [CONTENT ...]\nwslclip --get-image FILE"
help_details='Get or set the Windows clipboard from WSL without X or Wayland.

Arguments:
  CONTENT         Text to place on the Windows clipboard. All remaining
                  command-line words are joined as the content.
  standard input  When CONTENT is omitted and input is piped, copy that input.
  no input        When neither CONTENT nor piped input is present, clear the clipboard.

Options:
  -g, --get       Print the clipboard; cannot be combined with CONTENT.
  -i, --get-image FILE
                  Get a clipboard image into FILE; the format follows the
                  extension (png, jpg, jpeg, bmp; png by default).
  --              End option parsing; use before CONTENT that starts with a dash.
  -h, --help      Show this help.
  -v, --version   Show the wslu version.

Examples:
  wslclip "copied text"
  printf %s "copied text" | wslclip
  wslclip --get
  wslclip --get-image ~/shots/screenshot.png'

function get_clipboard {
    winps_exec "\$ErrorActionPreference='Stop'; Get-Clipboard"
}

function set_clipboard {
	if [[ -z $1 ]]; then
		winps_exec "\$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Clipboard]::Clear()"
	else
		printf %s "$1" | winps_exec_stdin "\$ErrorActionPreference='Stop'; [Console]::InputEncoding=[Text.Encoding]::UTF8; Set-Clipboard -Value ([Console]::In.ReadToEnd())"
	fi
}

function get_clipboard_image {
    local winpath
    local image_format
    case "${get_image##*.}" in
        jpg|jpeg) image_format="Jpeg";;
        bmp) image_format="Bmp";;
        *) image_format="Png";;
    esac
    if [[ "$get_image" =~ ^[A-Za-z]\:.*$ ]]; then
        winpath="$get_image"
    else
        winpath="$(wslpath -w "$get_image")"
    fi
    debug_echo "image target: $winpath"
    winps_exec "\$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.Windows.Forms; \$img=[System.Windows.Forms.Clipboard]::GetImage(); if (\$img -eq \$null) { throw 'No image found on the Windows clipboard.' }; \$img.Save($(winps_string "$winpath"), [System.Drawing.Imaging.ImageFormat]::$image_format)"
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		-h|--help) help "$0" "$help_short"; exit;;
		-v|--version) version; exit;;
		-g|--get) clipboard_action="get"; shift;;
		-i|--get-image)
			if [ -z "${2:-}" ] || [[ "$2" == -* ]]; then
				error_echo "$1 requires FILE." 22
			fi
			get_image_set=1
			get_image="$2"
			shift 2;;
		--)
			shift
			if [ "$#" -gt 0 ]; then
				content_set=1
				content="$*"
			fi
			break;;
		-*) error_echo "Unexpected option: $1" 22; exit 22;;
		*) content_set=1; content="$*"; break;;
	esac
done

if [ "$get_image_set" -eq 1 ]; then
	if [ "$clipboard_action" = "get" ]; then
		error_echo "--get-image cannot be combined with --get." 22
		exit 22
	fi
	if [ "$content_set" -eq 1 ]; then
		error_echo "--get-image does not accept CONTENT." 22
	fi
	get_clipboard_image
	exit
fi

if [ "$clipboard_action" = "get" ]; then
	if [ "$content_set" -eq 1 ]; then
		error_echo "--get does not accept CONTENT." 22
		exit 22
	fi
	get_clipboard
	exit
fi
if [ "$content_set" -eq 1 ]; then
	set_clipboard "$content"
elif [[ -p /dev/stdin ]]; then
	winps_exec_stdin "\$ErrorActionPreference='Stop'; [Console]::InputEncoding=[Text.Encoding]::UTF8; Set-Clipboard -Value ([Console]::In.ReadToEnd())"
else
	set_clipboard ""
fi
