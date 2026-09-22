#!/usr/bin/env bats

load ../integration/test_helper

setup() {
  [[ ${WSLU_RUN_MANUAL_TESTS:-} == 1 ]] || skip "set WSLU_RUN_MANUAL_TESTS=1 to run Windows-effect tests"
  require_windows_wsl
  # Mutating verbs need an elevated Windows shell and a disposable service,
  # e.g. WSLU_TEST_SERVICE=SomeTestService. No default: services are machine-wide.
  service=${WSLU_TEST_SERVICE:-}
  [ -n "$service" ] || skip "set WSLU_TEST_SERVICE to a disposable Windows service"

@test "stop and start a disposable Windows service" {
  run out/wslsvc stop "$service"
  [ "$status" -eq 0 ]

  run out/wslsvc start "$service"
  [ "$status" -eq 0 ]
}

@test "restart a disposable Windows service regardless of state" {
  run out/wslsvc restart "$service"
  [ "$status" -eq 0 ]
}

@test "mutating verbs are idempotent on a known state" {
  run out/wslsvc stop "$service"
  [ "$status" -eq 0 ]
  run out/wslsvc stop "$service"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already stopped"* ]]

  run out/wslsvc start "$service"
  [ "$status" -eq 0 ]
  run out/wslsvc start "$service"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already running"* ]]
}
