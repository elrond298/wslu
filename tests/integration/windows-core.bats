#!/usr/bin/env bats

load test_helper

setup() {
  require_windows_wsl
}

@test "real Windows build and environment are readable" {
  run out/wslsys --build -s
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]

  run out/wslvar --sys ProgramFiles
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[A-Za-z]:\\ ]]
}

@test "real wslpath round-trips a temporary path" {
  linux_path="$BATS_TEST_TMPDIR/round trip"
  mkdir -p "$linux_path"
  windows_path=$(wslpath -w "$linux_path")
  [ -n "$windows_path" ]
  [ "$(wslpath "$windows_path")" = "$linux_path" ]
}

@test "real PowerShell and cmd interop execute non-interactively" {
  run "$WSLU_TEST_POWERSHELL" -NoProfile -NonInteractive -Command "Write-Output WSLU_TEST"
  [ "$status" -eq 0 ]
  [[ "$output" == *WSLU_TEST* ]]

  run "$WSLU_TEST_CMD" /c ver
  [ "$status" -eq 0 ]
  [[ "$output" == *Windows* ]]
}
