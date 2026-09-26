# shellcheck shell=bash
doctor_problems=0

help_short="wsldoctor [OPTIONS]"
help_details='Run self-checks on the WSL environment wslu depends on and print a
PASS/WARN/FAIL report with fix suggestions.

Checks:
  interop     WSL interop is available so wslu can reach Windows.
  system32    The Windows System32 directory is reachable.
  powershell  Windows PowerShell is available for wslu commands.
  build       Windows build number; 1903 (18362) or newer is required for
              converting Linux paths with wslpath -w.
  zone        The \\wsl.localhost and wsl$ share hosts are mapped to the
              Local intranet zone; without it, opening files from the Linux
              filesystem shows an "Open File - Security Warning" prompt.
  config      The wslu configuration values are valid.
  helper      The wslview helper port file points at a live helper; a stale
              file can hang wslview under mirrored networking.
  server      The wslview --on file server state: a stale pid file, or a
              server that does not answer on its recorded port. A running
              server is reported as WARN as a notice, not a fault.
  tunnel      The wslview --on tunnels: live ssh masters with their recorded
              ports, stale sockets, and orphaned port records.
  inbox       The target inbox (~/.cache/wslu/inbox) where files copied by
              wslview --on land; entries older than WSLVIEW_ON_INBOX_TTL days
              are pruned by the next copy call.

Without options, the doctor only reports and prints the commands to fix
problems. With --fix, safe and idempotent fixes are applied first and
reported; the zone entries are added, a stale wslview helper port file is
removed, and stale wslview --on server and tunnel state is cleaned up.
Inbox entries are only reported, never removed. Re-run the doctor after
restarting WSL to confirm a fix took effect.

Options:
  --fix           Apply safe fixes after the checks.
  -h, --help      Show this help.
  -v, --version   Show the wslu version.

Exit status: 0 when every check passes, 1 when at least one check reports
WARN or FAIL. A running wslview file server is reported as WARN as a notice,
not a fault.'

function doctor_result {
    local doctor_color=""
    if [ -t 1 ]; then
        case "$1" in
            PASS) doctor_color="$green";;
            WARN) doctor_color="$yellow";;
            FAIL) doctor_color="$red";;
        esac
    fi
    if [ -n "$doctor_color" ]; then
        printf '%s%-5s%s %s\n' "$doctor_color" "$1" "$reset" "$2"
    else
        printf '%-5s %s\n' "$1" "$2"
    fi
    case "$1" in
        WARN|FAIL) doctor_problems=$((doctor_problems+1));;
    esac
}

function zone_rule_present {
    local query_out
    query_out="$("$(windows_system32)"/reg.exe query "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings\\ZoneMap\\Domains\\$1" /v file 2>/dev/null </dev/null)"
    [[ "$query_out" == *REG_DWORD*0x1* ]]
}

function apply_zone_fix {
    local host
    local ok=1
    for host in wsl.localhost 'wsl$'; do
        if zone_rule_present "$host"; then
            printf '  fixed   %s is already in the Local intranet zone\n' "$host"
        elif "$(windows_system32)"/reg.exe add "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings\\ZoneMap\\Domains\\$host" /v file /t REG_DWORD /d 1 /f >/dev/null </dev/null; then
            printf '  fixed   added %s to the Local intranet zone\n' "$host"
        else
            ok=0
            printf '  failed  could not add %s to the Local intranet zone\n' "$host"
        fi
    done
    return $((1-ok))
}

if [ "$#" -gt 0 ]; then
    case "$1" in
        -h|--help) help "$0" "$help_short"; exit;;
        -v|--version) version; exit;;
        --fix) doctor_fix=1; shift;;
        *) error_echo "Unexpected option: $1" 22; exit 22;;
    esac
fi
[ "$#" -eq 0 ] || { error_echo "Unexpected parameter: $1" 22; exit 22; }

if [ -n "${WSL_INTEROP:-}" ] || [ -e /proc/sys/fs/binfmt_misc/WSLInterop ]; then
    doctor_result "PASS" "WSL interop is available"
