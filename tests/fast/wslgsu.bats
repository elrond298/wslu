#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_fake_windows
}

#wslgsu testing
@test "wslgsu - Help" {
  run out/wslgsu --help
  [ "${lines[0]}" = "wslgsu - Part of wslu, a collection of utilities for Windows Subsystem for Linux (WSL)" ]
  [ "${lines[1]}" = "Usage: wslgsu [-u USERNAME] [-n NAME] [-S] SERVICE_OR_COMMAND" ]
  [ "${lines[2]}" = "wslgsu [-n NAME] -w" ]
  [ "${lines[3]}" = "wslgsu [-hv]" ]
}

@test "wslgsu - Help - Alt." {
  run out/wslgsu -h
  [ "${lines[0]}" = "wslgsu - Part of wslu, a collection of utilities for Windows Subsystem for Linux (WSL)" ]
  [ "${lines[1]}" = "Usage: wslgsu [-u USERNAME] [-n NAME] [-S] SERVICE_OR_COMMAND" ]
  [ "${lines[2]}" = "wslgsu [-n NAME] -w" ]
  [ "${lines[3]}" = "wslgsu [-hv]" ]
}