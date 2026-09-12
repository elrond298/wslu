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

Without options, the doctor only reports and prints the commands to fix
problems. With --fix, safe and idempotent fixes are applied first and
reported; the zone entries are the only fix applied this way. Re-run the
doctor after restarting WSL to confirm a fix took effect.

Options:
  --fix           Apply safe fixes after the checks.
  -h, --help      Show this help.
  -v, --version   Show the wslu version.

Exit status: 0 when every check passes, 1 when at least one check reports
WARN or FAIL.'

function doctor_result {
    printf '%-5s %s\n' "$1" "$2"
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
