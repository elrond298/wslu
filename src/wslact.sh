# shellcheck shell=bash
help_short="wslact COMMAND ..."
help_details='Run one maintenance action for the current WSL distribution.

Commands:
  ts, time-sync, tr, time-reset
      Set the WSL clock from the Windows clock. Use after sleep or clock drift.
  am, auto-mount, sm, smart-mount
      Discover Windows drive letters and mount them under the WSL mount prefix,
      normally /mnt.
  mr, memory-reclaim, mem-reclaim
      Flush filesystem writes and drop the Linux page cache.

Each action requires root. Run "wslact COMMAND --help" for its options.

Options:
  -h, --help      Show this help.
  -v, --version   Show the wslu version.

Examples:
  sudo wslact time-sync
  sudo wslact auto-mount -m "metadata,uid=1000"
  sudo wslact memory-reclaim'

function time_reset {
	local help_short="wslact time-sync [-h]"
	local help_details='Set the WSL system clock to the current Windows date and time.
Use this after sleep, resume, or any other clock drift. The command requires root
because it changes the Linux system clock.

Options:
  -h, --help   Show this help.

Example:
  sudo wslact time-sync'

	while [ "$#" -gt 0 ]; do
		case "$1" in
			-h|--help) help "wslact" "$help_short"; exit;;
			*) error_echo "Unexpected option: $1" 22; exit 22;;
		esac
	done

	if [ "$EUID" -ne 0 ]; then
		error_echo "\`wslact time-sync\` requires you to run as root. Aborted." 1
	fi

	echo "${info} Before Sync: $(date +"%d %b %Y %T %Z")"
	if date -s "$(winps_exec "Get-Date -UFormat \"%m/%d/%Y %T %Z\"" | tr -d "\r")" >/dev/null; then
		echo "${info} After Sync: $(date +"%d %b %Y %T %Z")"
		echo "${info} Manual Time Reset Complete."
	else
		error_echo "Time Sync failed." 1
	fi
}

function auto_mount {
	local help_short="wslact auto-mount [-m OPTIONS] [-h]"
	local help_details='Discover Windows drive letters with fsutil.exe and mount each unmounted drive
as drvfs under the WSL mount prefix, normally /mnt. The command requires root.

Arguments:
  OPTIONS  Comma-separated options passed unchanged to "mount -t drvfs -o".
           Common WSL drvfs examples include metadata, uid=1000, gid=1000,
           umask=022, and case=dir. If omitted, options from /etc/wsl.conf are used
           when present.

Options:
  -m, --mount-options OPTIONS   Use OPTIONS instead of /etc/wsl.conf options.
  -h, --help                    Show this help.

Example:
  sudo wslact auto-mount -m "metadata,uid=1000,gid=1000"'
	mntpt_prefix="$(interop_prefix)"
	sysdrv_prefix="$(sysdrive_prefix)"

	mount_opt=""
	while [ "$#" -gt 0 ]; do
		case "$1" in
			-m|--mount-options)
				if [ -z "${2:-}" ] || [[ "$2" == -* ]]; then
					error_echo "$1 requires OPTIONS." 22
					exit 22
				fi
				mount_opt="$2"
				shift 2;;
			-h|--help) help "wslact" "$help_short"; exit;;
			*) error_echo "Unexpected option: $1" 22; exit 22;;
		esac
	done

	if [ "$EUID" -ne 0 ]; then
		error_echo "\`wslact auto-mount\` requires you to run as root. Aborted." 1
	fi

	#shellcheck disable=SC1003
	if ! drive_list=$(set -o pipefail; "$(windows_system32)"/fsutil.exe fsinfo drives | tail -1 | tr '[:upper:]' '[:lower:]' | tr -d ':\\' | sed -e 's/drives //g' -e "s|$sysdrv_prefix ||g" -e 's|\r||g' -e 's| $||g' -e 's| |\n|g'); then
		error_echo "Failed to enumerate Windows drives." 1
	fi

	if [ -n "$mount_opt" ]; then
		echo "${info} Custom mount option detected: $mount_opt"
	elif [ -f /etc/wsl.conf ]; then
		tmp="$(grep ^options /etc/wsl.conf | sed -r -e 's|^options[ ]+=[ ]+||g' -e 's|^"||g' -e 's|"$||g')"
		if [ "$tmp" != "" ]; then
			echo "${info} Custom mount option detected: $tmp"
			mount_opt="$tmp"
			unset tmp
		fi
	fi

	mount_s=0
	mount_f=0
	mount_j=0
	
	for drive in $drive_list; do
		if [[ ! -d "$mntpt_prefix$drive" ]] && ! mkdir -p "$mntpt_prefix$drive"; then
			error_echo "Failed to create mount point: $mntpt_prefix$drive" 1
		fi
		if ! mountpoint -q -- "$mntpt_prefix$drive"; then
			echo "${info} Mounting Drive ${drive^} to $mntpt_prefix$drive..."
			if mount -t drvfs "${drive}:" "$mntpt_prefix$drive" -o "$mount_opt" 2>/dev/null; then
				echo "${info} Mounted Drive ${drive^} to $mntpt_prefix$drive."
				mount_s=$((mount_s + 1))
			else
				echo "${error} Failed to mount Drive ${drive^}. Skipped."
				mount_f=$((mount_f + 1))
			fi
		else
			echo "${warn} Already mounted Drive ${drive^} at $mntpt_prefix$drive. Skipped."
			mount_j=$((mount_j + 1))
		fi
	done
	echo "${info} Auto mounting completed. $mount_s drive(s) succeed. $mount_f drive(s) failed. $mount_j drive(s) skipped."
	[ "$mount_f" -eq 0 ]
}

function memory_reclaim {
	local help_short="wslact memory-reclaim [-h]"
	local help_details='Flush pending filesystem writes, then write 1 to /proc/sys/vm/drop_caches
to discard the Linux page cache. It does not terminate processes or reclaim
memory still in active use. The command requires root.

Options:
  -h, --help   Show this help.

Example:
  sudo wslact memory-reclaim'

	while [ "$#" -gt 0 ]; do
		case "$1" in
			-h|--help) help "wslact" "$help_short"; exit;;
			*) error_echo "Unexpected option: $1" 22; exit 22;;
		esac
	done

	if [ "$EUID" -ne 0 ]; then
		error_echo "\`wslact memory-reclaim\` requires you to run as root. Aborted." 1
	fi

	sync || error_echo "Failed to flush filesystem writes." 1
	echo 1 > /proc/sys/vm/drop_caches || error_echo "Failed to drop the page cache." 1
	echo "${info} Memory Reclaimed."
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		ts|time-sync|tr|time-reset) shift; time_reset "$@"; exit;;
		am|auto-mount|sm|smart-mount) shift; auto_mount "$@"; exit;;
		mr|memory-reclaim|mem-reclaim) shift; memory_reclaim "$@"; exit;;
		-h|--help) help "$0" "$help_short"; exit;;
		-v|--version) version; exit;;
		*) error_echo "Invalid input." 22; exit 22;;
	esac
done

error_echo "COMMAND is required." 21
exit 21
