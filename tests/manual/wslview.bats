#!/usr/bin/env bats

load ../integration/test_helper

setup() {
  [[ ${WSLU_RUN_MANUAL_TESTS:-} == 1 ]] || skip "set WSLU_RUN_MANUAL_TESTS=1 to run Windows-effect tests"
  require_windows_wsl
  export PATH="$PWD/out:$PATH"
  test_file="$BATS_TEST_TMPDIR/wslu-view-smoke.txt"
  printf 'wslu manual smoke test\n' > "$test_file"
}

@test "open a real temporary file with its Windows handler" {
  run out/wslview --skip-validation-check "$test_file"
  [ "$status" -eq 0 ]
}

@test "open a real temporary folder with Explorer" {
  run out/wslview --skip-validation-check --engine cmd_explorer "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
}
