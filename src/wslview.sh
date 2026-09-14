# shellcheck shell=bash
link_args=()
reveal_path=""
reveal_mode=0
# Kept only so that an existing WSLVIEW_SKIP_VALIDATION_CHECK value is still accepted
# and still validated; the probe it used to control is gone.
skip_validation_check=${WSLVIEW_SKIP_VALIDATION_CHECK:-1}
WSLVIEW_DEFAULT_ENGINE=${WSLVIEW_DEFAULT_ENGINE:-powershell}
WSLVIEW_USE_HELPER=${WSLVIEW_USE_HELPER:-true}
helper_action=open
wslview_helper_script="${wslu_dest_dir}${wslu_prefix}/share/wslu/wslview-helper.ps1"
wslview_helper_port_file="${wslu_state_dir}/wslview-helper.port"
wslview_helper_token_file="${wslu_state_dir}/wslview-helper.token"
wslview_helper_stamp_file="${wslu_state_dir}/wslview-helper.attempt"
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
  -s, --skip-validation-check Accepted for compatibility and does nothing; wslview
                              no longer probes a URL before opening it.
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
  WSLVIEW_SKIP_VALIDATION_CHECK=1   Accepted for compatibility and ignored.
  WSLVIEW_USE_HELPER=true            Launch through the resident helper when WSL can
                                     reach the Windows loopback; set to false to always
                                     launch powershell.exe directly.

wslview opens a URL exactly as given, without probing it first. Earlier versions sent an
HTTP HEAD request to decide whether a value was a URL or a filesystem path; that decision
comes from the argument itself, so the probe could not change the outcome and only cost
time. Opening Linux paths or Linux file: URLs requires Windows build 1903 or newer.

wslview keeps a helper process alive on the Windows side so that a launch costs one
loopback socket round trip instead of a PowerShell startup. The helper is only
reachable in WSL mirrored networking mode; otherwise, and whenever it is not running,
wslview starts one for the next call and launches the slow way for this one.

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

# Launching through the resident helper.
#
# wslview-helper.ps1 keeps a powershell.exe and its Shell.Application COM object
# alive, so a launch costs one loopback socket round trip instead of ~200ms of
# PowerShell startup plus ~40ms of COM construction. wslview talks to it through
# bash's /dev/tcp. The port file can outlive the helper (idle timeout, crash,
# killed process), and in WSL mirrored networking a connect to a dead loopback
# port never fails, it hangs, so the whole exchange runs under timeout; any
# failure retires the port file so the next call starts a fresh helper.
#
# Returns 0 when the helper ran the action, 1 when it ran it and the launcher
# failed, and 2 when the helper could not be reached - the caller then starts
# one for the next call and launches the slow way for this one.
function wslview_helper_request() {
	local action="$1" payload="$2" port token reply

	[ "$WSLVIEW_USE_HELPER" == "true" ] || return 2
	[ -f "$wslview_helper_port_file" ] || return 2
	[ -f "$wslview_helper_token_file" ] || return 2

	port=$(<"$wslview_helper_port_file")
	token=$(<"$wslview_helper_token_file")
	[[ "$port" =~ ^[0-9]+$ ]] || return 2
	[ -n "$token" ] || return 2

	# shellcheck disable=SC2016 # the child script uses positional args, no expansion wanted
	reply=$(timeout 6 bash -c '
		exec 3<>/dev/tcp/127.0.0.1/"$1" || exit 2
		printf "%s\t%s\t%s\n" "$2" "$3" "$4" >&3
		IFS= read -r -t 5 line <&3 || exit 3
		printf "%s" "$line"
	' wslview-helper "$port" "$token" "$action" "$payload" 2>/dev/null) || {
		rm -f "$wslview_helper_port_file"
		debug_echo "wslview_helper_request: $action -> helper unreachable, port file retired"
		return 2
	}
	reply="${reply%$'\r'}" # tolerate a CRLF reply from an older helper
	debug_echo "wslview_helper_request: $action -> ${reply:-no reply}"

	case "$reply" in
		OK) return 0 ;;
		FAIL) return 1 ;;
	esac
	return 2
}

