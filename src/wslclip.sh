# shellcheck shell=bash
content=""
clipboard_action="set"
content_set=0

help_short="wslclip [OPTIONS] [CONTENT ...]"
help_details='Get or set the Windows clipboard from WSL without X or Wayland.

Arguments:
  CONTENT         Text to place on the Windows clipboard. All remaining
                  command-line words are joined as the content.
  standard input  When CONTENT is omitted and input is piped, copy that input.
  no input        When neither CONTENT nor piped input is present, clear the clipboard.

Options:
  -g, --get       Print the clipboard; cannot be combined with CONTENT.
  --              End option parsing; use before CONTENT that starts with a dash.
  -h, --help      Show this help.
  -v, --version   Show the wslu version.

Examples:
  wslclip "copied text"
  printf %s "copied text" | wslclip
  wslclip --get'

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

while [ "$#" -gt 0 ]; do
	case "$1" in
		-h|--help) help "$0" "$help_short"; exit;;
		-v|--version) version; exit;;
		-g|--get) clipboard_action="get"; shift;;
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
