#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_fake_windows
  make_instrumented_command wslnotify \
    'winps_exec() { printf "launch %s\n" "$*" >> "$WSLU_TEST_LOG"; }' \
    "$BATS_TEST_TMPDIR/wslnotify"
}

@test "wslnotify - No parameter" {
  run "$BATS_TEST_TMPDIR/wslnotify"
  [ "$status" -eq 21 ]
}

@test "wslnotify - Help" {
  run "$BATS_TEST_TMPDIR/wslnotify" --help
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "wslnotify - Part of wslu, a collection of utilities for Windows Subsystem for Linux (WSL)" ]
  [[ "${lines[1]}" =~ ^Usage:\ .*wslnotify\ \[OPTIONS\]\ TEXT\ \[TEXT\ \.\.\.\]$ ]]
}

@test "wslnotify - Help - Alt." {
  run "$BATS_TEST_TMPDIR/wslnotify" -h
  [ "$status" -eq 0 ]
  [[ "${lines[1]}" =~ ^Usage:\ .*wslnotify\ \[OPTIONS\]\ TEXT\ \[TEXT\ \.\.\.\]$ ]]
}

@test "wslnotify sends a toast with the default title" {
  run "$BATS_TEST_TMPDIR/wslnotify" "build finished"
  [ "$status" -eq 0 ]
  assert_called "ToastNotificationManager"
  decoded=$(decode_winps_log)
  [[ "$decoded" == *"WSL"* ]]
  [[ "$decoded" == *"build finished"* ]]
}

@test "wslnotify joins multiple words as the body" {
  run "$BATS_TEST_TMPDIR/wslnotify" three words joined
  [ "$status" -eq 0 ]
  decoded=$(decode_winps_log)
  [[ "$decoded" == *"three words joined"* ]]
}

@test "wslnotify --title sets the first toast line" {
  run "$BATS_TEST_TMPDIR/wslnotify" --title backup "3 files copied"
  [ "$status" -eq 0 ]
  decoded=$(decode_winps_log)
  [[ "$decoded" == *"backup"* ]]
  [[ "$decoded" == *"3 files copied"* ]]
}

@test "wslnotify encodes text as data, not code" {
  run "$BATS_TEST_TMPDIR/wslnotify" 'bad"; Write-Output INJECTED; "'
  [ "$status" -eq 0 ]
  refute_called 'Write-Output INJECTED'
  decoded=$(decode_winps_log)
  [[ "$decoded" == *'bad"; Write-Output INJECTED; "'* ]]
}

@test "wslnotify rejects an empty body" {
  run "$BATS_TEST_TMPDIR/wslnotify" ""
  [ "$status" -eq 22 ]
}

@test "wslnotify rejects an unknown option" {
  run "$BATS_TEST_TMPDIR/wslnotify" --bogus hi
  [ "$status" -eq 22 ]
}

@test "wslnotify requires a value for --title" {
  run "$BATS_TEST_TMPDIR/wslnotify" --title
  [ "$status" -eq 22 ]
}

@test "wslnotify accepts -- before dash-prefixed text" {
  run "$BATS_TEST_TMPDIR/wslnotify" -- --restart-pending
  [ "$status" -eq 0 ]
  decoded=$(decode_winps_log)
  [[ "$decoded" == *"--restart-pending"* ]]
}

@test "wslnotify propagates launcher failures" {
  make_instrumented_command wslnotify \
    'winps_exec() { return 9; }' \
    "$BATS_TEST_TMPDIR/wslnotify-fail"
  run "$BATS_TEST_TMPDIR/wslnotify-fail" hello
  [ "$status" -eq 9 ]
}
