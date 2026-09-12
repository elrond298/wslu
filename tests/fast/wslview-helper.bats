#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_fake_windows
}

# make_instrumented_command injects after `# shellcheck shell=bash`, which in the
# assembled executables sits *before* the utility's own function definitions. That
# is right for overriding header functions (winps_exec, wslu_get_build, ...) but
# useless for overriding the helper transport, which src/wslview.sh defines later,
# so inject just before the main body instead.
make_instrumented_wslview() {
  local overrides=$1 output=$2
  awk -v o="$overrides" \
    'index($0, "while [ \"$#\" -gt 0 ]; do") == 1 && !done { print o; done = 1 } { print }' \
    out/wslview > "$output"
  chmod +x "$output"
}

# The helper resource is what gates autostart, so tests that do not copy it into
# the fake rootfs exercise the "no helper installed" path by default.
install_fake_helper_resource() {
  cp src/etc/wslview-helper.ps1 "$WSLU_DESTDIR/usr/share/wslu/"
}

@test "wslview - helper handles the launch without starting powershell" {
  make_instrumented_wslview \
    'wslview_helper_request() { printf "helper %s %s\n" "$1" "$2" >> "$WSLU_TEST_LOG"; return 0; }' \
    "$BATS_TEST_TMPDIR/wslview-helper-ok"
  run "$BATS_TEST_TMPDIR/wslview-helper-ok" --skip-validation-check 'C:/Users/Public'
  [ "$status" -eq 0 ]
  assert_called "helper open C:/Users/Public"
  refute_called 'powershell.exe'
}

@test "wslview - helper failure is propagated and does not fall back" {
  make_instrumented_wslview \
    'wslview_helper_request() { return 1; }' \
    "$BATS_TEST_TMPDIR/wslview-helper-fail"
  run "$BATS_TEST_TMPDIR/wslview-helper-fail" --skip-validation-check 'C:/Users/Public'
  [ "$status" -eq 1 ]
  refute_called 'powershell.exe'
}

@test "wslview - unreachable helper falls back to powershell" {
  make_instrumented_wslview \
    'wslview_helper_request() { return 2; }; winps_exec() { printf "launch %s\n" "$*" >> "$WSLU_TEST_LOG"; }' \
    "$BATS_TEST_TMPDIR/wslview-helper-down"
  run "$BATS_TEST_TMPDIR/wslview-helper-down" --skip-validation-check 'C:/Users/Public'
  [ "$status" -eq 0 ]
  assert_called 'ShellExecute('
}

@test "wslview - helper maps each engine to its own action" {
  make_instrumented_wslview \
    'wslview_helper_request() { printf "helper %s\n" "$1" >> "$WSLU_TEST_LOG"; return 0; }' \
    "$BATS_TEST_TMPDIR/wslview-helper-engines"
  run "$BATS_TEST_TMPDIR/wslview-helper-engines" --skip-validation-check 'C:/Users/Public'
  [ "$status" -eq 0 ]
  run "$BATS_TEST_TMPDIR/wslview-helper-engines" --skip-validation-check --engine cmd_explorer 'C:/Windows'
  [ "$status" -eq 0 ]
  assert_called "helper open"
  assert_called "helper explorer"
  refute_called 'powershell.exe'
}

@test "wslview --reveal asks the helper to reveal" {
  path="$WSLU_TEST_ROOT/mnt/c/reveal/report.pdf"
  mkdir -p "$(dirname "$path")"
  touch "$path"
  make_instrumented_wslview \
    'wslview_helper_request() { printf "helper %s %s\n" "$1" "$2" >> "$WSLU_TEST_LOG"; return 0; }' \
    "$BATS_TEST_TMPDIR/wslview-helper-reveal"
  run "$BATS_TEST_TMPDIR/wslview-helper-reveal" --reveal "$path"
  [ "$status" -eq 0 ]
  assert_called "helper reveal"
  refute_called 'powershell.exe'
}

