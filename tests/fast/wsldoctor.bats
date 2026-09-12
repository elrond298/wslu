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
