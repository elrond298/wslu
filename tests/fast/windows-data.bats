#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_fake_windows
}

@test "wslvar reads deterministic Windows environment data" {
  run out/wslvar --sys ProgramFiles
  [ "$status" -eq 0 ]
  [ "$output" = 'C:\Program Files' ]
  assert_called 'powershell.exe'
}

@test "wslvar reads deterministic shell-folder data" {
  run out/wslvar --shell Desktop
  [ "$status" -eq 0 ]
  [ "$output" = 'C:\Users\Test\Desktop' ]
}

@test "wslupath delegates conversions to the controlled wslpath" {
  run out/wslupath 'C:\Windows'
  [ "$status" -eq 0 ]
  [ "$output" = "$WSLU_TEST_ROOT/mnt/c/Windows" ]
  assert_called 'wslpath -u C:\Windows'
}

@test "wslfetch consumes deterministic wslsys output" {
  run out/wslfetch --generic --options windows-build,wsl-version
  [ "$status" -eq 0 ]
  [[ "$output" == *'Build: 22631'* ]]
  assert_called 'wslsys --wslfetch'
}

@test "Windows fakes reject unplanned calls and host paths" {
  run wslpath -w /tmp/outside-test-root
  [ "$status" -eq 97 ]

  run wslsys --unexpected
  [ "$status" -eq 97 ]

  run wslvar --unexpected
  [ "$status" -eq 97 ]
}
