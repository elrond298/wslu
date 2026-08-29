# shellcheck shell=bash
# shellcheck disable=SC2329
set -o pipefail
help_short="wslsys [FIELD] [-s]\nwslsys -n NAME [-s]\nwslsys [-hv]"
help_details='Print WSL and Windows system information. With no argument, print all fields.

FIELD selects one value:
  -V, --wsl-version       WSL generation: 1 or 2.
  -I, --sys-installdate   Windows installation date.
  -b, --branch            Windows release branch, such as ni_release.
  -B, --build             Numeric Windows build, such as 22631.
  -F, --full-build        Full Windows build identifier.
  -U, --uptime            Time since the WSL instance started.
  -W, --win-uptime        Time since Windows started.
  -R, --release           Linux distribution name and release.
  -K, --kernel            Linux kernel version.
  -P, --package           Number of installed Linux packages.
  -i, --ip                WSL IPv4 address.
  -S, --display-scaling   Windows display scale, where 1 is 100 percent.
  -l, --locale            Windows locale with underscores, such as en_US.
  -t, --win-theme         Windows application theme: light or dark.
  -T, --win-system-type   Windows role: Desktop, Server, or Domain Controller.
  -d, --systemd-status    systemd status in this WSL distribution.

Arguments:
  NAME  Symbolic field name used by wslfetch. Valid names are:
        windows-install-date, windows-rel-branch, windows-build,
        windows-full-build, display-scaling, windows-locale, windows-theme,
        windows-uptime, wsl-version, wsl-uptime, wsl-release, wsl-kernel,
        wsl-package-count, wsl-ip, win-system-type, and wsl-systemd-status.

Options:
  -n, --name NAME   Select a field by NAME instead of a FIELD option.
  -s                Print only the value, without its label.
  -h, --help        Show this help.
  -v, --version     Show the wslu version.

Examples:
  wslsys
  wslsys --build
  wslsys --build -s
  wslsys --name wsl-kernel -s'

## Windows 10 information
function get_branch() {
	debug_echo "get_branch: called"
	branch=$("$(windows_system32)"/reg.exe query "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v BuildBranch | tail -n 2 | head -n 1 | sed -e 's|\r||g') || return 1
	[ -n "$branch" ] || return 1
	echo "${branch##* }"
}

function get_build() {
	debug_echo "get_build: called"
	build=$(wslu_get_build) || return 1
	[[ "$build" =~ ^[0-9]{1,9}$ ]] || return 1
	echo "$build"
}

function get_full_build() {
	debug_echo "get_full_build: called"
	full_build=$("$(windows_system32)"/reg.exe query "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v BuildLabEx | tail -n 2 | head -n 1 | sed -e 's|\r||g') || return 1
	[ -n "$full_build" ] || return 1
	echo "${full_build##* }"
}

function get_install_date() {
	debug_echo "get_install_date: called"
	installdate=$("$(windows_system32)"/reg.exe query "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v InstallDate | tail -n 2 | head -n 1 | sed -e 's|\r||g') || return 1
	[ -n "$installdate" ] || return 1
	installdate="${installdate##* }"
	[[ "$installdate" =~ ^(0x[0-9A-Fa-f]+|[0-9]+)$ ]] || return 1
	echo "$installdate"
}

function get_theme() {
	debug_echo "get_theme: called"
	win_theme=$("$(windows_system32)"/reg.exe query "HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize" /v AppsUseLightTheme | tail -n 2 | head -n 1 | sed -e 's|\r||g') || return 1
	[ -n "$win_theme" ] || return 1
	win_theme=${win_theme##* }
	case "$win_theme" in
		0x0) echo "dark";;
		0x1) echo "light";;
		*) return 1;;
	esac
}

function get_display_scaling() {
	debug_echo "get_display_scaling: called"
	up_path="$(wslvar -s USERPROFILE)" || return 1
	[ -n "$up_path" ] || return 1
	wslu_file_check "$(wslpath "$up_path")/wslu" "get_dpi.ps1" "?!S" || return 1
	dpi_script="$(double_dash_p "$up_path" | sed -e 's| |\` |g')\\wslu\\get_dpi.ps1"
	display_scaling="$(winps_exec "$dpi_script")" || return 1
	display_scaling="${display_scaling//$'\r'/}"
	[[ "$display_scaling" =~ ^[0-9]+$ ]] || return 1
	scaled="$(bc -l <<< "$display_scaling/100")" || return 1
	scaled="$(sed -e 's/\.0//g' -e 's/0*$//g' <<< "$scaled")" || return 1
	echo "$scaled"
}

function get_windows_uptime() {
	debug_echo "get_windows_uptime: called"
	win_uptime=$(winps_exec "[int64]((get-date) - (gcim Win32_OperatingSystem).LastBootUpTime).TotalSeconds" | sed -e 's|\r||g') || return 1
	[[ "$win_uptime" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
	win_uptime=${win_uptime//.*}
	w_days=$((win_uptime/86400))
	w_hours=$((win_uptime/3600%24))
	w_minutes=$((win_uptime/60%60))
	echo "${w_days}d ${w_hours}h ${w_minutes}m"
}

function get_windows_locale() {
	debug_echo "get_windows_locale: called"
	windows_locale=$(winps_exec "(Get-Culture).Name" | sed -e 's|\r||g' -e 's|-|_|g') || return 1
	[ -n "$windows_locale" ] || return 1
	echo "$windows_locale"
}

## WSL information

function get_wsl_version() {
	wslu_get_wsl_ver
}

function get_wsl_release() {
	debug_echo "get_wsl_release: called"
	release=$(grep "PRETTY_NAME=" /etc/os-release | sed -e 's/PRETTY_NAME=//g' -e 's/"//g') || return 1
	[ -n "$release" ] || return 1
	##  old version of fedora remix specific information
	if [ "$distro" == "oldfedora" ]; then
		release="Fedora Remix $(grep -e "^VERSION=" /etc/os-release | sed -e 's/\"//g' | sed -e 's/VERSION=//g')"
	fi
	echo "$release"
}

function get_wsl_kernel() {
	debug_echo "get_wsl_kernel: called"
	echo "$(</proc/sys/kernel/ostype) $(</proc/sys/kernel/osrelease)"
}

function get_wsl_uptime() {
	debug_echo "get_wsl_uptime: called"
	uptime=$(</proc/uptime)
	uptime=${uptime//.*}
	days=$((uptime/86400))
	hours=$((uptime/3600%24))
	minutes=$((uptime/60%60))
	echo "${days}d ${hours}h ${minutes}m"
}

function get_wsl_packages() {
	debug_echo "get_wsl_packages: called"
	case "$distro" in
		'pengwin'|'ubuntu'|'kali'|'debian'|'wlinux')
			packages=$(dpkg -l | grep -c '^ii[[:space:]]') || return 1;;
		'opensuse'|'sles'|'scilinux'|'oldfedora'|'fedora'|'fedoraremix'|'almalinux'|'oracle'|'cblm'|'clear')
			packages=$(rpm -qa | wc -l) || return 1;;
		'alpine')
			packages=$(apk info | wc -l) || return 1;;
		'archlinux')
			packages=$(pacman -Qq | wc -l) || return 1;;
		'gentoo')
			packages=$(qlist -IRv | wc -l) || return 1;;
		*) return 1;;
	esac
	echo "$packages"
}

