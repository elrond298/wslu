# shellcheck shell=bash
##########   CAUTION   ###########
## wslupath is a legacy cli for backward compatbility.
## Use it unless it is necessary.

style=1
reg_path=0
set_path=""

help_short="wslupath [-dO] PATH\nwslupath -r [-dO] SHELL_FOLDER\nwslupath [-dO] LOCATION\nwslupath [-h|-v|-R]"
help_details='Convert between Windows and WSL path forms. This command is deprecated;
use wslpath for ordinary path conversion.

Arguments:
  PATH          A Windows path such as C:\Windows or a mounted WSL path such
                as /mnt/c/Windows. Output defaults to the opposite path form.
  SHELL_FOLDER  Windows shell-folder registry name, such as Desktop or Startup.
                Use --avail-reg to list names accepted on this Windows account.
  LOCATION      One of the known-location options below.

Output style:
  -O, --original          Print input unchanged; known locations stay Windows-style.
  -d, --doubledash-dir   Double backslashes without converting the path form.
  -r, --reg-data         Interpret SHELL_FOLDER as a shell-folder registry name.

Known locations:
  -D, --desktop           Windows Desktop folder.
  -A, --appdata           Windows roaming AppData folder.
  -T, --temp              Windows temporary folder.
  -S, --sysdir            Windows System32 folder.
  -W, --windir            Windows installation folder.
  -s, --start-menu        Windows Start Menu folder.
  -su, --startup          Windows Startup folder.
  -H, --home              Windows user home folder.
  -P, --program-files     Windows Program Files folder.

Options:
  -R, --avail-reg         List shell-folder names accepted by -r.
  -h, --help              Show this help.
  -v, --version           Show the wslu version.

Place an output-style option before a known-location option.

Examples:
  wslupath "C:\Windows"
  wslupath /mnt/c/Windows
  wslupath -d -D
  wslupath -r Desktop'

function path_double_dash {
	new_path="${*//\\/\\\\}"
	echo "$new_path"
}

function general_converter {
	target="$*"

	if [[ $target =~ ^[A-Z]:(\\[^:\\]+)*(\\)?$ ]]; then
		p=$(wslpath -u "${target}")
	elif [[ $target =~ ^$(interop_prefix)[A-Za-z](/[^/]+)*(/)?$ ]]; then
		p=$(wslpath -w "${target}")
	else
		echo "${error} No proper path form detected: ""$*""."
		exit 20
	fi
	echo "$p"
}

function style_path {
	case $style in
		1) p="$(general_converter "$@")";;
		2) p="$*";;
		3) p="$(path_double_dash "$@")";;
	esac
	echo "$p"
}

if [[ $# -eq 0 ]]; then
	echo -e "$help_short"
	exit 20
else
	for args; do
		case $args in
			#styles
			-r|--reg-data) reg_path=1;;
			-O|--original) style=2;;
			-d|--doubledash-dir) style=3;;
			## system location

			-D|--desktop)
			set_path="$(style_path "$(wslvar -l 'Desktop')")"
			break;;
			-A|--appdata)
			set_path="$(style_path "$(wslvar -s APPDATA)")"
			break;;
			-T|--temp)
			set_path="$(style_path "$(wslvar -s TMP)")"
			break;;
			-S|--sysdir)
			set_path="$(style_path "$(wslvar -s windir)"\\System32)"
			break;;
			-W|--windir)
			set_path="$(style_path "$(wslvar -s windir)")"
			break;;
			-s|--start-menu)
			set_path="$(style_path "$(wslvar -l 'Start Menu')")"
			break;;
			-su|--startup)
			set_path="$(style_path "$(wslvar -l 'Startup')")"
			break;;
			-H|--home)
			set_path="$(style_path "$(wslvar HOMEDRIVE)""$(wslvar HOMEPATH)")"
			break;;
			-P|--program-files)
			set_path="$(style_path "$(wslvar -s ProgramFiles)")"
			break;;
			-h|--help) help "$0" "$help_short"; exit;;
			-v|--version) version; exit;;
			-R|--avail-reg) echo "Available registery input:"
			wslvar -L
			exit;;
			*)
			if [[ "$reg_path" == "1" ]]; then
				set_path="$(style_path "$(wslvar -l "$args")")"
			else
				set_path="$(style_path "$args")"
			fi
			break;;
		esac
	done
fi

if [[ "$set_path" == "" ]]; then
	echo "${error}No path input. Aborted."
	exit 21
else
	echo "$set_path"
fi
