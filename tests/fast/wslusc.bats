#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_fake_windows
  make_instrumented_command wslusc \
    'wslu_get_build() { echo 22631; }; wslu_file_check() { :; }; winps_exec() { printf "shortcut %s\n" "$*" >> "$WSLU_TEST_LOG"; }; mv() { printf "move %s\n" "$*" >> "$WSLU_TEST_LOG"; }' \
    "$BATS_TEST_TMPDIR/wslusc"
}

@test "wslusc - No parameter" {
  run "$BATS_TEST_TMPDIR/wslusc"
  [ "$status" -eq 21 ]
}

@test "wslusc - Help" {
  run "$BATS_TEST_TMPDIR/wslusc" --help
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "wslusc - Part of wslu, a collection of utilities for Windows Subsystem for Linux (WSL)" ]
  [ "${lines[1]}" = "Usage: wslusc [OPTIONS] COMMAND [ARGUMENTS ...]" ]
  [ "${lines[2]}" = "wslusc -d SHORTCUT_FILE" ]
  [ "${lines[3]}" = "wslusc [-hv]" ]
}

@test "wslusc - Help - Alt." {
  run "$BATS_TEST_TMPDIR/wslusc" -h
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "wslusc - Part of wslu, a collection of utilities for Windows Subsystem for Linux (WSL)" ]
  [ "${lines[1]}" = "Usage: wslusc [OPTIONS] COMMAND [ARGUMENTS ...]" ]
  [ "${lines[2]}" = "wslusc -d SHORTCUT_FILE" ]
  [ "${lines[3]}" = "wslusc [-hv]" ]
}

@test "wslusc - non-exist file" {
  run "$BATS_TEST_TMPDIR/wslusc" wryyyyy
  [ "$status" -eq 30 ]
}

@test "wslusc - with GUI" {
  run "$BATS_TEST_TMPDIR/wslusc" --gui true
  [ "$status" -eq 0 ]
  decoded=$(decode_winps_log)
  [[ "$decoded" == *'wscript.exe'* ]]
  assert_called '$s.Save()'
}

@test "wslusc - without GUI" {
  run "$BATS_TEST_TMPDIR/wslusc" printf '%s' 'argument with spaces'
  [ "$status" -eq 0 ]
  assert_called 'shortcut $ErrorActionPreference='
  assert_called 'FromBase64String'
  assert_called '$s.Save()'
  assert_called 'move '
  run bash -c 'compgen -G "$1/wslu.*"' _ "$WSLU_TEST_ROOT/mnt/c/Temp"
  [ "$status" -eq 1 ]
}

@test "wslusc - with Custom Name" {
  run "$BATS_TEST_TMPDIR/wslusc" --gui --native --name 'My App' true
  [ "$status" -eq 0 ]
  decoded=$(decode_winps_log)
  [[ "$decoded" == *'wslg.exe'* ]]
  assert_called 'My App.lnk'
}

@test "wslusc reports PowerShell failures" {
  make_instrumented_command wslusc \
    'wslu_get_build() { echo 22631; }; wslu_file_check() { :; }; winps_exec() { return 7; }; mv() { return 0; }' \
    "$BATS_TEST_TMPDIR/wslusc-fail"
  run "$BATS_TEST_TMPDIR/wslusc-fail" true
  [ "$status" -eq 1 ]
  [[ "$output" == *'Failed to create Windows shortcut.'* ]]
  run bash -c 'compgen -G "$1/wslu.*"' _ "$WSLU_TEST_ROOT/mnt/c/Temp"
  [ "$status" -eq 1 ]
}

@test "wslusc reports move failures" {
  make_instrumented_command wslusc \
    'wslu_get_build() { echo 22631; }; wslu_file_check() { :; }; winps_exec() { return 0; }; mv() { return 7; }' \
    "$BATS_TEST_TMPDIR/wslusc-move-fail"
  run "$BATS_TEST_TMPDIR/wslusc-move-fail" true
  [ "$status" -eq 1 ]
  [[ "$output" == *'Failed to move shortcut'* ]]
}