elif grep -qi microsoft /proc/version 2>/dev/null; then
    doctor_result "FAIL" "WSL interop is not registered"
    printf '      fix: set [interop] enabled=true in /etc/wsl.conf and restart WSL\n'
else
    doctor_result "FAIL" "not running under WSL"
fi

if [ -d "$(windows_system32)" ]; then
    doctor_result "PASS" "Windows System32 found at $(windows_system32)"
else
    doctor_result "FAIL" "Windows System32 not found under the automount root"
    printf '      fix: check the [automount] root in /etc/wsl.conf\n'
fi

if [ -x "$(windows_system32)/WindowsPowerShell/v1.0/powershell.exe" ]; then
    doctor_result "PASS" "Windows PowerShell is available"
else
    doctor_result "FAIL" "Windows PowerShell not found"
    printf '      fix: reinstall Windows PowerShell 5.1 or check the automount root\n'
fi

wslu_doctor_build="$(wslu_get_build)"
if [[ "$wslu_doctor_build" =~ ^[0-9]{1,9}$ ]] && [ "$wslu_doctor_build" -ge 1 ] 2>/dev/null; then
    if [ "$wslu_doctor_build" -ge "$BN_MAY_NINETEEN" ]; then
        doctor_result "PASS" "Windows build $wslu_doctor_build supports Linux path conversion"
    else
        doctor_result "WARN" "Windows build $wslu_doctor_build is older than 1903 ($BN_MAY_NINETEEN)"
        printf '      fix: update Windows; wslpath -w on Linux paths needs build 1903\n'
    fi
else
    doctor_result "FAIL" "unable to determine the Windows build number"
fi

if zone_rule_present wsl.localhost && zone_rule_present 'wsl$'; then
    doctor_result "PASS" "WSL share hosts are in the Local intranet zone"
elif [ "${doctor_fix:-0}" -eq 1 ]; then
    if apply_zone_fix; then
        doctor_result "PASS" "WSL share hosts added to the Local intranet zone"
    else
        doctor_result "FAIL" "could not add WSL share hosts to the Local intranet zone"
        printf '      fix: add them manually with reg.exe (see the NOTES section of wslview(1))\n'
    fi
else
    doctor_result "WARN" "WSL share hosts are not in the Local intranet zone"
    printf '      fix: files opened from the Linux filesystem show a security warning\n'
    printf '      fix: run wsldoctor --fix, or add the hosts manually:\n'
    printf '      fix:   reg.exe add "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings\\ZoneMap\\Domains\\wsl.localhost" /v file /t REG_DWORD /d 1 /f\n'
    printf '      fix:   reg.exe add "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings\\ZoneMap\\Domains\\wsl$" /v file /t REG_DWORD /d 1 /f\n'
fi

# The wslview helper publishes its port to a state file. The file can outlive
# the helper (idle timeout, crash), and in WSL mirrored networking a connect to
# that dead port hangs instead of being refused, which is how wslview can
# appear to freeze. Ping the helper through the same bounded exchange wslview
# uses (wslview_helper_request in src/wslview.sh); the protocol is token TAB
# action TAB payload, reply OK.
if [ ! -f "$wslu_state_dir/wslview-helper.port" ]; then
    doctor_result "PASS" "wslview helper is not running (it starts on demand)"
else
    # shellcheck disable=SC2016 # the child script uses positional args, no expansion wanted
    wslu_doctor_helper_reply="$(timeout 6 bash -c '
        exec 3<>/dev/tcp/127.0.0.1/"$1" || exit 2
        printf "%s\t%s\t%s\n" "$2" ping ping >&3
        IFS= read -r -t 5 line <&3 || exit 3
        printf "%s" "$line"
    ' wsldoctor-helper "$(cat "$wslu_state_dir/wslview-helper.port")" "$(cat "$wslu_state_dir/wslview-helper.token" 2>/dev/null)" 2>/dev/null)"
    wslu_doctor_helper_reply="${wslu_doctor_helper_reply%$'\r'}"
    if [ "$wslu_doctor_helper_reply" = "OK" ]; then
        doctor_result "PASS" "wslview helper is running and answering"
    elif [ "${doctor_fix:-0}" -eq 1 ]; then
        rm -f "$wslu_state_dir/wslview-helper.port"
        doctor_result "PASS" "removed the stale wslview helper port file"
    else
        doctor_result "WARN" "wslview helper port file is stale: no helper answers on that port"
        printf '      fix: this file can hang wslview; run wsldoctor --fix, or delete:\n'
        printf '      fix:   %s\n' "$wslu_state_dir/wslview-helper.port"
    fi
