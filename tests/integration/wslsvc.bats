#!/usr/bin/env bats

load test_helper

setup() {
  require_windows_wsl
}

#wslsvc read-only testing
@test "wslsvc lists Windows services with NAME STATE DISPLAY NAME columns" {
  run out/wslsvc list
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ ^NAME\ +STATE\ +DISPLAY\ NAME$ ]]
  [ "${#lines[@]}" -gt 1 ]
}

@test "wslsvc list filters by substring and state" {
  run out/wslsvc list spool --state=Running
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -ge 1 ]

  run out/wslsvc list --state=Stopped
  [ "$status" -eq 0 ]
}

@test "wslsvc status reports the Print Spooler read-only" {
  run out/wslsvc status Spooler
  [[ "$status" -eq 0 || "$status" -eq 3 ]]
  [[ "${lines[0]}" == *"Spooler"* ]]
  [[ "$output" == *"Start type:"* ]]
  [[ "$output" == *"Binary path:"* ]]
}

@test "wslsvc status resolves display names" {
  run out/wslsvc status "Print Spooler"
  [[ "$status" -eq 0 || "$status" -eq 3 ]]
  [[ "${lines[0]}" == "Print Spooler (Spooler)" ]]
}

@test "wslsvc status of an unknown service exits 4" {
  run out/wslsvc status WsluNoSuchService
  [ "$status" -eq 4 ]
}

@test "wslsvc rejects invalid states without effects" {
  run out/wslsvc list --state=bogus
  [ "$status" -eq 22 ]

  run out/wslsvc status WsluNoSuchService
  [ "$status" -eq 4 ]
}
