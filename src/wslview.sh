# shellcheck shell=bash
link_args=()
reveal_path=""
reveal_mode=0
skip_validation_check=${WSLVIEW_SKIP_VALIDATION_CHECK:-1}
WSLVIEW_DEFAULT_ENGINE=${WSLVIEW_DEFAULT_ENGINE:-powershell}
browser_action=""
launch_option=0
link_argument_set=0

help_short="wslview [OPTIONS] LINK_OR_FILE [LINK_OR_FILE ...]\nwslview --reveal PATH\nwslview ACTION\nwslview [-hv]"
help_details='Open a URL, file, or folder with a Windows application from WSL.

Arguments:
  LINK_OR_FILE  One or more of: an http(s) URL, a URL without a scheme, a
                file: URL, a Windows path such as C:/Users/Public, or an
                existing Linux path. Every argument is opened separately;
                Linux paths are converted to Windows paths first.
  ENGINE        Windows launcher to use:
                  powershell    Windows Shell association through PowerShell (default).
                  cmd           Compatibility alias for the PowerShell shell launcher.
                  cmd_explorer  explorer.exe invoked directly.
  PATH          For --reveal: an existing Linux path or a Windows path whose
                file is highlighted in its Windows Explorer folder.
  ACTION        Exactly one of --reg-as-browser, --unreg-as-browser, or
                --export-as-browser. Actions do not accept LINK_OR_FILE or launch options.

Options:
  -E, --engine ENGINE          Select one of the launchers described above.
  -s, --skip-validation-check Skip the curl HTTP HEAD request used to validate URLs.
  --reveal PATH               Highlight PATH in its Windows Explorer folder
                              instead of opening it.
  -r, --reg-as-browser        Register wslview with update-alternatives; uses sudo.
  -u, --unreg-as-browser      Remove that update-alternatives registration; uses sudo.
  -e, --export-as-browser     Append BROWSER=/usr/bin/wslview to existing shell
                              profiles and comment out existing BROWSER exports.
  -h, --help                  Show this help.
  -v, --version               Show the wslu version.

Configuration defaults:
  WSLVIEW_DEFAULT_ENGINE=powershell
  WSLVIEW_SKIP_VALIDATION_CHECK=1   Validate URLs; set to 0 to skip validation.

URL validation uses curl to send an HTTP HEAD request. A failed probe does not
rewrite the input as a filesystem path; the original URL is still opened. Opening
Linux paths or Linux file: URLs requires Windows build 1903 or newer.

Browser registration is unsupported on Arch Linux and Alpine Linux. The export
method may edit .bashrc, .zshrc, and .kshrc in the home directory.

Examples:
  wslview https://example.com
  wslview /mnt/c/Users/Public
  wslview report1.pdf report2.pdf
  wslview --reveal /mnt/c/Users/Public/report.pdf
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
			while [ "$#" -gt 0 ]; do
				link_args+=("$1")
				shift
			done
			if [ "${#link_args[@]}" -gt 0 ]; then
				link_argument_set=1
			fi;;
		--reveal)
			if [ -z "${2:-}" ] || [[ "$2" == -* ]]; then
				error_echo "$1 requires PATH." 22
				exit 22
			fi
			reveal_path="$2"
			reveal_mode=1
			launch_option=1
			shift 2;;
		-*) error_echo "Unexpected option: $1" 22; exit 22;;
		*)
			link_args+=("$1")
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

if [ "$link_argument_set" -eq 1 ]; then
	for entry in "${link_args[@]}"; do
		[ -n "$entry" ] || error_echo "LINK_OR_FILE cannot be empty." 22
	done
fi
if [ "$reveal_mode" -eq 1 ] && [ "$link_argument_set" -eq 1 ]; then
	error_echo "--reveal cannot be combined with LINK_OR_FILE." 22
	exit 22
fi
debug_echo "link_args: ${link_args[*]}"
debug_echo "WSLVIEW_DEFAULT_ENGINE: $WSLVIEW_DEFAULT_ENGINE"

if [ "$reveal_mode" -eq 1 ]; then
	# --reveal: highlight the file in its Windows Explorer folder instead of opening it.
	resolved="$(readlink -f "$reveal_path")"
	if [ -n "$resolved" ] && [ -e "$resolved" ]; then
		require_linux_path_build "$(wslu_get_build)"
		reveal_target="$(wslpath -w "$resolved")"
	elif [[ "$reveal_path" =~ ^[A-Za-z]\:.*$ ]]; then
		reveal_target="$reveal_path"
	else
		error_echo "--reveal requires an existing Linux path or a Windows path." 22
	fi
	debug_echo "reveal_target: $reveal_target"
	winps_exec "\$ErrorActionPreference='Stop'; & explorer.exe ($(winps_string "/select,$reveal_target"))"
	exit $?
fi

if [ "$link_argument_set" -eq 0 ]; then
	error_echo "No input, aborting" 21
fi

launch_status=0
for lname in "${link_args[@]}"; do
	properfile_full_path=""
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
	target=""
	if [ -n "$properfile_full_path" ]; then
		debug_echo "It is a Linux path"
		target="$(wslpath -w "$properfile_full_path")"
	elif [[ "$lname" =~ ^file:\/\/(\/)+[A-Za-z]\:.*$ ]] || [[ "$lname" =~ ^[A-Za-z]\:.*$ ]]; then
		debug_echo "Received Windows absolute path or Windows file URL"
		target="$lname"
	else
		debug_echo "Treating input as a URL"
		if [ "$skip_validation_check" -ne 0 ] && ! url_validator "$lname"; then
			debug_echo "URL validation failed; preserving the original URL"
		fi
		target="$lname"
	fi
	debug_echo "target: $target"
	if [[ "$WSLVIEW_DEFAULT_ENGINE" == "powershell" || "$WSLVIEW_DEFAULT_ENGINE" == "cmd" ]]; then
		winps_exec "\$ErrorActionPreference='Stop'; \$shell=New-Object -ComObject Shell.Application; \$shell.ShellExecute($(winps_string "$target"))"
	elif [[ "$WSLVIEW_DEFAULT_ENGINE" == "cmd_explorer" ]]; then
		winps_exec "\$ErrorActionPreference='Stop'; & explorer.exe ($(winps_string "$target"))"
	fi
	rc=$?
	if [ "$rc" -ne 0 ] && [ "$launch_status" -eq 0 ]; then
		launch_status=$rc
	fi
done
exit "$launch_status"