@test "wslview - unreachable helper is started in the background for the next call" {
  install_fake_helper_resource
  make_instrumented_command wslview \
    'wslu_get_build() { echo 22631; }; winps_exec() { printf "launch %s\n" "$*" >> "$WSLU_TEST_LOG"; }' \
    "$BATS_TEST_TMPDIR/wslview-autostart"
  run "$BATS_TEST_TMPDIR/wslview-autostart" --skip-validation-check 'C:/Users/Public'
  [ "$status" -eq 0 ]

  # this call still went the slow way...
  assert_called 'ShellExecute('
  # ...and a helper was spawned for the next one
  assert_called 'powershell.exe'
  assert_called '<-PortFile>'
  assert_called 'wslview-helper.port'
  assert_called '<-WindowStyle>'
  assert_called '<-Token>'
  assert_called 'wslview-helper.ps1'
}

@test "wslview - autostart keeps the token private and asks the helper to publish its port" {
  install_fake_helper_resource
  make_instrumented_command wslview \
    'wslu_get_build() { echo 22631; }; winps_exec() { printf "launch %s\n" "$*" >> "$WSLU_TEST_LOG"; }' \
    "$BATS_TEST_TMPDIR/wslview-autostart-files"
  run "$BATS_TEST_TMPDIR/wslview-autostart-files" --skip-validation-check 'C:/Users/Public'
  [ "$status" -eq 0 ]

  state="$XDG_STATE_HOME/wslu"
  [ -s "$state/wslview-helper.token" ]
  [ "$(stat -c '%a' "$state/wslview-helper.token")" = "600" ]

  # wslview must not invent a port: only the helper publishes one, and the file is
  # deleted first so that its existence proves the helper bound successfully
  [ ! -e "$state/wslview-helper.port" ]
  assert_called '<-PortFile>'
  assert_called 'wslview-helper.port'

  [ -s "$state/wslview-helper.attempt" ]
}

@test "wslview - autostart is rate limited so a broken helper cannot spawn a process per call" {
  install_fake_helper_resource
  make_instrumented_command wslview \
    'wslu_get_build() { echo 22631; }; winps_exec() { printf "launch %s\n" "$*" >> "$WSLU_TEST_LOG"; }' \
    "$BATS_TEST_TMPDIR/wslview-ratelimit"
  run "$BATS_TEST_TMPDIR/wslview-ratelimit" --skip-validation-check 'C:/Users/Public'
  [ "$status" -eq 0 ]
  started=$(grep -cF 'powershell.exe' "$WSLU_TEST_LOG")
  [ "$started" -eq 1 ]

  run "$BATS_TEST_TMPDIR/wslview-ratelimit" --skip-validation-check 'C:/Users/Public'
  [ "$status" -eq 0 ]
  [ "$(grep -cF 'powershell.exe' "$WSLU_TEST_LOG")" -eq 1 ]
}

@test "wslview - WSLVIEW_USE_HELPER=false keeps the legacy launcher" {
  install_fake_helper_resource
  echo 'WSLVIEW_USE_HELPER=false' > "$HOME/.wslurc"
  make_instrumented_command wslview \
    'wslu_get_build() { echo 22631; }; winps_exec() { printf "launch %s\n" "$*" >> "$WSLU_TEST_LOG"; }' \
    "$BATS_TEST_TMPDIR/wslview-helper-off"
  run "$BATS_TEST_TMPDIR/wslview-helper-off" --skip-validation-check 'C:/Users/Public'
  [ "$status" -eq 0 ]
  assert_called 'ShellExecute('
  refute_called 'powershell.exe'
  [ ! -e "$XDG_STATE_HOME/wslu/wslview-helper.port" ]
}

@test "wslview - helper resource is shipped and installed" {
  [ -f src/etc/wslview-helper.ps1 ]
  grep -q 'src/etc/\*.ps1' Makefile
}
