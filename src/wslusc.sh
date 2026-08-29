# shellcheck shell=bash
cname=""
cname_args=()
iconpath=""
is_gui=0
is_interactive=0
customname=""
customenv=""
shortcut_debug=""
non_debug_option=0
interactive_arguments=0
native_requested=0
WSLUSC_GUITYPE=${WSLUSC_GUITYPE:-"legacy"}
WSLUSC_SMART_ICON_DETECTION=${WSLUSC_SMART_ICON_DETECTION:-"false"}
base_converter_engine=${WSLUSC_BASE_CONVERTER_ENGINE:-"imagemagick"}

help_short="wslusc [OPTIONS] COMMAND [ARGUMENTS ...]\nwslusc -d SHORTCUT_FILE\nwslusc [-hv]"
help_details='Create a Windows Desktop shortcut that launches a WSL command.

Arguments:
  COMMAND        Linux executable name or path stored in the shortcut.
  ARGUMENTS      Arguments passed to COMMAND when the shortcut is opened.
  SHORTCUT_FILE  Name of an existing .lnk file on the Windows Desktop to inspect.
  ENV            Shell fragment run before COMMAND, for example "export GDK_SCALE=2;".
  NAME           Shortcut filename without the .lnk suffix; default: command name.
  FILE           Linux path to an ico, png, svg, or xpm icon.

Options:
  -d, --shortcut-debug SHORTCUT_FILE
      Print the Windows shortcut object for an existing Desktop shortcut.
      This mode cannot be combined with shortcut-creation options or COMMAND.
  -I, --interactive       Prompt for command, name, GUI mode, environment, and icon.
  -e, --env ENV           Run the ENV shell fragment before COMMAND.
  -n, --name NAME         Set the shortcut name.
  -i, --icon FILE         Copy and convert FILE for the shortcut icon.
  -g, --gui               Hide the terminal and launch as a GUI application.
  -N, --native            With -g, launch through wslg.exe instead of wscript.exe.
  -s, --smart-icon        Find an icon with wslpy; requires Python and wslpy.
  -h, --help              Show this help.
  -v, --version           Show the wslu version.

Configuration defaults:
  WSLUSC_GUITYPE=legacy                 Accepted values: legacy, native.
  WSLUSC_SMART_ICON_DETECTION=false     Set true to enable wslpy detection.
  WSLUSC_BASE_CONVERTER_ENGINE=imagemagick
                                          Accepted values: imagemagick, ffmpeg.

Native GUI mode requires -g, wslg.exe, and Windows build 21332 or newer. The
selected converter must be installed for non-ico icon input.

Examples:
  wslusc top
  wslusc -n Editor -i ./editor.png code .
  wslusc -g -N xeyes
  wslusc -e "export GDK_SCALE=2;" -g xterm'

PARSED_ARGUMENTS=$(getopt -n "${wslu_util_name##*/}" -o +hvd:Ie:n:i:gNs --long help,version,shortcut-debug:,interactive,env:,name:,icon:,gui,native,smart-icon -- "$@")
#shellcheck disable=SC2181
if [ "$?" != "0" ]; then
	help "$wslu_util_name" "$help_short"
	exit 22
fi

function sc_debug {
	debug_echo "sc_debug: called with $*"
	dp="$(double_dash_p "$(wslvar -l Desktop)")"
	winps_exec "\$s=(New-Object -COM WScript.Shell).CreateShortcut($(winps_string "$dp\\$*")); \$s;"
}

debug_echo "Parsed: $PARSED_ARGUMENTS"
eval set -- "$PARSED_ARGUMENTS"
while :
do
	case "$1" in
		-d|--shortcut-debug)
			if [ -n "$shortcut_debug" ] || [ -z "$2" ] || [[ "$2" == -* ]]; then
				error_echo "$1 requires one non-option SHORTCUT_FILE." 22
				exit 22
			fi
			shortcut_debug="$2"
			shift 2;;
		-I|--interactive) non_debug_option=1; is_interactive=1; shift;;
		-i|--icon)
			if [ -z "$2" ] || [[ "$2" == -* ]]; then
				error_echo "$1 requires FILE." 22
				exit 22
			fi
			non_debug_option=1; iconpath="$2"; shift 2;;
		-s|--smart-icon) non_debug_option=1; WSLUSC_SMART_ICON_DETECTION="true"; shift;;
		-n|--name)
			if [ -z "$2" ] || [[ "$2" == -* ]]; then
				error_echo "$1 requires NAME." 22
				exit 22
			fi
			non_debug_option=1; customname="$2"; shift 2;;
		-e|--env)
			if [ -z "$2" ] || [[ "$2" == -* ]]; then
				error_echo "$1 requires ENV." 22
				exit 22
			fi
			non_debug_option=1; customenv="$2"; shift 2;;
		-g|--gui) non_debug_option=1; is_gui=1; shift;;
		-N|--native) non_debug_option=1; native_requested=1; WSLUSC_GUITYPE="native"; shift;;
		-h|--help) help "$0" "$help_short"; exit;;
		-v|--version) version; exit;;
		--)
			shift
			if [ "$#" -gt 0 ]; then
				non_debug_option=1
				cname_header="$1"
				shift
				cname_args=("$@")
				cname="${cname_args[*]}"
			fi
			break;;
		*) error_echo "Unexpected option: $1" 22; exit 22;;
	esac
