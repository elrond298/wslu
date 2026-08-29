#!/usr/bin/env bats

load test_helper

setup() {
  require_windows_wsl
  temp_win=$(out/wslvar --sys TEMP | tr -d '\r')
  test_dir_win="$temp_win\\wslu-view-${BATS_TEST_NUMBER}-$$"
  test_dir_linux=$(wslpath "$test_dir_win")
  mkdir -p "$test_dir_linux"
}

teardown() {
  rm -rf "${test_dir_linux:-}"
}

@test "default Windows shell launcher executes a bounded local command" {
  marker_linux="$test_dir_linux/launched.txt"
  marker_win="$test_dir_win\\launched.txt"
  script_linux="$test_dir_linux/wslu-shell-launch.cmd"
  cat > "$script_linux" <<EOF
@echo off
> "$marker_win" echo launched
EOF

  run out/wslview --skip-validation-check "$script_linux"
  [ "$status" -eq 0 ]

  for _ in {1..50}; do
    [[ -f "$marker_linux" ]] && break
    sleep 0.1
  done
  [ "$(tr -d '\r\n' < "$marker_linux")" = launched ]
}