# Start the helper in the background.
#
# Deliberately does not wait for it: this call falls back to the slow path and
# the next one finds the helper already listening, so the helper never adds
# latency to a launch. The helper binds its own ephemeral port and publishes it,
# so wslview never connects to a port it does not own.
function wslview_helper_autostart() {
	local token port_win last now

	[ "$WSLVIEW_USE_HELPER" == "true" ] || return 0
	[ -f "$wslview_helper_script" ] || return 0
	[ -x "$(windows_system32)/WindowsPowerShell/v1.0/powershell.exe" ] || return 0

	# Rate limit. In WSL NAT networking mode the helper can never be reached, and
	# without this every call would start another one and leave it to idle out.
	now="$(date +%s)"
	last=""
	[ -f "$wslview_helper_stamp_file" ] && last=$(<"$wslview_helper_stamp_file")
	if [[ "$last" =~ ^[0-9]+$ ]] && [ $(( now - last )) -lt 60 ]; then
		debug_echo "wslview_helper_autostart: rate limited"
		return 0
	fi
	printf '%s\n' "$now" > "$wslview_helper_stamp_file"

	if [ ! -s "$wslview_helper_token_file" ]; then
		(umask 077; head -c 24 /dev/urandom | base64 > "$wslview_helper_token_file")
	fi
	token=$(<"$wslview_helper_token_file")
	[ -n "$token" ] || return 0

	# The helper publishes its port here, so deleting it first makes "the file
	# exists" mean "a helper bound successfully and can be reached".
	rm -f "$wslview_helper_port_file"
	port_win="$(wslpath -w "$wslview_helper_port_file")" || return 0
	script_win="$(wslpath -w "$wslview_helper_script")" || return 0

	"$(windows_system32)/WindowsPowerShell/v1.0/powershell.exe" \
		-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden \
		-File "$script_win" -PortFile "$port_win" -Token "$token" >/dev/null 2>&1 &
	disown 2>/dev/null || true
	debug_echo "wslview_helper_autostart: helper starting"
	return 0
}


while [ "$#" -gt 0 ]; do
	case "$1" in
		-s|--skip-validation-check) launch_option=1; shift;;
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
	wslview_helper_request reveal "$reveal_target"
	rc=$?
	if [ "$rc" -eq 2 ]; then
		wslview_helper_autostart
		# Same focus nudge as the main path: see the comment in the launch loop.
		winps_exec "(New-Object -ComObject WScript.Shell).SendKeys('{F16}'); \$ErrorActionPreference='Stop'; & explorer.exe ($(winps_string "/select,$reveal_target"))"
		rc=$?
	fi
	exit "$rc"
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
		target="$lname"
	fi
	debug_echo "target: $target"
	case "$WSLVIEW_DEFAULT_ENGINE" in
		powershell|cmd) helper_action=open ;;
		cmd_explorer) helper_action=explorer ;;
	esac

	wslview_helper_request "$helper_action" "$target"
	rc=$?
	if [ "$rc" -eq 2 ]; then
		# No helper yet: start one for the next call, then launch the slow way.
		wslview_helper_autostart
		# The slow way runs in a background powershell, which has no foreground
		# right: without a synthetic key tap first (F16, bound by nothing), the
		# opened window only flashes in the taskbar. The resident helper does the
		# same nudge in-process (ForegroundNudge).
		if [[ "$WSLVIEW_DEFAULT_ENGINE" == "powershell" || "$WSLVIEW_DEFAULT_ENGINE" == "cmd" ]]; then
			winps_exec "(New-Object -ComObject WScript.Shell).SendKeys('{F16}'); \$ErrorActionPreference='Stop'; \$shell=New-Object -ComObject Shell.Application; \$shell.ShellExecute($(winps_string "$target"))"
		elif [[ "$WSLVIEW_DEFAULT_ENGINE" == "cmd_explorer" ]]; then
			winps_exec "(New-Object -ComObject WScript.Shell).SendKeys('{F16}'); \$ErrorActionPreference='Stop'; & explorer.exe ($(winps_string "$target"))"
		fi
		rc=$?
	fi
	if [ "$rc" -ne 0 ] && [ "$launch_status" -eq 0 ]; then
		launch_status=$rc
	fi
done
exit "$launch_status"