fi

# wslview --on diagnostics. The file server, the tunnels and the inbox keep
# state under wslu_state_dir and ~/.cache/wslu/inbox; probe them the same way
# wslview does and report what a user can act on.

function doctor_port_answers {
    # shellcheck disable=SC2016 # the child script uses positional args, no expansion wanted
    timeout 1 bash -c 'exec 3<>/dev/tcp/127.0.0.1/"$1"' wsldoctor-port "$1" 2>/dev/null
}

function doctor_tunnel_answers {
    ssh -S "$1" -O check _ >/dev/null 2>&1
}


wslu_doctor_on_pid_file="$wslu_state_dir/wslview-on-server.pid"
wslu_doctor_on_port_file="$wslu_state_dir/wslview-on-server.port"
if [ ! -f "$wslu_doctor_on_pid_file" ]; then
    if [ -e "$wslu_doctor_on_port_file" ] || [ -e "$wslu_state_dir/wslview-on-server.args" ]; then
        if [ "${doctor_fix:-0}" -eq 1 ]; then
            rm -f "$wslu_doctor_on_port_file" "$wslu_state_dir/wslview-on-server.args"
            doctor_result "PASS" "removed the orphaned wslview file server records"
        else
            doctor_result "WARN" "orphaned wslview file server records (no server is running)"
            printf '      fix: run wsldoctor --fix, or delete %s\n' "$wslu_state_dir/wslview-on-server.*"
        fi
    else
        doctor_result "PASS" "wslview file server is not running (it starts on demand)"
    fi
elif wslu_pid_check "$(cat "$wslu_doctor_on_pid_file")" copyparty; then
    wslu_doctor_on_port="$(cat "$wslu_doctor_on_port_file" 2>/dev/null)"
    if [[ "$wslu_doctor_on_port" =~ ^[0-9]+$ ]] && doctor_port_answers "$wslu_doctor_on_port"; then
        doctor_result "WARN" "wslview file server is running and answering on port $wslu_doctor_on_port"
        printf '      note: it serves browsing until wslview --on TARGET --stop\n'
    elif [[ "$wslu_doctor_on_port" =~ ^[0-9]+$ ]]; then
        doctor_result "WARN" "wslview file server is running but not answering on port $wslu_doctor_on_port"
        printf '      fix: the port may be held by another program; reopen the directory, or run:\n'
        printf '      fix:   wslview --on TARGET --stop\n'
    else
        doctor_result "WARN" "wslview file server is running but its recorded port is missing"
        printf '      fix: wslview re-records it on the next --on call, or run wslview --on TARGET --stop\n'
    fi
elif [ "${doctor_fix:-0}" -eq 1 ]; then
    rm -f "$wslu_doctor_on_pid_file" "$wslu_state_dir/wslview-on-server.args" "$wslu_doctor_on_port_file"
    doctor_result "PASS" "removed the stale wslview file server state"
else
    doctor_result "WARN" "wslview file server state is stale: no server answers for that pid"
    printf '      fix: run wsldoctor --fix, or delete %s\n' "$wslu_state_dir/wslview-on-server.*"
fi

