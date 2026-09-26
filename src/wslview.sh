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

help_short="wslview [OPTIONS] LINK_OR_FILE [LINK_OR_FILE ...]\nwslview --reveal PATH\nwslview --on TARGET [OPTIONS] LINK_OR_FILE ...\nwslview --on TARGET --stop\nwslview ACTION\nwslview [-hv]"
help_details='Open a URL, file, or folder with a Windows application from WSL.

Arguments:
  LINK_OR_FILE  One or more of: an http(s) URL, a URL without a scheme, a
                file: URL, a Windows path such as C:/Users/Public, or an
                existing Linux path. Every argument is opened separately;
                Linux paths are converted to Windows paths first (without --on).
  ENGINE        Windows launcher to use:
                  powershell    Windows Shell association through PowerShell (default).
                  cmd           Compatibility alias for the PowerShell shell launcher.
                  cmd_explorer  explorer.exe invoked directly.
  PATH          For --reveal: an existing Linux path or a Windows path whose
                file is highlighted in its Windows Explorer folder.
  ACTION        Exactly one of --reg-as-browser, --unreg-as-browser, or
                --export-as-browser. Actions do not accept --on, LINK_OR_FILE, or
                launch options.
  TARGET        For --on: any ssh destination, typically an alias from
                ~/.ssh/config whose login lands in the target WSL instance.

Options:
  -E, --engine ENGINE          Select one of the launchers described above.
  -s, --skip-validation-check Accepted for compatibility and does nothing; wslview
                              no longer probes a URL before opening it.
  --reveal PATH               Highlight PATH in its Windows Explorer folder
                              instead of opening it.
  --on TARGET                  Open on another machine (the target): files are copied
                               there and opened with their application, directories
                               open in a web file browser on the target. TARGET goes to
                               ssh verbatim, e.g. an ssh config alias.
  --stop                       With --on TARGET: close the tunnels, stop the file
                               server, and clear the registrations.
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
  WSLVIEW_ON_PORT=8090          Loopback port of the file server. The tunnel to a
                                target forwards one hundred above the configured
                                value; both fall forward when a port is taken.
  WSLVIEW_ON_INBOX_TTL=7        Days a copied file may stay in the target inbox

wslview opens a URL exactly as given, without probing it first. Earlier versions sent an
HTTP HEAD request to decide whether a value was a URL or a filesystem path; that decision
comes from the argument itself, so the probe could not change the outcome and only cost
time. Opening Linux paths or Linux file: URLs requires Windows build 1903 or newer.

With --on, paths are resolved in this distro (a Windows path refers to the Windows
filesystem here) and never sent as paths to the target: a directory becomes a browser
URL served through an ssh reverse tunnel, a single file is copied to an inbox on the
target and opened in its associated application there. Opening a directory on the
target needs copyparty on PATH in this distro and wslview on
the target. Files previewed inside the browser open in the browser, not in a Windows
application. Any directory works: it is registered with the file server for as
long as the server runs; --stop clears the registrations and the server state.
Directories opened as arguments are shared read-write (upload yes, move and
delete no); a directory shown by --reveal is shared read-only. URLs work only
while the file server runs, and anything shared this way is browsable and
writable from the browser on the target.

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
  wslview --engine cmd_explorer C:/Windows
  wslview --on laptop ~/notes
  wslview --on laptop --stop'

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


# Opening on a target (--on TARGET).
#
# A target is another machine reached over ssh between the WSL instances; its
# Windows desktop is where things open. Nothing is attached anywhere: directories
# and reveal become deep links into a loopback-bound file server (copyparty)
# reached through an ssh reverse tunnel, while single files are copied to an
# inbox on the target and opened there with their associated application.

