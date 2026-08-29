#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_fake_windows
}

@test "wslfetch - No parameter" {
  run out/wslfetch
  [ "$status" -eq 0 ]
  [[ "$output" != *"Expected one field"* ]]
  [[ "$output" == *"Windows Subsystem for Linux"* ]]
}

@test "wslfetch - Help" {
  run out/wslfetch --help
  [ "${lines[0]}" = "wslfetch - Part of wslu, a collection of utilities for Windows Subsystem for Linux (WSL)" ]
  [ "${lines[1]}" = "Usage: wslfetch [-hvcg] [-t THEME] [-o OPTIONS]" ]
}

@test "wslfetch - Help - Alt." {
  run out/wslfetch -h
  [ "${lines[0]}" = "wslfetch - Part of wslu, a collection of utilities for Windows Subsystem for Linux (WSL)" ]
  [ "${lines[1]}" = "Usage: wslfetch [-hvcg] [-t THEME] [-o OPTIONS]" ]
}

@test "wslfetch - Theme argument" {
  run out/wslfetch --theme /dev/null
  [ "$status" -eq 0 ]

  run out/wslfetch -t /dev/null
  [ "$status" -eq 0 ]
}
