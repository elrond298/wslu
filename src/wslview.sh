# shellcheck shell=bash
lname=""
skip_validation_check=${WSLVIEW_SKIP_VALIDATION_CHECK:-1}
WSLVIEW_DEFAULT_ENGINE=${WSLVIEW_DEFAULT_ENGINE:-powershell}
browser_action=""
launch_option=0
link_argument_set=0

help_short="wslview [OPTIONS] LINK_OR_FILE\nwslview ACTION\nwslview [-hv]"
help_details='Open a URL, file, or folder with a Windows application from WSL.

Arguments:
  LINK_OR_FILE  An http(s) URL, a URL without a scheme, a file: URL, a Windows
                path such as C:/Users/Public, or an existing Linux path. Linux
                paths are converted to Windows paths before opening.
  ENGINE        Windows launcher to use:
                  powershell    PowerShell Start command (default).
                  cmd           Compatibility alias for PowerShell Start.
                  cmd_explorer  explorer.exe invoked directly.
  ACTION        Exactly one of --reg-as-browser, --unreg-as-browser, or
                --export-as-browser. Actions do not accept LINK_OR_FILE or launch options.

Options:
  -E, --engine ENGINE          Select one of the launchers described above.
  -s, --skip-validation-check Skip the curl HTTP HEAD request used to validate URLs.
  -r, --reg-as-browser        Register wslview with update-alternatives; uses sudo.
  -u, --unreg-as-browser      Remove that update-alternatives registration; uses sudo.
  -e, --export-as-browser     Append BROWSER=/usr/bin/wslview to existing shell
                              profiles and comment out existing BROWSER exports.
  -h, --help                  Show this help.
  -v, --version               Show the wslu version.

Configuration defaults:
  WSLVIEW_DEFAULT_ENGINE=powershell
  WSLVIEW_SKIP_VALIDATION_CHECK=1   Validate URLs; set to 0 to skip validation.

URL validation requires curl and sends an HTTP HEAD request. Opening Linux paths or
Linux file: URLs requires Windows build 1903 or newer.

Browser registration is unsupported on Arch Linux and Alpine Linux. The export
method may edit .bashrc, .zshrc, and .kshrc in the home directory.

Examples:
  wslview https://example.com
  wslview /mnt/c/Users/Public
  wslview --engine cmd_explorer C:/Windows'

function fileprotocoldecode() { : "${*//+/ }"; echo -e "${_//%/\\x}"; }

function del_reg_alt {
	if [ "$distro" == "archlinux" ] || [ "$distro" == "alpine" ]; then
		error_echo "Unsupported action for this distro. Aborted." 34
		exit 34
	else
		status=0
		sudo update-alternatives --remove x-www-browser "$(readlink -f "$0")" || status=1
		sudo update-alternatives --remove www-browser "$(readlink -f "$0")" || status=1
		exit "$status"
	fi
}

function alternative_registered {
	local output
	output=$(update-alternatives --query "$1" 2>/dev/null) || return 1
	grep -Fxq "Alternative: $2" <<< "$output"
}

function add_reg_alt {
	if [ "$distro" == "archlinux" ] || [ "$distro" == "alpine" ]; then
		error_echo "Unsupported action for this distro. Aborted." 34
	else
		alternative_path=$(readlink -f "$0")
		added_x=0
		if ! alternative_registered x-www-browser "$alternative_path"; then
			sudo update-alternatives --install "$wslu_prefix/bin/x-www-browser" x-www-browser "$alternative_path" 1 || exit 1
			added_x=1
		fi
		if ! alternative_registered www-browser "$alternative_path"; then
			if ! sudo update-alternatives --install "$wslu_prefix/bin/www-browser" www-browser "$alternative_path" 1; then
				[ "$added_x" -eq 0 ] || sudo update-alternatives --remove x-www-browser "$alternative_path" >/dev/null 2>&1 || true
				exit 1
			fi
		fi
		exit 0
	fi
}

function add_browser_export {
	local browser_export='export BROWSER="/usr/bin/wslview"'
	local rc_file

	for rc_file in .bashrc .zshrc .kshrc; do
		[ -f "$HOME/$rc_file" ] || continue
		echo "Processing $rc_file..."

		if ! sed -i \
			-e '\|^export BROWSER="/usr/bin/wslview"$|d' \
			-e '/^[[:space:]]*export BROWSER=/s/^/#/' \
			"$HOME/$rc_file"; then
			error_echo "Failed to update $HOME/$rc_file." 1
			return 1
		fi
		if ! echo "$browser_export" >> "$HOME/$rc_file"; then
			error_echo "Failed to write $HOME/$rc_file." 1
			return 1
		fi
		echo "Configured BROWSER in $rc_file."
	done
}

function url_validator {
	curl --head --silent --fail -g -- "$1" >/dev/null
}

function require_linux_path_build {
	if ! [[ "$1" =~ ^[0-9]{1,9}$ ]]; then
		error_echo "Unable to determine the Windows build number." 34
	fi
	[ "$1" -ge "$BN_MAY_NINETEEN" ] || error_echo "Linux paths require Windows build 1903 or newer." 34
}


