#!/usr/bin/env bats

load ../integration/test_helper

setup() {
  [[ ${WSLU_RUN_MANUAL_TESTS:-} == 1 ]] || skip "set WSLU_RUN_MANUAL_TESTS=1 to run Windows-effect tests"
  require_windows_wsl
  export PATH="$PWD/out:$PATH"
  desktop=$(wslupath -D)
}

teardown() {
  [[ -n ${desktop:-} ]] && rm -f "$desktop/WsluManualTerminal.lnk" "$desktop/WsluManualGui.lnk" || true
}

@test "create real terminal shortcut on Desktop" {
  run out/wslusc --name WsluManualTerminal top
  [ "$status" -eq 0 ]
  [ -f "$desktop/WsluManualTerminal.lnk" ]
}

@test "create real GUI shortcut on Desktop" {
  run out/wslusc --gui --name WsluManualGui xeyes
  [ "$status" -eq 0 ]
  [ -f "$desktop/WsluManualGui.lnk" ]
}
