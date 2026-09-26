#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_fake_windows
}

@test "wsldoctor - Help" {
  run out/wsldoctor --help
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "wsldoctor - Part of wslu, a collection of utilities for Windows Subsystem for Linux (WSL)" ]
  [[ "${lines[1]}" =~ ^Usage:\ .*wsldoctor\ \[OPTIONS\]$ ]]
}

@test "wsldoctor - Help - Alt." {
  run out/wsldoctor -h
  [ "$status" -eq 0 ]
  [[ "${lines[1]}" =~ ^Usage:\ .*wsldoctor\ \[OPTIONS\]$ ]]
}

@test "wsldoctor - Version" {
  run out/wsldoctor -v
  [ "$status" -eq 0 ]
  [[ "${output}" =~ ^wslu\ v[0-9] ]]
}

@test "wsldoctor rejects unknown options" {
  run out/wsldoctor --bogus
  [ "$status" -eq 22 ]
}

@test "wsldoctor passes all checks in a healthy environment" {
  run env WSLU_TEST_ZONE_SET=1 out/wsldoctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS  WSL interop is available"* ]]
  [[ "$output" == *"PASS  Windows System32 found"* ]]
  [[ "$output" == *"PASS  Windows PowerShell is available"* ]]
  [[ "$output" == *"PASS  Windows build"* ]]
  [[ "$output" == *"PASS  WSL share hosts are in the Local intranet zone"* ]]
  [[ "$output" == *"PASS  wslu configuration values are valid"* ]]
  refute_called '/t REG_DWORD'
}

@test "wsldoctor proposes the zone fix without applying it" {
  run out/wsldoctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN  WSL share hosts are not in the Local intranet zone"* ]]
  [[ "$output" == *"run wsldoctor --fix"* ]]
  [[ "$output" == *"reg.exe add \"HKCU"* ]]
  refute_called '/t REG_DWORD'
}

@test "wsldoctor --fix applies the zone rule" {
  run out/wsldoctor --fix
  [ "$status" -eq 0 ]
  assert_called 'Domains\wsl.localhost /v file /t REG_DWORD /d 1 /f'
  assert_called 'Domains\wsl$ /v file /t REG_DWORD /d 1 /f'
  [[ "$output" == *"PASS  WSL share hosts added to the Local intranet zone"* ]]
}

@test "wsldoctor --fix skips an already-present zone rule" {
  run env WSLU_TEST_ZONE_SET=1 out/wsldoctor --fix
  [ "$status" -eq 0 ]
  refute_called '/t REG_DWORD'
  [[ "$output" == *"PASS  WSL share hosts are in the Local intranet zone"* ]]
}

@test "wsldoctor warns on a Windows build older than 1903" {
  make_instrumented_command wsldoctor 'wslu_get_build() { echo 17763; }' "$BATS_TEST_TMPDIR/wsldoctor-old"
  run env WSLU_TEST_ZONE_SET=1 "$BATS_TEST_TMPDIR/wsldoctor-old"
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN  Windows build 17763 is older than 1903"* ]]
}

@test "wsldoctor warns on an invalid engine in custom.conf" {
  mkdir -p "$WSLU_TEST_ROOT/rootfs/etc/wslu"
  printf '%s\n' 'WSLVIEW_DEFAULT_ENGINE=bogus' > "$WSLU_TEST_ROOT/rootfs/etc/wslu/custom.conf"
  run env WSLU_TEST_ZONE_SET=1 out/wsldoctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN  WSLVIEW_DEFAULT_ENGINE is invalid: bogus"* ]]
}

@test "wsldoctor - helper check passes when no helper is running" {
  run env WSLU_TEST_ZONE_SET=1 out/wsldoctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS  wslview helper is not running (it starts on demand)"* ]]
}