done

if [ -n "$shortcut_debug" ]; then
	if [ "$non_debug_option" -eq 1 ]; then
		error_echo "--shortcut-debug cannot be combined with other options or commands." 22
		exit 22
	fi
	sc_debug "$shortcut_debug"
	exit
fi

case "$WSLUSC_GUITYPE" in
	legacy|native) ;;
	*) error_echo "Unsupported WSLUSC_GUITYPE: $WSLUSC_GUITYPE" 22; exit 22;;
esac

case "$base_converter_engine" in
	imagemagick|ffmpeg) ;;
	*) error_echo "Unsupported WSLUSC_BASE_CONVERTER_ENGINE: $base_converter_engine" 22; exit 22;;
esac

if [ "$native_requested" -eq 1 ] && [ "$is_gui" -eq 0 ]; then
	error_echo "--native must be combined with --gui." 22
	exit 22
fi
debug_echo "cname_header: $cname_header cname: $cname"
# interactive mode
if [[ $is_interactive -eq 1 ]]; then
	echo "${info} Welcome to wslu shortcut creator interactive mode."
	read -r -e -i "$cname_header" -p "${input_info} Command (Without Parameter): " input
	cname_header="${input:-$cname_header}"
	read -r -e -i "$cname" -p "${input_info} Command param: " input
	cname="${input:-$cname}"
	interactive_arguments=1
	read -r -e -i "$customname" -p "${input_info} Shortcut name [optional, ENTER for default]: " input
	customname="${input:-$customname}"
	read -r -e -i "$is_gui" -p "${input_info} Is it a GUI application? [if yes, input 1; if no, input 0]: " input
	is_gui=$(( ${input:-$is_gui} + 0 ))
	read -r -e -i "$customenv" -p "${input_info} Pre-executed command [optional, ENTER for default]: " input
	customenv="${input:-$customenv}"
	read -r -e -i "$iconpath" -p "${input_info} Custom icon Linux path (support ico/png/xpm/svg) [optional, ENTER for default]: " input
	iconpath="${input:-$iconpath}"
fi

# supported gui check
windows_build=$(wslu_get_build)
if ! [[ "$windows_build" =~ ^[0-9]{1,9}$ ]]; then
	error_echo "Unable to determine the Windows build number." 35
	exit 35
fi
if [[ "$is_gui" -eq 1 && "$WSLUSC_GUITYPE" == "native" ]] && [ "$windows_build" -lt 21332 ]; then
	error_echo "Native GUI shortcuts require Windows build 21332 or newer. Aborted." 35
	exit 35
fi

