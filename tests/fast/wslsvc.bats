#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_fake_windows
  make_instrumented_command wslsvc \
    'winps_exec() { printf "%s\n" "$*" >> "$WSLU_TEST_LOG"; case "$*" in *Start-Service*|*Stop-Service*) printf "%s\n" "${WSLU_FAKE_MUTATE:-WSLVC_OK}" ;; *Get-CimInstance*) printf "%s\n" "${WSLU_FAKE_DETAIL:-}" ;; *Get-Service*) printf "%s\n" "${WSLU_FAKE_SERVICES:-}" ;; esac; }' \
    "$BATS_TEST_TMPDIR/wslsvc"
  export WSLVC="$BATS_TEST_TMPDIR/wslsvc"
  export WSLU_FAKE_SERVICES=$'Spooler\tRunning\tPrint Spooler\nwuauserv\tStopped\tWindows Update\nBthServ\tStartPending\tBluetooth Support Service\nBits\tPaused\tBackground Intelligent Transfer Service'
  export WSLU_FAKE_DETAIL=$'Auto\t777\tC:\\Test\\svc.exe\tLocalSystem\tdemo description'
}

#wslsvc testing
@test "wslsvc - Help" {
  run out/wslsvc --help
  [ "${lines[0]}" = "wslsvc - Part of wslu, a collection of utilities for Windows Subsystem for Linux (WSL)" ]
  [ "${lines[1]}" = "Usage: wslsvc COMMAND ..." ]
}

@test "wslsvc - Help - Alt." {
  run out/wslsvc -h
  [ "${lines[0]}" = "wslsvc - Part of wslu, a collection of utilities for Windows Subsystem for Linux (WSL)" ]
  [ "${lines[1]}" = "Usage: wslsvc COMMAND ..." ]
}

@test "wslsvc - List - Help" {
  run out/wslsvc list --help
  [ "${lines[1]}" = "Usage: wslsvc list [SUBSTRING] [--state=STATE] [-h]" ]
  run out/wslsvc list -h
  [ "${lines[1]}" = "Usage: wslsvc list [SUBSTRING] [--state=STATE] [-h]" ]
}

@test "wslsvc - Status - Help" {
  run out/wslsvc status --help
  [ "${lines[1]}" = "Usage: wslsvc status SERVICE [-h]" ]
  run out/wslsvc status -h
  [ "${lines[1]}" = "Usage: wslsvc status SERVICE [-h]" ]
}

@test "wslsvc - Start - Help" {
  run out/wslsvc start --help
  [ "${lines[1]}" = "Usage: wslsvc start SERVICE [-h]" ]
}

@test "wslsvc - Stop - Help" {
  run out/wslsvc stop --help
  [ "${lines[1]}" = "Usage: wslsvc stop SERVICE [-h]" ]
}

@test "wslsvc - Restart - Help" {
  run out/wslsvc restart --help
  [ "${lines[1]}" = "Usage: wslsvc restart SERVICE [-h]" ]
}

@test "wslsvc list prints NAME STATE DISPLAY NAME columns" {
  run "$WSLVC" list
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ ^NAME\ +STATE\ +DISPLAY\ NAME$ ]]
  [[ "${lines[1]}" =~ ^Spooler\ +Running\ +Print\ Spooler$ ]]
  [[ "${lines[2]}" =~ ^wuauserv\ +Stopped\ +Windows\ Update$ ]]
  [ "${#lines[@]}" -eq 5 ]
}

@test "wslsvc list substring filters both name fields case-insensitively" {
  run "$WSLVC" list spool
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[1]}" =~ ^Spooler\ +Running\ +Print\ Spooler$ ]]

  run "$WSLVC" list PRINT
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[1]}" =~ ^Spooler\ +Running\ +Print\ Spooler$ ]]

  run "$WSLVC" list nope
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "wslsvc list substring does not match the state column" {
  run "$WSLVC" list run
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "wslsvc list --state filters exactly and composes with substring" {
  run "$WSLVC" list --state=stopped
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[1]}" =~ ^wuauserv\ +Stopped\ +Windows\ Update$ ]]

  run "$WSLVC" list --state=StartPending
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[1]}" =~ ^BthServ\ +StartPending\ +Bluetooth\ Support\ Service$ ]]

  run "$WSLVC" list intel --state=PAUSED
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[1]}" =~ ^Bits\ +Paused\ +Background\ Intelligent\ Transfer\ Service$ ]]

  run "$WSLVC" list spool --state=Stopped
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "wslsvc list rejects invalid --state before querying" {
  run "$WSLVC" list --state=bogus
  [ "$status" -eq 22 ]
  run "$WSLVC" list --state=RunningX
  [ "$status" -eq 22 ]
  run "$WSLVC" list --state=
  [ "$status" -eq 22 ]
  run "$WSLVC" list --state
  [ "$status" -eq 22 ]
  run "$WSLVC" list --state --help
  [ "$status" -eq 22 ]
  refute_called "Get-Service"
}

