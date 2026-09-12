#!/usr/bin/env bats

# The resident helper can only be exercised against a real Windows side: it needs
# a real powershell.exe to start and a real ShellExecute to land. Everything else
# about it (request/fallback decisions, autostart bookkeeping) is covered by
# tests/fast/wslview-helper.bats.

load test_helper

setup() {
  require_windows_wsl
  temp_win=$(out/wslvar --sys TEMP | tr -d '\r')
  test_dir_win="$temp_win\\wslu-helper-${BATS_TEST_NUMBER}-$$"
  test_dir_linux=$(wslpath "$test_dir_win")
  mkdir -p "$test_dir_linux"

  # A private rootfs and state dir, so this drives the real helper without
  # depending on an installed wslu or on another test's leftovers.
  export WSLU_TEST_ROOT="$BATS_TEST_TMPDIR/root"
  export WSLU_DESTDIR="$WSLU_TEST_ROOT/rootfs"
  export XDG_STATE_HOME="$WSLU_TEST_ROOT/state"
  mkdir -p "$WSLU_DESTDIR/usr/share/wslu" "$WSLU_DESTDIR/etc" "$XDG_STATE_HOME/wslu"
  cp src/etc/conf "$WSLU_DESTDIR/usr/share/wslu/conf"
  cp src/etc/wslview-helper.ps1 "$WSLU_DESTDIR/usr/share/wslu/"
  : > "$WSLU_DESTDIR/etc/wsl.conf"
  export WSLU_WINDOWS_SYSTEM32="$WSLU_TEST_SYSTEM32"

  helper_port_file="$XDG_STATE_HOME/wslu/wslview-helper.port"
  helper_token_file="$XDG_STATE_HOME/wslu/wslview-helper.token"
}

teardown() {
  stop_helper
  rm -rf "${test_dir_linux:-}" "${WSLU_TEST_ROOT:-}"
}

# One request to the helper, returns the reply in $reply (empty when unreachable).
helper_request() {
  local port token
  reply=""
  [[ -s $helper_port_file && -s $helper_token_file ]] || return 1
  port=$(cat "$helper_port_file")
  token=$(cat "$helper_token_file")
  # fd 9, not 3: bats-core uses fd 3 for its own internal output
  { exec 9<>/dev/tcp/127.0.0.1/"$port"; } 2>/dev/null || return 1
  printf '%s\t%s\t%s\n' "$token" "$1" "${2:-}" >&9
  IFS= read -r -t 10 reply <&9
  exec 9<&- 9>&-
  [ "$reply" = "OK" ]
}


wait_for_helper() {
  local _
  for _ in $(seq 100); do
    helper_request ping && return 0
    sleep 0.2
  done
  return 1
}

stop_helper() {
  helper_request quit || true
}

write_marker_script() {		# write_marker_script <name> -> sets marker_linux/marker_win/script_linux
  local name=$1
  marker_linux="$test_dir_linux/$name.txt"
  marker_win="$test_dir_win\\$name.txt"
  script_linux="$test_dir_linux/$name.cmd"
  cat > "$script_linux" <<EOF
@echo off
> "$marker_win" echo launched
EOF
  rm -f "$marker_linux"
}

await_marker() {
  local _
  for _ in $(seq 50); do
    [[ -f "$marker_linux" ]] && break
    sleep 0.1
  done
  [ -f "$marker_linux" ]
}

@test "helper is started on the first call and used by the next one" {
  write_marker_script first

  # first call: no helper yet, so it launches the slow way and starts one
  run out/wslview --debug --skip-validation-check "$script_linux"
  [ "$status" -eq 0 ]
  [[ "$output" == *"wslview_helper_autostart: helper starting"* ]]
  await_marker

  # the helper must come up on its own, detached from that first call
  wait_for_helper
  [ -s "$helper_port_file" ]
  [ -s "$helper_token_file" ]

  write_marker_script second

  # second call: the helper is up, so the launch never touches powershell.exe
  run out/wslview --debug --skip-validation-check "$script_linux"
  [ "$status" -eq 0 ]
  [[ "$output" == *"wslview_helper_request: open -> OK"* ]]
  [[ "$output" != *"wslview_helper_autostart"* ]]
  await_marker
  [ "$(tr -d '\r\n' < "$marker_linux")" = launched ]

  # and it still answers after having done real work
  run helper_request ping
  [ "$reply" = "OK" ]
}

@test "helper reveal action highlights a file in Explorer" {
  write_marker_script warmup
  run out/wslview --skip-validation-check "$script_linux"
  [ "$status" -eq 0 ]
  wait_for_helper

  target_linux="$test_dir_linux/highlight.txt"
  target_win="$test_dir_win\\highlight.txt"
  printf 'x\n' > "$target_linux"

  run out/wslview --debug --reveal "$target_linux"
  [ "$status" -eq 0 ]
  [[ "$output" == *"wslview_helper_request: reveal -> OK"* ]]
}

@test "unreachable helper falls back to launching powershell.exe" {
  printf '19999\n' > "$helper_port_file"
  printf 'stale-token\n' > "$helper_token_file"

  write_marker_script fallback
  run out/wslview --debug --skip-validation-check "$script_linux"
  [ "$status" -eq 0 ]
  [[ "$output" == *"wslview_helper_request: open -> no reply"* || "$output" == *"helper starting"* ]]
  await_marker
}

@test "WSLVIEW_USE_HELPER=false never starts a helper" {
  echo 'WSLVIEW_USE_HELPER=false' > "$WSLU_DESTDIR/usr/share/wslu/custom.conf"

  write_marker_script disabled
  run out/wslview --debug --skip-validation-check "$script_linux"
  [ "$status" -eq 0 ]
  [[ "$output" != *"wslview_helper"* ]]
  await_marker
  [ ! -e "$helper_port_file" ]
}
