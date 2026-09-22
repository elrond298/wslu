# shellcheck shell=bash
help_short="wslsvc COMMAND ..."
help_details='Inspect and control Windows services (the Service Control Manager side,
not Linux services managed by wslgsu).

Commands:
  list [SUBSTRING] [--state=STATE]
      List Windows services as NAME, STATE, DISPLAY NAME columns. SUBSTRING
      filters both name fields case-insensitively. Valid states: Stopped,
      StartPending, StopPending, Running, ContinuePending, PausePending,
      Paused.
  status SERVICE
      Show state, start type, PID, binary path, run-as account, and
      description. Exits 0 when active (Running or Paused), 3 when inactive,
      4 when the service is unknown.
  start SERVICE
  stop SERVICE
  restart SERVICE
      Change the service state. restart is stop followed by start even when
      the service is already stopped. Being already in the desired state is
      a no-op with exit 0.

SERVICE is an exact service name or display name, case-insensitive, one per
invocation. An ambiguous match lists candidates and asks you to pick one;
without an interactive stdin that exits 22. Exact matches run unattended.

A denied action exits 1; rerun from an elevated shell. wslsvc never
triggers UAC prompts.

Options:
  -h, --help      Show this help.
  -v, --version   Show the wslu version.

Examples:
  wslsvc list spool
  wslsvc list --state=Running
  wslsvc status Spooler
  wslsvc restart "Print Spooler"'

readonly -a WSLU_SVC_STATES=(Stopped StartPending StopPending Running ContinuePending PausePending Paused)

svc_rows=""

function svc_fetch {
	svc_rows=$(winps_exec "Get-Service | ForEach-Object { \$_.Name + [char]9 + \$_.Status + [char]9 + \$_.DisplayName }") || return 1
	svc_rows=${svc_rows//$'\r'/}
	[ -n "$svc_rows" ]
}

function svc_state_valid {
	local s
	for s in "${WSLU_SVC_STATES[@]}"; do
		[ "${s,,}" = "${1,,}" ] && return 0
	done
	return 1
}

# svc_resolve ACTION TARGET: set res_name/res_state/res_display from an exact
# service name or display name match (case-insensitive). Returns 2 with no
# match; on ambiguous input it prompts on a terminal (stdin and the prompt go
# to stderr) and reads the pick and ACTION confirmation from stdin.
function svc_resolve {
	local action="$1" target="$2" name state display pick answer i idx=0
	local lt="${target,,}"
	local -a c_name=() c_state=() c_display=()
	while IFS=$'\t' read -r name state display; do
		[ -n "$name" ] || continue
		if [ "${name,,}" = "$lt" ] || [ "${display,,}" = "$lt" ]; then
			c_name+=("$name")
			c_state+=("$state")
			c_display+=("$display")
		fi
	done <<< "$svc_rows"

	if [ "${#c_name[@]}" -eq 0 ]; then
		return 2
	fi

	if [ "${#c_name[@]}" -gt 1 ]; then
		{
			echo "Multiple services match '$target':"
			for i in "${!c_name[@]}"; do
				printf '  %d) %s (%s)\n' "$((i + 1))" "${c_display[$i]}" "${c_name[$i]}"
			done
		} >&2
		if [ ! -t 0 ]; then
			error_echo "Non-interactive stdin; '$target' is an ambiguous match. Pick one by its unique service name." 22
		fi
		printf 'Select a service [1-%d]: ' "${#c_name[@]}" >&2
		if ! read -r pick; then
			error_echo "Non-interactive stdin; '$target' is an ambiguous match." 22
		fi
		if ! [[ "$pick" =~ ^[0-9]+$ ]] || [ "$pick" -lt 1 ] || [ "$pick" -gt "${#c_name[@]}" ]; then
			error_echo "Invalid selection: '$pick'." 22
		fi
		idx=$((pick - 1))
		printf "Confirm %s '%s' (%s)? [y/N] " "$action" "${c_display[$idx]}" "${c_name[$idx]}" >&2
		if ! read -r answer; then
			error_echo "Non-interactive stdin; confirmation required." 22
		fi
		case "${answer,,}" in
			y|yes) ;;
			*) echo "${warn} Aborted." >&2; exit 1;;
		esac
	fi
	res_name="${c_name[$idx]}"
	res_state="${c_state[$idx]}"
	res_display="${c_display[$idx]}"
}

