#!/usr/bin/env bats

load ../integration/test_helper

setup() {
  [[ ${WSLU_RUN_MANUAL_TESTS:-} == 1 ]] || skip "set WSLU_RUN_MANUAL_TESTS=1 to run Windows-effect tests"
  require_windows_wsl
  [[ $EUID -eq 0 ]] || skip "requires root in disposable WSL"
}

@test "synchronize the WSL clock from Windows" {
  run out/wslact time-sync
  [ "$status" -eq 0 ]
}

@test "auto-mount currently available Windows drives" {
  run out/wslact auto-mount
  [ "$status" -eq 0 ]
}

@test "flush and reclaim the Linux page cache" {
  run out/wslact memory-reclaim
  [ "$status" -eq 0 ]
}