on_target=""
on_stop=0
engine_option_set=0
WSLVIEW_ON_PORT=${WSLVIEW_ON_PORT:-8090}
WSLVIEW_ON_INBOX_TTL=${WSLVIEW_ON_INBOX_TTL:-7}
wslview_on_sources_file="${wslu_state_dir}/wslview-on-sources"
wslview_on_server_args="${wslu_state_dir}/wslview-on-server.args"
wslview_on_server_port_file="${wslu_state_dir}/wslview-on-server.port"
wslview_on_url_port=""
wslview_on_tunnel_offset=100
wslview_on_port_window=5
wslview_on_server_pid_file="${wslu_state_dir}/wslview-on-server.pid"

# Classify one LINK_OR_FILE argument, shared by the local and the --on paths.
# Sets wslview_input_kind to linux, windows, or url, and wslview_input_path to
# the resolved Linux path (empty when unresolvable), the Windows path or
# Windows file: URL exactly as given, or the argument unchanged.
function wslview_classify_input() {
	local lname="$1"
	wslview_input_kind=url
	wslview_input_path="$lname"
	if [[ "$lname" =~ ^file:\/\/.*$ ]] && [[ ! "$lname" =~ ^file:\/\/(\/)+[A-Za-z]\:.*$ ]]; then
		lname="$(fileprotocoldecode "$lname")"
		wslview_input_kind=linux
		wslview_input_path="$(readlink -f "${lname//file:\/\//}")"
	elif [[ "$lname" =~ ^(/[^/]+)*(/)?$ ]]; then
		wslview_input_kind=linux
		wslview_input_path="$(readlink -f "$lname")"
	elif [ -e "$(readlink -f "$lname")" ]; then
		wslview_input_kind=linux
		wslview_input_path="$(readlink -f "$lname")"
	elif [[ "$lname" =~ ^file:\/\/(\/)+[A-Za-z]\:.*$ ]] || [[ "$lname" =~ ^[A-Za-z]\:.*$ ]]; then
		wslview_input_kind=windows
	fi
}

# True for arguments shaped like a path but matched by no path branch.
function wslview_input_pathlike() {
	[[ "$1" == */* ]] && [[ ! "$1" =~ ^[A-Za-z][A-Za-z0-9+.-]*: ]]
}

# Control socket id for a target; the hash keeps distinct targets apart.
function wslview_on_target_id() {
	local safe hash
	safe="$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')"
	hash="$(printf '%s' "$1" | cksum)"
	printf '%s-%s' "$safe" "${hash%% *}"
}

# Quote one argument for the target's POSIX shell.
function wslview_on_quote() {
	local s
	s=${1//\'/\'\\\'\'}
	printf "'%s'" "$s"
}

# Percent-encode a path for the file server URL; / and safe bytes stay as-is.
function wslview_on_encode() {
	local LC_ALL=C in="$1" out="" c i
	for (( i = 0; i < ${#in}; i++ )); do
		c="${in:i:1}"
		case "$c" in
			[A-Za-z0-9.~_-]) out+="$c";;
			/) out+="/";;
			*) printf -v c '%%%02X' "'$c"; out+="$c";;
		esac
	done
	printf '%s' "$out"
}

# Browser URL for an absolute directory, registering it with the file server on
# first use. $2 is rw for an opened directory and r for a --reveal parent; a
# directory inside an exposed one reuses that source, upgraded to rw on request.
function wslview_on_source_for() {
	local path="$1" want="$2" best="" bestname="" bestperm="" rel base candidate i tmp
	local sname spath sperm
	local -a taken=()
	: >> "$wslview_on_sources_file"
	while IFS=$'\t' read -r sname spath sperm; do
		[ -n "$sname" ] || continue
		taken+=("$sname")
		if [ "$path" == "$spath" ] || [[ "$path" == "$spath"/* ]]; then
			if [ ${#spath} -gt ${#best} ]; then
				best="$spath"
				bestname="$sname"
				bestperm="$sperm"
			fi
		fi
	done < "$wslview_on_sources_file"
	if [ -z "$best" ]; then
		base="$(basename "$path")"
		base="${base//[^A-Za-z0-9._-]/-}"
		candidate="$base"
		i=2
		while [[ " ${taken[*]} " == *" $candidate "* ]]; do
			candidate="$base-$i"
			i=$((i + 1))
		done
		printf '%s\t%s\t%s\n' "$candidate" "$path" "$want" >> "$wslview_on_sources_file"
		printf '%s/' "$candidate"
		return 0
	fi
	if [ "$want" == "rw" ] && [ "$bestperm" != "rw" ]; then
		tmp="$wslview_on_sources_file.tmp"
		while IFS=$'\t' read -r sname spath sperm; do
			[ "$sname" == "$bestname" ] && sperm=rw
			printf '%s\t%s\t%s\n' "$sname" "$spath" "$sperm"
		done < "$wslview_on_sources_file" > "$tmp"
		mv "$tmp" "$wslview_on_sources_file"
	fi
	rel="${path#"$best"}"
	rel="${rel#/}"
	if [ -n "$rel" ]; then
		printf '%s/%s' "$bestname" "$(wslview_on_encode "$rel")"
	else
		printf '%s/' "$bestname"
	fi
}


function wslview_on_server_running() {
	local pid=""
	[ -f "$wslview_on_server_pid_file" ] || return 1
	pid=$(<"$wslview_on_server_pid_file")
	[[ "$pid" =~ ^[0-9]+$ ]] || return 1
	wslu_pid_check "$pid" copyparty
}

function wslview_on_server_stop() {
	local pid=""
	if wslview_on_server_running; then
		pid=$(<"$wslview_on_server_pid_file")
		kill "$pid" 2>/dev/null || true
	fi
	rm -f "$wslview_on_server_pid_file"
}

# Remove every piece of file server state; nothing outlives --stop or a server.
function wslview_on_state_clear() {
	rm -f "$wslview_on_sources_file" "$wslview_on_server_args" "$wslview_on_server_pid_file" \
		"$wslview_on_server_port_file"
}

# Close every tunnel; their forwards die with the server they point at.
function wslview_on_tunnels_stop() {
	local sock port_file
	for sock in "$wslu_state_dir"/wslview-on-*.sock; do
		[ -e "$sock" ] || continue
		wslu_tunnel_close "$sock"
	done
	# a master that died on its own leaves its port file behind
	for port_file in "$wslu_state_dir"/wslview-on-*.port; do
		[ "$port_file" == "$wslview_on_server_port_file" ] && continue
		rm -f "$port_file"
	done
}

# The local port of the running server, or the default before it starts.
function wslview_on_server_port() {
	local p="" pid=""
	[ -f "$wslview_on_server_port_file" ] && p=$(<"$wslview_on_server_port_file")
	if ! [[ "$p" =~ ^[0-9]+$ ]]; then
		# recover a lost port file from the server cmdline, which carries -p PORT
		[ -f "$wslview_on_server_pid_file" ] && pid=$(<"$wslview_on_server_pid_file")
		if wslu_pid_check "$pid" copyparty; then
			p=$(tr '\0' '\n' < "/proc/$pid/cmdline" | awk '/^-p$/ { getline; print; exit }')
		fi
	fi
	[[ "$p" =~ ^[0-9]+$ ]] || p="$WSLVIEW_ON_PORT"
	printf '%s' "$p"
}

# Start the loopback-bound file server unless it runs with the same volumes.
# The port falls forward when taken: a target tunnel may already hold it.
function wslview_on_server_ensure() {
	local pid i port old_port sname spath sperm
	local -a vol_args=()
	command -v copyparty >/dev/null 2>&1 || error_echo "Browsing on a target needs copyparty on PATH; install copyparty or open a single file instead." 34
	while IFS=$'\t' read -r sname spath sperm; do
		[ -n "$sname" ] || continue
		vol_args+=(-v "$spath:/$sname:${sperm:-rw}")
	done < "$wslview_on_sources_file"
	[ ${#vol_args[@]} -gt 0 ] || error_echo "No directory registered for browsing yet." 22
	if wslview_on_server_running && cmp -s "$wslview_on_sources_file" "$wslview_on_server_args"; then
		return 0
	fi
	old_port="$(wslview_on_server_port)"
	wslview_on_server_stop
	# --http-only skips the TLS sniff, which 400s and corrupts the stream when the
	# request arrives fragmented (normal through an ssh tunnel).
	for (( port = WSLVIEW_ON_PORT; port < WSLVIEW_ON_PORT + wslview_on_port_window; port++ )); do
		copyparty -i 127.0.0.1 --http-only -p "$port" "${vol_args[@]}" >/dev/null 2>&1 &
		pid=$!
		printf '%s\n' "$pid" > "$wslview_on_server_pid_file"
		disown 2>/dev/null || true
		for (( i = 0; i < 75; i++ )); do
			if timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then
				break
			fi
			kill -0 "$pid" 2>/dev/null || break
			sleep 0.2
		done
		# the probe can connect to a foreign listener before copyparty binds (or
		# fails to); settle, then trust only our own process
		sleep 0.3
		if wslu_pid_check "$pid" copyparty; then
			cp "$wslview_on_sources_file" "$wslview_on_server_args"
			printf '%s\n' "$port" > "$wslview_on_server_port_file"
			if [ "$old_port" != "$port" ]; then
				wslview_on_tunnels_stop
			fi
			debug_echo "wslview_on_server_ensure: serving on port $port"
			return 0
		fi
	done
	wslview_on_server_stop
	error_echo "The file server could not start; check the copyparty installation. Ports $WSLVIEW_ON_PORT..$((WSLVIEW_ON_PORT + wslview_on_port_window - 1)) may also all be taken." 1
}

function wslview_on_tunnel_ensure() {
	local sock="$1" port_file="${1%.sock}.port" remote local_port try err
	local_port="$(wslview_on_server_port)"
	# reuse only a tunnel whose recorded port can be trusted
	if [ -f "$port_file" ] && ssh -S "$sock" -O check "$on_target" >/dev/null 2>&1; then
		wslview_on_url_port=$(<"$port_file")
		if [[ "$wslview_on_url_port" =~ ^[0-9]+$ ]]; then
			debug_echo "wslview_on_tunnel_ensure: reusing tunnel to $on_target on port $wslview_on_url_port"
			return 0
		fi
	fi
	# no trustworthy port: close whatever is there and build fresh
	wslu_tunnel_close "$sock"
	# the remote port starts one hundred above the configured port so the two
	# roles never share a number (a mutual setup would be ambiguous otherwise),
	# then falls forward when taken on the target
	for (( try = 0; try < wslview_on_port_window; try++ )); do
		remote=$((WSLVIEW_ON_PORT + wslview_on_tunnel_offset + try))
		if err="$(ssh -fN -M -S "$sock" -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
			-o ConnectTimeout=10 -R "$remote:localhost:$local_port" "$on_target" 2>&1)"; then
			printf '%s\n' "$remote" > "$port_file"
			wslview_on_url_port="$remote"
			debug_echo "wslview_on_tunnel_ensure: tunnel to $on_target forwards $remote to localhost:$local_port"
			return 0
		fi
		rm -f "$sock"
		case "$err" in
			*"forwarding failed"*) ;; # that port is taken on the target; try the next
			*) error_echo "Could not open a tunnel to $on_target. ${err:-ssh failed}." 1;;
		esac
	done
	error_echo "Could not open a tunnel to $on_target. Ports $((WSLVIEW_ON_PORT + wslview_on_tunnel_offset))..$((WSLVIEW_ON_PORT + wslview_on_tunnel_offset + wslview_on_port_window - 1)) are all taken on the target; run ssh $on_target to diagnose." 1
}

# Deepest common directory of the given absolute paths.
function wslview_on_common_dir() {
	local common f
	common="$(dirname "$1")"
	shift
	for f in "$@"; do
		while [ "$common" != "/" ] && [ "$f" != "$common" ] && [[ "$f" != "$common"/* ]]; do
			common="$(dirname "$common")"
		done
	done
	printf '%s' "$common"
}

function wslview_on_run() {
	local sock
	sock="${wslu_state_dir}/wslview-on-$(wslview_on_target_id "$on_target").sock"
	local lname properfile entry f rel common runid remote_cmd rc wpath idx
	local -a remote_args=() file_args=() rel_args=() pipe_status=() dir_parts=()
	local need_browser=0 need_copy=0

	[[ "$WSLVIEW_ON_PORT" =~ ^[0-9]+$ ]] || error_echo "WSLVIEW_ON_PORT must be a number." 22
	[[ "$WSLVIEW_ON_INBOX_TTL" =~ ^[0-9]+$ ]] || error_echo "WSLVIEW_ON_INBOX_TTL must be a number of days." 22
	if ! wslview_on_server_running; then
		wslview_on_state_clear
		wslview_on_tunnels_stop
	fi

	if [ "$on_stop" -eq 1 ]; then
		wslview_on_tunnels_stop
		wslview_on_server_stop
		wslview_on_state_clear
		debug_echo "wslview_on_run: tunnels, file server, and state cleared"
		exit 0
	fi

	if [ "$reveal_mode" -eq 1 ]; then
		wslview_classify_input "$reveal_path"
		if [ "$wslview_input_kind" == "linux" ] && [ -n "$wslview_input_path" ]; then
			properfile="$wslview_input_path"
		elif [[ "$reveal_path" =~ ^[A-Za-z]\:.*$ ]]; then
			properfile="$(wslpath -u "$reveal_path" 2>/dev/null)"
		fi
		if [ -z "$properfile" ] || [ ! -e "$properfile" ]; then
			error_echo "--reveal requires an existing Linux path or a Windows path." 22
		fi
		# the parent is shared read-only: reveal only points at it
		dir_parts+=("$(wslview_on_source_for "$(dirname "$properfile")" r)")
		need_browser=1
	else
		[ "$link_argument_set" -eq 1 ] || error_echo "wslview --on TARGET needs LINK_OR_FILE, --reveal PATH, or --stop." 21
		for lname in "${link_args[@]}"; do
			wslview_classify_input "$lname"
			properfile=""
			case "$wslview_input_kind" in
				linux)
					if [ -z "$wslview_input_path" ] || [ ! -e "$wslview_input_path" ]; then
						error_echo "No such file or directory: $lname" 22
					fi
					properfile="$wslview_input_path";;
				windows)
					wpath="${wslview_input_path#file://}"
					wpath="${wpath#/}"
					properfile="$(wslpath -u "$wpath" 2>/dev/null)"
					if [ -z "$properfile" ] || [ ! -e "$properfile" ]; then
						error_echo "No such file or directory: $lname" 22
					fi;;
				url)
					wslview_input_pathlike "$lname" && error_echo "No such file or directory: $lname" 22;;
			esac
			if [ -n "$properfile" ]; then
				if [ -d "$properfile" ]; then
					dir_parts+=("$(wslview_on_source_for "$properfile" rw)")
					need_browser=1
				else
					file_args+=("$properfile")
					need_copy=1
				fi
			else
				remote_args+=("$(wslview_on_quote "$lname")")
			fi
		done
	fi

	if [ "$need_browser" -eq 1 ]; then
		wslview_on_server_ensure
		wslview_on_tunnel_ensure "$sock"
	fi

	for idx in "${!dir_parts[@]}"; do
		remote_args+=("$(wslview_on_quote "http://localhost:$wslview_on_url_port/${dir_parts[$idx]}")")
	done

	if [ "$need_copy" -eq 1 ]; then
		runid="$(date +%Y-%m-%d_%H%M%S)-$$"
		common="$(wslview_on_common_dir "${file_args[@]}")"
		for f in "${file_args[@]}"; do
			rel_args+=("${f#"$common"/}")
		done
		# shellcheck disable=SC2029 # the target shell expands ~ and $? on its side
		tar -chf - -C "$common" "${rel_args[@]}" | ssh -o ConnectTimeout=10 "$on_target" \
			"mkdir -p ~/.cache/wslu/inbox/$runid && tar -xf - -C ~/.cache/wslu/inbox/$runid; rc=\$?; find ~/.cache/wslu/inbox -mindepth 1 -maxdepth 1 -mtime +$WSLVIEW_ON_INBOX_TTL -exec rm -rf {} + 2>/dev/null; exit \$rc"
		pipe_status=("${PIPESTATUS[@]}")
		if [ "${pipe_status[0]}" -ne 0 ] || [ "${pipe_status[1]}" -ne 0 ]; then
			error_echo "Failed to copy files to $on_target. Check ssh access and free space on the target." 1
		fi
		for rel in "${rel_args[@]}"; do
			# shellcheck disable=SC2088 # the target shell expands the tilde; only the
			# relative part is single-quoted, after it.
			remote_args+=("~/.cache/wslu/inbox/$runid/$(wslview_on_quote "$rel")")
		done
	fi

	remote_cmd="command -v wslview >/dev/null 2>&1 || { echo 'wslview is not installed on the target.' >&2; exit 127; }; exec wslview"
	if [ "$engine_option_set" -eq 1 ]; then
		remote_cmd+=" --engine $WSLVIEW_DEFAULT_ENGINE"
	fi
	for entry in "${remote_args[@]}"; do
		remote_cmd+=" $entry"
	done
	debug_echo "wslview_on_run: ssh $on_target $remote_cmd"
	# shellcheck disable=SC2029 # every argument is quoted by wslview_on_quote
	ssh -o ConnectTimeout=10 "$on_target" "$remote_cmd"
	rc=$?
	exit "$rc"
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
			engine_option_set=1
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
		--on)
			if [ -z "${2:-}" ] || [[ "$2" == -* ]]; then
				error_echo "$1 requires TARGET." 22
				exit 22
			fi
			if [ -n "$on_target" ]; then
				error_echo "Only one --on TARGET is allowed." 22
				exit 22
			fi
			on_target="$2"
			shift 2;;
		--stop) on_stop=1; shift;;
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
	if [ "$launch_option" -eq 1 ] || [ "$link_argument_set" -eq 1 ] || [ -n "$on_target" ]; then
		error_echo "ACTION cannot be combined with --on, launch options, or LINK_OR_FILE." 22
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

if [ "$on_stop" -eq 1 ] && [ -z "$on_target" ]; then
	error_echo "--stop requires --on TARGET." 22
	exit 22
fi
if [ "$on_stop" -eq 1 ] && { [ "$link_argument_set" -eq 1 ] || [ "$reveal_mode" -eq 1 ] || [ "$launch_option" -eq 1 ]; }; then
	error_echo "--stop cannot be combined with LINK_OR_FILE, --reveal, or launch options." 22
	exit 22
fi
if [ -n "$on_target" ]; then
	wslview_on_run
fi

if [ "$reveal_mode" -eq 1 ]; then
	# --reveal: highlight the file in its Windows Explorer folder instead of opening it.
	wslview_classify_input "$reveal_path"
	if [ "$wslview_input_kind" == "linux" ] && [ -n "$wslview_input_path" ] && [ -e "$wslview_input_path" ]; then
		require_linux_path_build "$(wslu_get_build)"
		reveal_target="$(wslpath -w "$wslview_input_path")"
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
	wslview_classify_input "$lname"
	target=""
	if [ "$wslview_input_kind" == "linux" ] && [ -n "$wslview_input_path" ]; then
		require_linux_path_build "$(wslu_get_build)"
		target="$(wslpath -w "$wslview_input_path")"
	else
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