function svc_list {
	local help_short="wslsvc list [SUBSTRING] [--state=STATE] [-h]"
	local help_details='List Windows services as NAME, STATE, DISPLAY NAME columns.

Arguments:
  SUBSTRING   Case-insensitive substring matched against service name and
              display name. Omit to list every service.

Options:
  --state=STATE  Only show services whose state equals STATE exactly,
                 case-insensitive. Valid states: Stopped, StartPending,
                 StopPending, Running, ContinuePending, PausePending,
                 Paused. Composable with SUBSTRING.
  -h, --help     Show this help.

Examples:
  wslsvc list spool
  wslsvc list --state=Running
  wslsvc list spool --state=Stopped'
	local filter="" statef="" name state display

	while [ "$#" -gt 0 ]; do
		case "$1" in
			-h|--help) help "wslsvc" "$help_short"; exit;;
			--state)
				if [ -z "${2:-}" ] || [[ "${2:-}" == -* ]]; then
					error_echo "$1 requires STATE." 22
				fi
				statef="$2"
				shift;;
			--state=*)
				statef="${1#--state=}"
				[ -n "$statef" ] || error_echo "--state requires STATE." 22;;
			--*|-*)
				error_echo "Unexpected option: $1" 22;;
			*)
				[ -n "$1" ] || error_echo "SUBSTRING must not be empty." 22
				[ -z "$filter" ] || error_echo "Unexpected argument: $1" 22
				filter="$1";;
		esac
		shift
	done

	if [ -n "$statef" ] && ! svc_state_valid "$statef"; then
		error_echo "Invalid --state value: '$statef'. Valid states are: ${WSLU_SVC_STATES[*]}." 22
	fi

	if ! svc_fetch; then
		error_echo "Failed to query Windows services." 1
	fi

	local fl="${filter,,}" sf="${statef,,}"
	printf '%-30s  %-13s  %s\n' "NAME" "STATE" "DISPLAY NAME"
	while IFS=$'\t' read -r name state display; do
		[ -n "$name" ] || continue
		if [ -n "$fl" ] && [[ "${name,,}" != *"$fl"* && "${display,,}" != *"$fl"* ]]; then
			continue
		fi
		if [ -n "$sf" ] && [ "${state,,}" != "$sf" ]; then
			continue
		fi
		printf '%-30s  %-13s  %s\n' "$name" "$state" "$display"
	done <<< "$svc_rows"
}

# svc_parse_target "$@": require exactly one non-empty SERVICE operand.
svc_target=""
function svc_parse_target {
	local count=0
	while [ "$#" -gt 0 ]; do
		case "$1" in
			-h|--help) help "wslsvc" "$help_short"; exit;;
			--*|-*) error_echo "Unexpected option: $1" 22;;
			*)
				[ "$count" -eq 0 ] || error_echo "Unexpected argument: $1" 22
				[ -n "$1" ] || error_echo "SERVICE must not be empty." 22
				svc_target="$1"
				count=1;;
		esac
		shift
	done
	[ "$count" -eq 1 ] || error_echo "SERVICE is required." 21
}

function svc_status {
	local help_short="wslsvc status SERVICE [-h]"
	local help_details='Show one Windows service: display name and name, state, start type, PID,
binary path, run-as account, and description.

Arguments:
  SERVICE  Exact service name or display name, case-insensitive.

Options:
  -h, --help   Show this help.

Exit status: 0 when active (Running or Paused), 3 when inactive (Stopped and
transitional states like StartPending), 4 when the service is unknown, 1 on
operational failure, 21/22 on CLI misuse.

Example:
  wslsvc status Spooler'
	local detail startmode starttype pid binpath account desc

	svc_parse_target "$@"
	local target="$svc_target"

	if ! svc_fetch; then
		error_echo "Failed to query Windows services." 1
	fi
	svc_resolve status "$target"
	case "$?" in
		0) ;;
		2) error_echo "Unknown service: '$target'." 4;;
		*) error_echo "Failed to resolve '$target'." 1;;
	esac

	if ! detail=$(winps_exec "Get-CimInstance Win32_Service | Where-Object { \$_.Name -eq ($(winps_string "$res_name")) } | ForEach-Object { [string]\$_.StartMode + [char]9 + [string]\$_.ProcessId + [char]9 + [string]\$_.PathName + [char]9 + [string]\$_.StartName + [char]9 + (\$_.Description -replace '\s+', ' ') }"); then
		error_echo "Failed to query details for '$res_name'." 1
	fi
	detail=${detail//$'\r'/}
	[ -n "$detail" ] || error_echo "Failed to query details for '$res_name'." 1
	IFS=$'\t' read -r startmode pid binpath account desc <<< "$detail"
	case "$startmode" in
		Auto) starttype="Automatic";;
		*) starttype="$startmode";;
	esac

	printf '%s (%s)\n' "$res_display" "$res_name"
	printf '%-12s %s\n' "State:" "$res_state"
	printf '%-12s %s\n' "Start type:" "$starttype"
	printf '%-12s %s\n' "PID:" "$pid"
	printf '%-12s %s\n' "Binary path:" "$binpath"
	printf '%-12s %s\n' "Run as:" "$account"
	printf '%-12s %s\n' "Description:" "$desc"

	case "${res_state,,}" in
		running|paused) return 0;;
		*) return 3;;
	esac
}

