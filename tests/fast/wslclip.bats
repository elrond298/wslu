#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_fake_windows
  make_instrumented_command wslclip \
    'winps_exec_stdin() { printf "clipboard %s\n" "$1" >> "$WSLU_TEST_LOG"; cat > "$TEST_INPUT"; }; winps_exec() { printf "clipboard %s\n" "$*" >> "$WSLU_TEST_LOG"; printf fixture; }' \
    "$BATS_TEST_TMPDIR/wslclip"
}

@test "wslclip sends argument content through stdin" {
  value=$'one line\nsecond "line"'
  run env TEST_INPUT="$BATS_TEST_TMPDIR/input" "$BATS_TEST_TMPDIR/wslclip" "$value"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/input")" = "$value" ]
  assert_called 'Set-Clipboard -Value'
}

@test "wslclip sends piped content through stdin" {
  run bash -c 'printf piped | TEST_INPUT="$1" "$2"' _ "$BATS_TEST_TMPDIR/input" "$BATS_TEST_TMPDIR/wslclip"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/input")" = piped ]
}

@test "wslclip retrieves clipboard content" {
  run env TEST_INPUT="$BATS_TEST_TMPDIR/input" "$BATS_TEST_TMPDIR/wslclip" --get
  [ "$status" -eq 0 ]
  [ "$output" = fixture ]
  assert_called Get-Clipboard
}

@test "wslclip clears without consuming stdin" {
  run bash -c 'printf ignored | TEST_INPUT="$1" "$2" ""' _ "$BATS_TEST_TMPDIR/input" "$BATS_TEST_TMPDIR/wslclip"
  [ "$status" -eq 0 ]
  [ ! -s "$BATS_TEST_TMPDIR/input" ]
  assert_called 'Clipboard]::Clear()'
}

@test "wslclip propagates clear failures" {
  make_instrumented_command wslclip \
    'winps_exec() { return 8; }' \
    "$BATS_TEST_TMPDIR/wslclip-clear-fail"
  run "$BATS_TEST_TMPDIR/wslclip-clear-fail" ""
  [ "$status" -eq 8 ]
}

@test "wslclip propagates PowerShell failures" {
  make_instrumented_command wslclip \
    'winps_exec_stdin() { cat >/dev/null; return 8; }' \
    "$BATS_TEST_TMPDIR/wslclip-fail"
  run "$BATS_TEST_TMPDIR/wslclip-fail" value
  [ "$status" -eq 8 ]
}