@test "wsldoctor warns on a stale wslview helper port file" {
  printf '1\n' > "$XDG_STATE_HOME/wslu/wslview-helper.port"
  printf 'tok\n' > "$XDG_STATE_HOME/wslu/wslview-helper.token"
  run env WSLU_TEST_ZONE_SET=1 out/wsldoctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN  wslview helper port file is stale: no helper answers on that port"* ]]
  [[ "$output" == *"run wsldoctor --fix"* ]]
  [ -e "$XDG_STATE_HOME/wslu/wslview-helper.port" ]
}

@test "wsldoctor --fix removes a stale wslview helper port file" {
  printf '1\n' > "$XDG_STATE_HOME/wslu/wslview-helper.port"
  printf 'tok\n' > "$XDG_STATE_HOME/wslu/wslview-helper.token"
  run env WSLU_TEST_ZONE_SET=1 out/wsldoctor --fix
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS  removed the stale wslview helper port file"* ]]
  [ ! -e "$XDG_STATE_HOME/wslu/wslview-helper.port" ]
}

@test "wsldoctor - --on checks pass when nothing is running" {
  run env WSLU_TEST_ZONE_SET=1 out/wsldoctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS  wslview file server is not running (it starts on demand)"* ]]
  [[ "$output" == *"PASS  no wslview tunnels are open"* ]]
  [[ "$output" == *"PASS  target inbox is empty"* ]]
}

@test "wsldoctor warns on stale wslview file server state" {
  printf '99999999\n' > "$XDG_STATE_HOME/wslu/wslview-on-server.pid"
  run env WSLU_TEST_ZONE_SET=1 out/wsldoctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN  wslview file server state is stale"* ]]
  [ -e "$XDG_STATE_HOME/wslu/wslview-on-server.pid" ]
}

@test "wsldoctor --fix removes stale wslview file server state" {
  printf '99999999\n' > "$XDG_STATE_HOME/wslu/wslview-on-server.pid"
  run env WSLU_TEST_ZONE_SET=1 out/wsldoctor --fix
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS  removed the stale wslview file server state"* ]]
  [ ! -e "$XDG_STATE_HOME/wslu/wslview-on-server.pid" ]
}

@test "wsldoctor notices a running wslview file server with its port" {
  exec -a copyparty sleep 60 &
  wslu_doctor_fake_pid=$!
  printf '%s\n' "$wslu_doctor_fake_pid" > "$XDG_STATE_HOME/wslu/wslview-on-server.pid"
  printf '18090\n' > "$XDG_STATE_HOME/wslu/wslview-on-server.port"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/timeout"
  chmod +x "$BATS_TEST_TMPDIR/bin/timeout"
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" WSLU_TEST_ZONE_SET=1 out/wsldoctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN  wslview file server is running and answering on port 18090"* ]]
  [[ "$output" == *"note: it serves browsing until wslview --on TARGET --stop"* ]]
  kill "$wslu_doctor_fake_pid" 2>/dev/null || true
}

@test "wsldoctor warns when the file server does not answer" {
  exec -a copyparty sleep 60 &
  wslu_doctor_fake_pid=$!
  printf '%s\n' "$wslu_doctor_fake_pid" > "$XDG_STATE_HOME/wslu/wslview-on-server.pid"
  printf '18090\n' > "$XDG_STATE_HOME/wslu/wslview-on-server.port"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/timeout"
  chmod +x "$BATS_TEST_TMPDIR/bin/timeout"
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" WSLU_TEST_ZONE_SET=1 out/wsldoctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN  wslview file server is running but not answering on port 18090"* ]]
  kill "$wslu_doctor_fake_pid" 2>/dev/null || true
}

@test "wsldoctor warns when the recorded port file is missing" {
  exec -a copyparty sleep 60 &
  wslu_doctor_fake_pid=$!
  printf '%s\n' "$wslu_doctor_fake_pid" > "$XDG_STATE_HOME/wslu/wslview-on-server.pid"
  run env WSLU_TEST_ZONE_SET=1 out/wsldoctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN  wslview file server is running but its recorded port is missing"* ]]
  kill "$wslu_doctor_fake_pid" 2>/dev/null || true
}