# svc_do ACTION: run Start-Service/Stop-Service for $res_name.
function svc_do {
	local action="$1" cmd out msg
	case "$action" in
		start) cmd="Start-Service";;
		stop) cmd="Stop-Service";;
	esac
	if ! out=$(winps_exec "try { $cmd -Name ($(winps_string "$res_name")) -ErrorAction Stop; 'WSLVC_OK' } catch { 'WSLVC_ERR ' + \$_.Exception.Message }"); then
		error_echo "Failed to $action '$res_name'." 1
	fi
	out=${out//$'\r'/}
	case "$out" in
		*WSLVC_OK*) return 0;;
		*WSLVC_ERR*)
			msg="${out#*WSLVC_ERR}"
			msg="${msg# }"
			if [[ "${msg,,}" == *denied* || "${msg,,}" == *elevat* ]]; then
				error_echo "Access denied for '$res_name'; this action needs elevation - rerun from an elevated shell." 1
			fi
			error_echo "Failed to $action '$res_name': $msg" 1;;
		*) error_echo "Failed to $action '$res_name'." 1;;
	esac
}

function svc_control {
	local action="$1"
	shift
	local help_short="wslsvc $action SERVICE [-h]"
	local help_details
	case "$action" in
		start) help_details='Start a Windows service unless it is already running. Already running
is a no-op with exit 0.';;
		stop) help_details='Stop a Windows service unless it is already stopped. Already stopped
is a no-op with exit 0.';;
		restart) help_details='Restart a Windows service: stop followed by start, regardless of the
current state. Restarting a stopped service starts it.';;
	esac
	help_details="$help_details

Arguments:
  SERVICE  Exact service name or display name, case-insensitive.

Options:
  -h, --help   Show this help.

A denied action exits 1; rerun from an elevated shell. An ambiguous match
prompts for a pick and confirmation on stderr; without an interactive stdin
exits 22.

Example:
  wslsvc $action Spooler"

	svc_parse_target "$@"
	local target="$svc_target"

	if ! svc_fetch; then
		error_echo "Failed to query Windows services." 1
	fi
	svc_resolve "$action" "$target"
	case "$?" in
		0) ;;
		2) error_echo "Unknown service: '$target'." 22;;
		*) error_echo "Failed to resolve '$target'." 1;;
	esac

	case "$action" in
		start)
			if [ "${res_state,,}" = "running" ]; then
				echo "${warn} Service '${res_name}' is already running; nothing to do." >&2
				exit 0
			fi
			svc_do start;;
		stop)
			if [ "${res_state,,}" = "stopped" ]; then
				echo "${warn} Service '${res_name}' is already stopped; nothing to do." >&2
				exit 0
			fi
			svc_do stop;;
		restart)
			svc_do stop
			svc_do start;;
	esac
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		list) shift; svc_list "$@"; exit;;
		status) shift; svc_status "$@"; exit;;
		start) shift; svc_control start "$@"; exit;;
		stop) shift; svc_control stop "$@"; exit;;
		restart) shift; svc_control restart "$@"; exit;;
		-h|--help) help "$0" "$help_short"; exit;;
		-v|--version) version; exit;;
		*) error_echo "Invalid input." 22; exit 22;;
	esac
done

error_echo "COMMAND is required." 21
exit 21
