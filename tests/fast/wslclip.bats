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

@test "wslclip saves a clipboard image to a converted Linux path" {
  target="$WSLU_TEST_ROOT/mnt/c/shots/shot.png"
  run env TEST_INPUT="$BATS_TEST_TMPDIR/input" "$BATS_TEST_TMPDIR/wslclip" --get-image "$target"
  [ "$status" -eq 0 ]
  assert_called "wslpath -w $target"
  decoded=$(decode_winps_log)
  [[ "$decoded" == *"C:\\shots\\shot.png"* ]]
  assert_called 'Clipboard]::GetImage()'
  assert_called 'ImageFormat]::Png'
}

@test "wslclip picks the image format from the extension" {
  target="$WSLU_TEST_ROOT/mnt/c/shots/shot.jpg"
  run env TEST_INPUT="$BATS_TEST_TMPDIR/input" "$BATS_TEST_TMPDIR/wslclip" --get-image "$target"
  [ "$status" -eq 0 ]
  assert_called 'ImageFormat]::Jpeg'
}

@test "wslclip passes Windows save paths through" {
  run env TEST_INPUT="$BATS_TEST_TMPDIR/input" "$BATS_TEST_TMPDIR/wslclip" --get-image 'C:/shots/shot.png'
  [ "$status" -eq 0 ]
  refute_called 'wslpath -w C:/shots/shot.png'
  decoded=$(decode_winps_log)
  [[ "$decoded" == *"C:/shots/shot.png"* ]]
}

@test "wslclip --get-image rejects --get" {
  run env TEST_INPUT="$BATS_TEST_TMPDIR/input" "$BATS_TEST_TMPDIR/wslclip" --get-image "$WSLU_TEST_ROOT/mnt/c/a.png" --get
  [ "$status" -eq 22 ]
}

@test "wslclip --get-image rejects CONTENT" {
  run env TEST_INPUT="$BATS_TEST_TMPDIR/input" "$BATS_TEST_TMPDIR/wslclip" --get-image "$WSLU_TEST_ROOT/mnt/c/a.png" text
  [ "$status" -eq 22 ]
}

@test "wslclip --get-image requires a file path" {
  run env TEST_INPUT="$BATS_TEST_TMPDIR/input" "$BATS_TEST_TMPDIR/wslclip" --get-image
  [ "$status" -eq 22 ]
}

@test "wslclip propagates image save failures" {
  make_instrumented_command wslclip \
    'winps_exec() { return 8; }' \
    "$BATS_TEST_TMPDIR/wslclip-image-fail"
  run "$BATS_TEST_TMPDIR/wslclip-image-fail" --get-image "$WSLU_TEST_ROOT/mnt/c/a.png"
  [ "$status" -eq 8 ]
}