wslu_doctor_tunnel_seen=0
for wslu_doctor_sock in "$wslu_state_dir"/wslview-on-*.sock; do
    [ -e "$wslu_doctor_sock" ] || continue
    wslu_doctor_tunnel_seen=1
    wslu_doctor_name="${wslu_doctor_sock##*/wslview-on-}"
    wslu_doctor_name="${wslu_doctor_name%.sock}"
    wslu_doctor_name="${wslu_doctor_name%-*}"
    wslu_doctor_tport="$(cat "${wslu_doctor_sock%.sock}.port" 2>/dev/null)"
    if doctor_tunnel_answers "$wslu_doctor_sock"; then
        doctor_result "PASS" "tunnel to $wslu_doctor_name is open${wslu_doctor_tport:+ on port $wslu_doctor_tport}"
    elif [ "${doctor_fix:-0}" -eq 1 ]; then
        wslu_tunnel_close "$wslu_doctor_sock"
        doctor_result "PASS" "closed the stale tunnel to $wslu_doctor_name"
    else
        doctor_result "WARN" "tunnel to $wslu_doctor_name is stale: no ssh master answers"
        printf '      fix: run wsldoctor --fix, or delete %s\n' "$wslu_doctor_sock"
    fi
done
for wslu_doctor_pfile in "$wslu_state_dir"/wslview-on-*.port; do
    [ -e "$wslu_doctor_pfile" ] || continue
    [ "$wslu_doctor_pfile" = "$wslu_doctor_on_port_file" ] && continue
    [ -e "${wslu_doctor_pfile%.port}.sock" ] && continue
    wslu_doctor_tunnel_seen=1
    if [ "${doctor_fix:-0}" -eq 1 ]; then
        rm -f "$wslu_doctor_pfile"
        doctor_result "PASS" "removed the orphaned tunnel port record ${wslu_doctor_pfile##*/}"
    else
        doctor_result "WARN" "orphaned tunnel port record ${wslu_doctor_pfile##*/} (its tunnel is gone)"
        printf '      fix: run wsldoctor --fix, or delete %s\n' "$wslu_doctor_pfile"
    fi
done
if [ "$wslu_doctor_tunnel_seen" -eq 0 ]; then
    doctor_result "PASS" "no wslview tunnels are open"
fi

wslu_doctor_inbox="$HOME/.cache/wslu/inbox"
if [ ! -d "$wslu_doctor_inbox" ] || [ -z "$(find "$wslu_doctor_inbox" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    doctor_result "PASS" "target inbox is empty"
else
    wslu_doctor_inbox_count="$(find "$wslu_doctor_inbox" -mindepth 1 -maxdepth 1 | wc -l)"
    wslu_doctor_inbox_count="${wslu_doctor_inbox_count// /}"
    wslu_doctor_inbox_size="$(du -sh "$wslu_doctor_inbox" 2>/dev/null | cut -f1)"
    wslu_doctor_inbox_ttl="${WSLVIEW_ON_INBOX_TTL:-7}"
    [[ "$wslu_doctor_inbox_ttl" =~ ^[0-9]+$ ]] || wslu_doctor_inbox_ttl=7
    if [ -n "$(find "$wslu_doctor_inbox" -mindepth 1 -maxdepth 1 -mtime +"$wslu_doctor_inbox_ttl" -print -quit)" ]; then
        doctor_result "WARN" "target inbox holds $wslu_doctor_inbox_count item(s) ($wslu_doctor_inbox_size); some are older than $wslu_doctor_inbox_ttl days"
        printf '      fix: the next wslview --on copy call prunes them; remove now with:\n'
        printf '      fix:   rm -rf %s\n' "$wslu_doctor_inbox"
    else
        doctor_result "PASS" "target inbox holds $wslu_doctor_inbox_count item(s) ($wslu_doctor_inbox_size), all within the $wslu_doctor_inbox_ttl day TTL"
    fi
fi

if [ -n "${WSLVIEW_DEFAULT_ENGINE:-}" ] && [[ ! "$WSLVIEW_DEFAULT_ENGINE" =~ ^(powershell|cmd|cmd_explorer)$ ]]; then
    doctor_result "WARN" "WSLVIEW_DEFAULT_ENGINE is invalid: $WSLVIEW_DEFAULT_ENGINE"
    printf '      fix: set it to powershell, cmd, or cmd_explorer in the wslu conf\n'
else
    doctor_result "PASS" "wslu configuration values are valid"
fi


if [ "$doctor_problems" -gt 0 ]; then
    exit 1
fi
exit 0