if [[ "$cname_header" != "" ]]; then
	up_path="$(wslvar -s USERPROFILE)"
	tpath=$(double_dash_p "$(wslvar -s TMP)") # Windows Temp, Win Double Sty.
	tpath="${tpath:-$(double_dash_p "$(wslvar -s TEMP)")}" # sometimes TMP is not set for some reason
	dpath=$(wslpath "$(wslvar -l Desktop)") # Windows Desktop, WSL Sty.
	script_location="$(wslpath "$up_path")/wslu" # Windows wslu, Linux WSL Sty.
	script_location_win="$(double_dash_p "$up_path")\\wslu" #  Windows wslu, Win Double Sty.
	distro_location_win="$(double_dash_p "$(cat "${wslu_state_dir}"/baseexec)")" # Distro Location, Win Double Sty.

	# change param according to the exec.
	distro_param="run"

	if [[ "$distro_location_win" == *wsl\.exe* ]]; then
		if [ "$windows_build" -ge "$BN_MAY_NINETEEN" ]; then
			distro_param="-d \"$WSL_DISTRO_NAME\" -e"
		else
			distro_param="-e"
		fi
	fi
 
	# handling the execuable part, a.k.a., cname_header
	# always absolute path
	tmp_cname_header="$(readlink -f "$cname_header")"
	if [ ! -f "$tmp_cname_header" ]; then
		cname_header="$(command -v "$cname_header")"
	else
		cname_header="$tmp_cname_header"
	fi
	unset tmp_cname_header

	[ -z "$cname_header" ] && error_echo "Bad or invalid input; Aborting" 30

	# handling no name given case
	new_cname="${cname_header##*/}"
	# handling name given case
	if [[ "$customname" != "" ]]; then
		new_cname=$customname
	fi

	if [ "$interactive_arguments" -eq 1 ]; then
		printf -v shortcut_command '%q' "$cname_header"
		[ -z "$cname" ] || shortcut_command="$shortcut_command $cname"
	else
		printf -v shortcut_command '%q ' "$cname_header" "${cname_args[@]}"
		shortcut_command="${shortcut_command% }"
	fi
	shortcut_command="${customenv:+$customenv }$shortcut_command"
	shortcut_payload=$(printf %s "$shortcut_command" | base64 | tr -d '\n')
	encoded_shell_command="eval \"\$(printf %s '$shortcut_payload' | base64 -d)\""
	windows_shell_command="${encoded_shell_command//\"/\\\"}"

	if [[ "$WSLUSC_SMART_ICON_DETECTION" == "true" ]]; then
		if wslpy_check; then
			tmp_fcname="${cname_header##*/}"
			iconpath="$(python3 -c 'import sys, wslpy.__internal__; print(wslpy.__internal__.find_icon(sys.argv[1]))' "$tmp_fcname")"
			echo "${info} Icon Detector found icon $tmp_fcname at: $iconpath"
		else
			echo "${warn} Icon Detector cannot find icon."
		fi
	fi

	if [ -n "$iconpath" ]; then
		ext="${iconpath##*.}"
		ext="${ext,,}"
		case "$ext" in
			ico|png|svg|xpm) ;;
			*) error_echo "Unsupported icon extension: .$ext" 22; exit 22;;
		esac
		if [ -f "$iconpath" ] && [ "$ext" != "ico" ]; then
			case "$base_converter_engine" in
				ffmpeg)
					command -v ffmpeg >/dev/null || { error_echo "ffmpeg is required to convert non-ico icons." 22; exit 22; }
					if [ "$ext" = "svg" ] && ! ffmpeg -v error -i "$iconpath" -f null - >/dev/null 2>&1; then
						error_echo "This ffmpeg build cannot decode the SVG icon." 22
						exit 22
					fi;;
				imagemagick)
					command -v convert >/dev/null || { error_echo "ImageMagick convert is required to convert non-ico icons." 22; exit 22; };;
			esac
		fi
	fi

	# Check default icon and runHidden.vbs
	wslu_file_check "$script_location" "wsl.ico"
	wslu_file_check "$script_location" "wsl-term.ico"
	wslu_file_check "$script_location" "wsl-gui.ico"
	wslu_file_check "$script_location" "runHidden.vbs" "?!R"

	# handling icon
	if [[ "$iconpath" != "" ]] || [[ "$WSLUSC_SMART_ICON_DETECTION" == "true" ]]; then

		# normal detection section
		icon_filename="${iconpath##*/}"
		ext="${iconpath##*.}"
		ext="${ext,,}"

		if [[ ! -f $iconpath ]]; then
			iconpath="$(double_dash_p "$up_path")\\wslu\\wsl.ico"
			echo "${warn} Icon not found. Reset to default icon..."
		else
			echo "${info} You choose to use custom icon: $iconpath. Processing..."
			icon_was_copied=0
			icon_destination="$script_location/$icon_filename"
			if [ "$(readlink -f "$iconpath")" != "$(readlink -f "$icon_destination")" ]; then
				if ! cp "$iconpath" "$script_location"; then
					error_echo "Failed to copy icon into $script_location." 1
					exit 1
				fi
				icon_was_copied=1
			fi
		
			if [[ "$ext" != "ico" ]]; then
				if [[ "${base_converter_engine}" = "ffmpeg" ]]; then
					if [[ "$ext" == "svg" ]]; then
						echo "${info} Converting $ext icon to ico..."
						echo "${warn} ffmpeg is not designed for converting svg to ico, the result may not be satisfactory."
						if ! ffmpeg -hide_banner -loglevel panic -i "$script_location/$icon_filename" -vf scale=256:256 "$script_location/${icon_filename%."$ext"}.ico"; then
							error_echo "Failed to convert SVG icon with ffmpeg." 22
							exit 22
						fi
						[ "$icon_was_copied" -eq 0 ] || rm "$script_location/$icon_filename"
						icon_filename="${icon_filename%."$ext"}.ico"
					elif [[ "$ext" == "png" ]] || [[ "$ext" == "xpm" ]]; then
						echo "${info} Converting $ext icon to ico..."
						if ! ffmpeg -hide_banner -loglevel panic -i "$script_location/$icon_filename" -vf scale=256:256 "$script_location/${icon_filename%."$ext"}.ico"; then
							error_echo "Failed to convert icon with ffmpeg." 22
							exit 22
						fi
						[ "$icon_was_copied" -eq 0 ] || rm "$script_location/$icon_filename"
						icon_filename="${icon_filename%."$ext"}.ico"
					else
						error_echo "wslusc only support creating shortcut using .png/.svg/.ico icon with ffmpeg engine. Aborted." 22
					fi
				else
					if [[ "$ext" == "svg" ]]; then
						echo "${info} Converting $ext icon to ico..."
						if ! convert "$script_location/$icon_filename" -trim -background none -resize 256X256 -define 'icon:auto-resize=16,24,32,64,128,256' "$script_location/${icon_filename%."$ext"}.ico"; then
							error_echo "Failed to convert SVG icon with ImageMagick." 22
							exit 22
						fi
						[ "$icon_was_copied" -eq 0 ] || rm "$script_location/$icon_filename"
						icon_filename="${icon_filename%."$ext"}.ico"
					elif [[ "$ext" == "png" ]] || [[ "$ext" == "xpm" ]]; then
						echo "${info} Converting $ext icon to ico..."
						if ! convert "$script_location/$icon_filename" -resize 256X256 "$script_location/${icon_filename%."$ext"}.ico"; then
							error_echo "Failed to convert icon with ImageMagick." 22
							exit 22
						fi
						[ "$icon_was_copied" -eq 0 ] || rm "$script_location/$icon_filename"
						icon_filename="${icon_filename%."$ext"}.ico"
					else
						error_echo "wslusc only support creating shortcut using .png/.svg/.xpm/.ico icon with imagemagick engine. Aborted." 22
					fi
				fi
			fi
			iconpath="$script_location_win\\$icon_filename"
		fi
	else
		if [[ "$is_gui" == "1" ]]; then
			iconpath="$(double_dash_p "$up_path")\\wslu\\wsl-gui.ico"
		else
			iconpath="$(double_dash_p "$up_path")\\wslu\\wsl-term.ico"
		fi
	fi
	
	# handling custom vairable command
	if [[ "$customenv" != "" ]]; then
		echo "${info} the following custom variable/command will be applied: $customenv"
	fi

	if [[ "$is_gui" == "1" ]]; then
		if [[ "$WSLUSC_GUITYPE" == "legacy" ]]; then
			if ! winps_exec "\$ErrorActionPreference='Stop'; \$s=(New-Object -COM WScript.Shell).CreateShortcut($(winps_string "$tpath\\$new_cname.lnk")); \$s.TargetPath=$(winps_string 'C:\Windows\System32\wscript.exe'); \$s.Arguments=$(winps_string "\"$script_location_win\\runHidden.vbs\" \"$distro_location_win\" $distro_param \"/usr/share/wslu/wslusc-helper.sh\" \"$windows_shell_command\""); \$s.IconLocation=$(winps_string "$iconpath"); \$s.Save();"; then
				error_echo "Failed to create Windows shortcut." 1
				exit 1
			fi
		elif [[ "$WSLUSC_GUITYPE" == "native" ]]; then
			if ! winps_exec "\$ErrorActionPreference='Stop'; \$s=(New-Object -COM WScript.Shell).CreateShortcut($(winps_string "$tpath\\$new_cname.lnk")); \$s.TargetPath=$(winps_string 'C:\Windows\System32\wslg.exe'); \$s.Arguments=$(winps_string "~ -d \"$WSL_DISTRO_NAME\" bash -l -c \"$windows_shell_command\""); \$s.IconLocation=$(winps_string "$iconpath"); \$s.Save();"; then
				error_echo "Failed to create native Windows shortcut." 1
				exit 1
			fi
		else
			error_echo "bad GUI type, aborting" 22
		fi
	else
		if ! winps_exec "\$ErrorActionPreference='Stop'; \$s=(New-Object -COM WScript.Shell).CreateShortcut($(winps_string "$tpath\\$new_cname.lnk")); \$s.TargetPath=$(winps_string "$distro_location_win"); \$s.Arguments=$(winps_string "$distro_param bash -l -c \"$windows_shell_command\""); \$s.IconLocation=$(winps_string "$iconpath"); \$s.Save();"; then
			error_echo "Failed to create Windows shortcut." 1
			exit 1
		fi
	fi
	tpath="$(wslpath "$tpath")/$new_cname.lnk"
	if ! mv "$tpath" "$dpath"; then
		error_echo "Failed to move shortcut to the Windows Desktop." 1
		exit 1
	fi
	echo "${info} Create shortcut ${new_cname}.lnk successful"
else
	error_echo "No input, aborting" 21
fi