@test "wsldoctor reports live tunnels with their recorded ports" {
  touch "$XDG_STATE_HOME/wslu/wslview-on-mytarget-12345.sock"
  printf '8190\n' > "$XDG_STATE_HOME/wslu/wslview-on-mytarget-12345.port"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/ssh"
  chmod +x "$BATS_TEST_TMPDIR/bin/ssh"
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" WSLU_TEST_ZONE_SET=1 out/wsldoctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS  tunnel to mytarget is open on port 8190"* ]]
}

@test "wsldoctor warns on stale tunnels and orphaned port records" {
  touch "$XDG_STATE_HOME/wslu/wslview-on-mytarget-12345.sock"
  printf '8190\n' > "$XDG_STATE_HOME/wslu/wslview-on-mytarget-12345.port"
  printf '8191\n' > "$XDG_STATE_HOME/wslu/wslview-on-gone-99.port"
  run env WSLU_TEST_ZONE_SET=1 out/wsldoctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN  tunnel to mytarget is stale"* ]]
  [[ "$output" == *"WARN  orphaned tunnel port record wslview-on-gone-99.port"* ]]
  [ -e "$XDG_STATE_HOME/wslu/wslview-on-mytarget-12345.sock" ]
}

@test "wsldoctor --fix closes stale tunnels and removes orphaned port records" {
  touch "$XDG_STATE_HOME/wslu/wslview-on-mytarget-12345.sock"
  printf '8190\n' > "$XDG_STATE_HOME/wslu/wslview-on-mytarget-12345.port"
  printf '8191\n' > "$XDG_STATE_HOME/wslu/wslview-on-gone-99.port"
  run env WSLU_TEST_ZONE_SET=1 out/wsldoctor --fix
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS  closed the stale tunnel to mytarget"* ]]
  [[ "$output" == *"PASS  removed the orphaned tunnel port record wslview-on-gone-99.port"* ]]
  [ ! -e "$XDG_STATE_HOME/wslu/wslview-on-mytarget-12345.sock" ]
  [ ! -e "$XDG_STATE_HOME/wslu/wslview-on-mytarget-12345.port" ]
  [ ! -e "$XDG_STATE_HOME/wslu/wslview-on-gone-99.port" ]
}

@test "wsldoctor - inbox reports items within the TTL" {
  mkdir -p "$HOME/.cache/wslu/inbox/run1"
  printf 'x\n' > "$HOME/.cache/wslu/inbox/run1/f.txt"
  run env WSLU_TEST_ZONE_SET=1 out/wsldoctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS  target inbox holds 1 item(s)"* ]]
  [[ "$output" == *"within the 7 day TTL"* ]]
}

@test "wsldoctor warns when inbox entries exceed the TTL" {
  mkdir -p "$HOME/.cache/wslu/inbox/old"
  touch -d '10 days ago' "$HOME/.cache/wslu/inbox/old"
  run env WSLU_TEST_ZONE_SET=1 out/wsldoctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN  target inbox holds 1 item(s)"* ]]
  [[ "$output" == *"older than 7 days"* ]]
  [[ "$output" == *"rm -rf"* ]]
  run env WSLU_TEST_ZONE_SET=1 out/wsldoctor --fix
  [ "$status" -eq 1 ]
  [ -e "$HOME/.cache/wslu/inbox/old" ]
}

@test "wsldoctor warns on orphaned file server records" {
  printf '18090\n' > "$XDG_STATE_HOME/wslu/wslview-on-server.port"
  run env WSLU_TEST_ZONE_SET=1 out/wsldoctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN  orphaned wslview file server records"* ]]
  run env WSLU_TEST_ZONE_SET=1 out/wsldoctor --fix
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS  removed the orphaned wslview file server records"* ]]
  [ ! -e "$XDG_STATE_HOME/wslu/wslview-on-server.port" ]
}

@test "wsldoctor colorizes the report on a terminal" {
  command -v script >/dev/null 2>&1 || skip "script(1) is not available"
  run script -qec "out/wsldoctor" /dev/null
  [[ "$output" == *$'\e[32mPASS'* ]]
}