function get_wsl_ip() {
	debug_echo "get_wsl_ip: called"
	ip -4 -o addr show eth0 | awk '{print $4}' | cut -d "/" -f 1
}

function get_win_system_type() {
	debug_echo "get_win_system_type: called"
	tp=$(winps_exec "(Get-WmiObject -Class Win32_OperatingSystem -Property ProductType).ProductType" | sed -e 's|\r||g') || return 1
	case "$tp" in
		"1")echo "Desktop";;
		"2")echo "Domain Controller";;
		"3")echo "Server";;
		*) return 1;;
	esac
}

function get_systemd() {
	debug_echo "get_systemd: called"
	wsl_version=$(get_wsl_version) || return 1
	case "$wsl_version" in
		2)
			systemd_setting=$(__wsl_conf_read boot systemd) || systemd_setting=""
			case "$systemd_setting" in
				true) echo "enabled";;
				false|"") echo "disabled";;
				*) return 1;;
			esac;;
		1) echo "N/A";;
		*) return 1;;
	esac
}

## Simple printer defined for fetching information
function printer() {
	debug_echo "printer: called with \"$1\" \"$2\""
	if [[ -n "$WSLSYS_WSLFETCH_COLOR" ]]; then
		debug_echo "printer: wslfetch printing"
		echo "$WSLSYS_WSLFETCH_COLOR$1${reset}: $2"
	elif [[ -z "$WSLSYS_WSLFETCH_SHORTFORM" ]]; then
		debug_echo "printer: long form printing"
		echo "$1: $2"
	else
		debug_echo "printer(wslsys): short form printing"
		echo "$2"
	fi
}

function print_getter() {
	local label="$1"
	local getter="$2"
	local value
	value=$("$getter") || return 1
	[ -n "$value" ] || return 1
	printer "$label" "$value"
}

