#!/usr/bin/env bats

load ../integration/test_helper

setup() {
  [[ ${WSLU_RUN_MANUAL_TESTS:-} == 1 ]] || skip "set WSLU_RUN_MANUAL_TESTS=1 to run Windows-effect tests"
  require_windows_wsl
}

teardown() {
  "${WSLU_TEST_POWERSHELL:-powershell.exe}" -NoProfile -NonInteractive -Command "Get-ScheduledTask -TaskName 'WSLUtilities_Actions_Startup_WsluManualWakeup_*' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:\$false" >/dev/null 2>&1 || true
}

@test "register a real elevated wakeup task" {
  run out/wslgsu --name WsluManualWakeup --wakeup
  [ "$status" -eq 0 ]
}
