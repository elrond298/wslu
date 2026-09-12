#!/usr/bin/env bats

load test_helper

setup() {
  require_windows_wsl
}

@test "wsldoctor passes on this machine" {
  run out/wsldoctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS  WSL interop is available"* ]]
  [[ "$output" == *"PASS  Windows build"* ]]
}

@test "wsldoctor --fix is idempotent on a fixed machine" {
  run out/wsldoctor --fix
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS  WSL share hosts are in the Local intranet zone"* ]]
}
