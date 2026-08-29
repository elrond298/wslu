# shellcheck shell=bash
var_type=${WSLVAR_DEFAULT_VARTYPE:-1}

help_short="wslvar [-sl] NAME\nwslvar [-hvSL]"
help_details='Read Windows environment variables and shell-folder paths.

Arguments:
  NAME  Case-insensitive Windows variable name. With --sys, examples include
        ProgramFiles, USERPROFILE, TEMP, and windir. With --shell, examples
        include Desktop, AppData, Start Menu, and Startup.

Options:
  -s, --sys        Read NAME from the Windows process environment.
  -l, --shell      Read NAME from the current user Shell Folders registry key.
  -S, --getsys     List environment names and values accepted by --sys.
  -L, --getshell   List shell-folder names and values accepted by --shell.
  -h, --help       Show this help.
  -v, --version    Show the wslu version.

Without -s or -l, WSLVAR_DEFAULT_VARTYPE selects the source: 1 means the
Windows environment and 2 means Shell Folders.

Examples:
  wslvar -s ProgramFiles
  wslvar -l Desktop
  wslvar --getsys
  wslvar --getshell'

function call_shell {
	winps_exec "\$ErrorActionPreference='Stop'; \$name=$(winps_string "$*"); \$property=(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders').PSObject.Properties[\$name]; if (\$null -eq \$property) { throw 'Unknown Shell Folder' }; \$property.Value"
}

function view_shell {
	output=$(winps_exec "Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'") || return 1
	printf '%s\n' "$output" | tail -n +3 | head -n -10
}

function call_sys {
	winps_exec "\$ErrorActionPreference='Stop'; \$value=[Environment]::GetEnvironmentVariable($(winps_string "$*")); if (\$null -eq \$value) { throw 'Unknown Environment Variable' }; \$value"
}

function view_sys {
	output=$(winps_exec "Get-ChildItem env:") || return 1
	printf '%s\n' "$output" | tail -n +2 | head -n -2
}

function cl_destoryer {
	echo "$@" | tr -d "\r"
}

function caller {
	if [ "$#" -eq 0 ] || [ -z "$*" ]; then
		error_echo "No input." 21
	fi
	case "$var_type" in
		1) raw_value="$(call_sys "$@")" || return $?;;
		2) raw_value="$(call_shell "$@")" || return $?;;
		*) error_echo "Invalid variable type." 22;;
	esac
	p="$(cl_destoryer "$raw_value")" || return $?
	echo "$p"
}

while [ "$1" != "" ]; do
	case "$1" in
		-s|--sys) var_type=1; shift;;
		-l|--shell) var_type=2; shift;;
		-S|--getsys) view_sys; exit;;
		-L|--getshell) view_shell; exit;;
		-h|--help) help "$0" "$help_short"; exit;;
		-v|--version) version; exit;;
		*) caller "$@"; exit;;
	esac
done

error_echo "No Input. Aborted." 21