# function to find the value using the param/number/option passed
function dict_finder() {
	debug_echo "dict_finder: called with $1 $2"
	# this function should only have two input: the content ($1) and the shortform param ($2).
	# the dict looks like this:
	## num|short_param|long_param|option)
	##	printer "readable name" "value" "$2"
	##	return;;
	# num is used for empty input for iteration only
	# param are for parameter passing
	# option are for --wslfetch and --name
	local WSLSYS_WSLFETCH_SHORTFORM="$2"
	case $1 in
		1|-I|--sys-installdate|windows-install-date)
			value=$(get_install_date) || return 1
			if [ -z "$WSLSYS_WSLFETCH_SHORTFORM" ]; then
				decimal=$(printf '%d' "$value") || return 1
				value=$(date -d "@$decimal") || return 1
			fi
			printer "Release Install Date" "$value";;
		2|-b|--branch|windows-rel-branch) print_getter "Branch" get_branch;;
		3|-B|--build|windows-build) print_getter "Build" get_build;;
		4|-F|--full-build|windows-full-build) print_getter "Full Build" get_full_build;;
		5|-S|--display-scaling|display-scaling) print_getter "Display Scaling" get_display_scaling;;
		6|-l|--locale|windows-locale) print_getter "Locale (Windows)" get_windows_locale;;
		7|-t|--win-theme|windows-theme) print_getter "Theme (Windows)" get_theme;;
		8|-W|--win-uptime|windows-uptime) print_getter "Uptime (Windows)" get_windows_uptime;;
		9|-V|--wsl-version|wsl-version) print_getter "Version (WSL)" get_wsl_version;;
		10|-U|--uptime|wsl-uptime) print_getter "Uptime (WSL)" get_wsl_uptime;;
		11|-R|--release|wsl-release) print_getter "Release" get_wsl_release;;
		12|-K|--kernel|wsl-kernel) print_getter "Kernel" get_wsl_kernel;;
		13|-P|--package|wsl-package-count) print_getter "Packages" get_wsl_packages;;
		14|-i|--ip|wsl-ip) print_getter "IPv4 Address" get_wsl_ip;;
		15|-T|--win-system-type|win-system-type) print_getter "System Type (Windows)" get_win_system_type;;
		16|-d|--systemd-status|wsl-systemd-status) print_getter "SystemD Status" get_systemd;;
		*) return 1;;
	esac
}

# main handler for wslsys
function wslsys_main() {
	debug_echo "wslsys_main: called"
	local name_mode=0
	# If input is empty, print everything available
	if [[ "$*" == "" ]]; then
		debug_echo "wslsys_main: printing everything"
		failed=0
		for i in {1..16}; do
			dict_finder "$i" || failed=1
		done
		[ "$failed" -eq 0 ] || exit 1
		exit
	fi
	# If input start with --wslfetch, doing wslfetch specific print, not intend to use externally
	if [[ "$1" == "--wslfetch" ]]; then
		debug_echo "wslsys_main: wslfetch printing"
		dict_finder "wsl-version" "-s" || exit 22
		IFS=',' read -r -a fetch_array <<< "$2"
		for i in "${fetch_array[@]}"; do
			if [[ "$i" != "wsl-version" ]] && ! WSLSYS_WSLFETCH_COLOR="$3" dict_finder "$i"; then
				exit 22
			fi
		done
		exit
	fi
	if [[ "$1" == "--name" ]] || [[ "$1" == "-n" ]]; then
		debug_echo "wslsys_main: --name/-n found"
		name_mode=1
		shift
	fi

	if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || { [ "$#" -eq 2 ] && [ "$2" != "-s" ]; }; then
		error_echo "Expected one field and optional -s." 22
		exit 22
	fi

	if [ "$name_mode" -eq 1 ]; then
		case "$1" in
			windows-install-date|windows-rel-branch|windows-build|windows-full-build|display-scaling|windows-locale|windows-theme|windows-uptime|wsl-version|wsl-uptime|wsl-release|wsl-kernel|wsl-package-count|wsl-ip|win-system-type|wsl-systemd-status) ;;
			*) error_echo "Unknown field name: $1" 22; exit 22;;
		esac
	else
		case "$1" in
			-I|--sys-installdate|-b|--branch|-B|--build|-F|--full-build|-S|--display-scaling|-l|--locale|-t|--win-theme|-W|--win-uptime|-V|--wsl-version|-U|--uptime|-R|--release|-K|--kernel|-P|--package|-i|--ip|-T|--win-system-type|-d|--systemd-status) ;;
			*) error_echo "Expected a FIELD option." 22; exit 22;;
		esac
	fi

	if ! dict_finder "$1" "${2:-}"; then
		echo "${error} Invalid input."
		exit 22
	fi
}

# pre-handler
case $1 in
		-h|--help) help "$0" "$help_short"; exit;;
		-v|--version) version; exit;;
		*)
		wslsys_main "$@"; exit;;
esac