@test "wslsvc rejects malformed CLI input" {
  run out/wslsvc
  [ "$status" -eq 21 ]
  run out/wslsvc bogus
  [ "$status" -eq 22 ]
  run out/wslsvc ""
  [ "$status" -eq 22 ]

  run "$WSLVC" list ""
  [ "$status" -eq 22 ]
  run "$WSLVC" list one two
  [ "$status" -eq 22 ]
  run "$WSLVC" list --bogus
  [ "$status" -eq 22 ]

  run "$WSLVC" status
  [ "$status" -eq 21 ]
  run "$WSLVC" status ""
  [ "$status" -eq 22 ]
  run "$WSLVC" status Spooler extra
  [ "$status" -eq 22 ]
  run "$WSLVC" status --bogus
  [ "$status" -eq 22 ]
  run "$WSLVC" start
  [ "$status" -eq 21 ]
  run "$WSLVC" stop ""
  [ "$status" -eq 22 ]
  run "$WSLVC" restart a b
  [ "$status" -eq 22 ]
}

@test "wslsvc status shows details and exits 0 for active states" {
  run "$WSLVC" status Spooler
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "Print Spooler (Spooler)" ]]
  [[ "$output" == *"State:"*Running* ]]
  [[ "$output" == *"Start type:"*Automatic* ]]
  [[ "$output" == *"PID:"*777* ]]
  [[ "$output" == *"Binary path:"*"C:\\Test\\svc.exe"* ]]
  [[ "$output" == *"Run as:"*LocalSystem* ]]
  [[ "$output" == *"Description:"*"demo description"* ]]
  assert_called "Get-CimInstance"

  run "$WSLVC" status Bits
  [ "$status" -eq 0 ]
}

@test "wslsvc status exits 3 for inactive states" {
  run "$WSLVC" status wuauserv
  [ "$status" -eq 3 ]
  run "$WSLVC" status BthServ
  [ "$status" -eq 3 ]
}

@test "wslsvc status resolves display names case-insensitively" {
  run "$WSLVC" status "windows update"
  [ "$status" -eq 3 ]
  [[ "${lines[0]}" == "Windows Update (wuauserv)" ]]
}

@test "wslsvc status unknown service exits 4" {
  run "$WSLVC" status NoSuchService
  [ "$status" -eq 4 ]
  [[ "$output" == *"Unknown service"* ]]
  refute_called "Get-CimInstance"
}

@test "wslsvc start and stop act on exact matches unattended" {
  run "$WSLVC" start "windows update"
  [ "$status" -eq 0 ]
  assert_called "Start-Service"
  assert_called "FromBase64String"

  : > "$WSLU_TEST_LOG"
  run "$WSLVC" stop Spooler
  [ "$status" -eq 0 ]
  assert_called "Stop-Service"
  assert_called "FromBase64String"

  : > "$WSLU_TEST_LOG"
  run "$WSLVC" start NoSuchService
  [ "$status" -eq 22 ]
  refute_called "Start-Service"
}

@test "wslsvc start and stop are idempotent" {
  run "$WSLVC" start Spooler
  [ "$status" -eq 0 ]
  [[ "$output" == *"already running"* ]]
  refute_called "Start-Service"

  run "$WSLVC" stop wuauserv
  [ "$status" -eq 0 ]
  [[ "$output" == *"already stopped"* ]]
  refute_called "Stop-Service"
}