while [ "$#" -gt 0 ]; do
	case "$1" in
		-s|--skip-validation-check) launch_option=1; skip_validation_check=0; shift;;
		-r|--reg-as-browser)
			[ -z "$browser_action" ] || { error_echo "Only one ACTION is allowed." 22; exit 22; }
			browser_action="register"; shift;;
		-u|--unreg-as-browser)
			[ -z "$browser_action" ] || { error_echo "Only one ACTION is allowed." 22; exit 22; }
			browser_action="unregister"; shift;;
		-e|--export-as-browser)
			[ -z "$browser_action" ] || { error_echo "Only one ACTION is allowed." 22; exit 22; }
			browser_action="export"; shift;;
		-h|--help) help "$0" "$help_short"; exit;;
		-v|--version) version; exit;;
		-E|--engine)
			if [ -z "${2:-}" ] || [[ "$2" == -* ]]; then
				error_echo "$1 requires ENGINE." 22
				exit 22
			fi
			case "$2" in
				powershell|cmd|cmd_explorer) WSLVIEW_DEFAULT_ENGINE="$2";;
				*) error_echo "Unsupported engine: $2" 22; exit 22;;
			esac
			launch_option=1
			shift 2;;
		--)
			shift
			[ "$#" -eq 1 ] || { error_echo "Expected exactly one LINK_OR_FILE." 22; exit 22; }
			lname="$1"
			link_argument_set=1
			shift;;
		-*) error_echo "Unexpected option: $1" 22; exit 22;;
		*)
			[ "$#" -eq 1 ] || { error_echo "Expected exactly one LINK_OR_FILE." 22; exit 22; }
			lname="$1"
			link_argument_set=1
			shift;;
	esac
done

case "$skip_validation_check" in
	0|1) ;;
	*) error_echo "WSLVIEW_SKIP_VALIDATION_CHECK must be 0 or 1." 22; exit 22;;
esac

case "$WSLVIEW_DEFAULT_ENGINE" in
	powershell|cmd|cmd_explorer) ;;
	*) error_echo "Unsupported engine: $WSLVIEW_DEFAULT_ENGINE" 22; exit 22;;
esac

if [ -n "$browser_action" ]; then
	if [ "$launch_option" -eq 1 ] || [ "$link_argument_set" -eq 1 ]; then
		error_echo "ACTION cannot be combined with launch options or LINK_OR_FILE." 22
		exit 22
	fi
	case "$browser_action" in
		register) add_reg_alt;;
		unregister) del_reg_alt;;
		export) add_browser_export; exit;;
	esac
fi

if [ "$link_argument_set" -eq 1 ] && [ -z "$lname" ]; then
	error_echo "LINK_OR_FILE cannot be empty." 22
	exit 22
fi
debug_echo "lname: $lname"
debug_echo "WSLVIEW_DEFAULT_ENGINE: $WSLVIEW_DEFAULT_ENGINE"

if [[ "$lname" != "" ]]; then
	# file:/// protocol used in linux
	if [[ "$lname" =~ ^file:\/\/.*$ ]] && [[ ! "$lname" =~ ^file:\/\/(\/)+[A-Za-z]\:.*$ ]]; then
		debug_echo "Received file:/// protocol used in linux"
		# convert before set
		lname="$(fileprotocoldecode "$lname")"
		require_linux_path_build "$(wslu_get_build)"
		properfile_full_path="$(readlink -f "${lname//file:\/\//}")"
	# Linux absolute path
	elif [[ "$lname" =~ ^(/[^/]+)*(/)?$ ]]; then
		debug_echo "Received linux absolute path"
		require_linux_path_build "$(wslu_get_build)"
		properfile_full_path="$(readlink -f "${lname}")"
	# Linux relative path
	elif [[ -d "$(readlink -f "$lname")" ]] || [[ -f "$(readlink -f "$lname")" ]]; then
		debug_echo "Received linux relative path"
		require_linux_path_build "$(wslu_get_build)"
		properfile_full_path="$(readlink -f "${lname}")"
	fi
	debug_echo "properfile_full_path: $properfile_full_path"
	if [ "$skip_validation_check" -eq 0 ]; then
		debug_echo "Skipping validation check"
		is_valid_url=0
  	else
   		debug_echo "Validating whether if it is a link"
		if url_validator "$lname"; then
			is_valid_url=0
		else
			is_valid_url=1
		fi
	fi
	if [[ "$is_valid_url" -eq 0 ]] && [ -z "$properfile_full_path" ]; then
		debug_echo "It is a link"
		target="$lname"
	elif [[ "$lname" =~ ^file:\/\/(\/)+[A-Za-z]\:.*$ ]] || [[ "$lname" =~ ^[A-Za-z]\:.*$ ]]; then
		debug_echo "It is not a link; received windows absolute path/file protocol windows absolute path"
		target="$lname"
	else
		debug_echo "It is not a link"
		target="$(wslpath -w "${properfile_full_path:-$lname}" 2>/dev/null || echo "$lname")"
	fi
	debug_echo "target: $target"
	if [[ "$WSLVIEW_DEFAULT_ENGINE" == "powershell" ]]; then
		winps_exec "Start ($(winps_string "$target"))"
	elif [[ "$WSLVIEW_DEFAULT_ENGINE" == "cmd" ]]; then
		winps_exec "Start ($(winps_string "$target"))"
	elif [[ "$WSLVIEW_DEFAULT_ENGINE" == "cmd_explorer" ]]; then
		winps_exec "& explorer.exe ($(winps_string "$target"))"
	fi
else
	error_echo "No input, aborting" 21
fi