@test "wslsvc restart stops then starts regardless of state" {
  run "$WSLVC" restart wuauserv
  [ "$status" -eq 0 ]
  assert_called "Stop-Service"
  assert_called "Start-Service"

  : > "$WSLU_TEST_LOG"
  run "$WSLVC" restart Spooler
  [ "$status" -eq 0 ]
  assert_called "Stop-Service"
  assert_called "Start-Service"
}

@test "wslsvc ambiguous match without stdin exits 22 with candidates on stderr" {
  export WSLU_FAKE_SERVICES=$'One\tRunning\tdup\nTwo\tStopped\tdup'
  run bash -c '"$WSLVC" start dup < /dev/null 2>"$BATS_TEST_TMPDIR/err"'
  [ "$status" -eq 22 ]
  grep -Fq "Multiple services match 'dup'" "$BATS_TEST_TMPDIR/err"
  grep -Fq "1) dup (One)" "$BATS_TEST_TMPDIR/err"
  grep -Fq "2) dup (Two)" "$BATS_TEST_TMPDIR/err"
  refute_called "Start-Service"
}

@test "wslsvc ambiguous match requires a terminal; piped answers exit 22" {
  export WSLU_FAKE_SERVICES=$'One\tRunning\tdup\nTwo\tStopped\tdup'
  run bash -c 'printf "2\ny\n" | "$WSLVC" start dup'
  [ "$status" -eq 22 ]
  [[ "$output" == *"Multiple services match 'dup'"* ]]
  refute_called "Start-Service"
}

@test "wslsvc ambiguous match picks and confirms on a terminal" {
  export WSLU_FAKE_SERVICES=$'One\tRunning\tdup\nTwo\tStopped\tdup'
  run bash -c 'printf "2\ny\n" | timeout 30 script -qec "\"$WSLVC\" start dup" /dev/null'
  [ "$status" -eq 0 ]
  assert_called "Start-Service"
  encoded=$(sed -n "s/.*FromBase64String('\([^']*\)').*/\1/p" "$WSLU_TEST_LOG" | tail -n 1)
  [ "$(printf %s "$encoded" | base64 -d)" = "Two" ]
}

@test "wslsvc ambiguous match rejects bad picks and declined confirmation" {
  export WSLU_FAKE_SERVICES=$'One\tRunning\tdup\nTwo\tStopped\tdup'

  run bash -c 'printf "9\n" | timeout 30 script -qec "\"$WSLVC\" stop dup" /dev/null'
  [ "$status" -eq 22 ]
  refute_called "Stop-Service"

  run bash -c 'printf "1\nn\n" | timeout 30 script -qec "\"$WSLVC\" stop dup" /dev/null'
  [ "$status" -eq 1 ]
  [[ "$output" == *"Aborted"* ]]
  refute_called "Stop-Service"
}

@test "wslsvc denied actions exit 1 with an elevation hint" {
  export WSLU_FAKE_MUTATE='WSLVC_ERR Access is denied. (Exception from HRESULT: 0x80070005 (E_ACCESSDENIED))'
  run "$WSLVC" start wuauserv
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs elevation"* ]]
  [[ "$output" == *"elevated shell"* ]]
}

@test "wslsvc reports other Windows failures as operational errors" {
  export WSLU_FAKE_MUTATE='WSLVC_ERR service did not respond'
  run "$WSLVC" stop Spooler
  [ "$status" -eq 1 ]
  [[ "$output" == *"service did not respond"* ]]
}

@test "wslsvc encodes service names as data in PowerShell commands" {
  export WSLU_FAKE_SERVICES=$'bad"; Write-Output INJECTED; "\tStopped\traw name'
  run "$WSLVC" start 'bad"; Write-Output INJECTED; "'
  [ "$status" -eq 0 ]
  assert_called "FromBase64String"
  run grep -Fq "Write-Output INJECTED" "$WSLU_TEST_LOG"
  [ "$status" -eq 1 ]
}

@test "wslsvc reports query failures as operational errors" {
  export WSLU_FAKE_SERVICES=""
  run "$WSLVC" list
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to query Windows services"* ]]

  export WSLU_FAKE_SERVICES=$'Spooler\tRunning\tPrint Spooler'
  export WSLU_FAKE_DETAIL=""
  run "$WSLVC" status Spooler
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to query details"* ]]
}
