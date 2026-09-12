#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_fake_windows
}

@test "header honors redirected interop disable guards" {
  cat > "$WSLU_DESTDIR/etc/wsl.conf" <<'EOF'
[interop]
enabled = false
EOF
  run out/wslview --help
  [ "$status" -eq 1 ]
  [[ "$output" == *"Interopability is disabled"* ]]

  printf '[automount]\nroot = %s\n' "$WSLU_TEST_ROOT/mnt" > "$WSLU_DESTDIR/etc/wsl.conf"
  mkdir -p "$WSLU_PROC_DIR/sys/fs/binfmt_misc"
  for name in WSLInterop WSLInterop-late; do
    rm -f "$WSLU_PROC_DIR/sys/fs/binfmt_misc/WSLInterop" "$WSLU_PROC_DIR/sys/fs/binfmt_misc/WSLInterop-late"
    printf 'disabled\n' > "$WSLU_PROC_DIR/sys/fs/binfmt_misc/$name"
    run out/wslview --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"temporarily disabled"* ]]
  done
}

@test "header installs refreshes and protects packaged resources" {
  resource="$WSLU_DESTDIR/usr/share/wslu/test-resource"
  destination_dir="$WSLU_TEST_ROOT/mnt/c/resources"
  destination="$destination_dir/test-resource"
  printf 'version one\n' > "$resource"
  sed '/^# shellcheck shell=bash$/i if [[ ${TEST_RESOURCE_ACTION:-} == 1 ]]; then wslu_file_check "$TEST_RESOURCE_DIR" test-resource "${TEST_RESOURCE_MODE:-}"; exit; fi' out/wslview > "$BATS_TEST_TMPDIR/resource-check"
  chmod +x "$BATS_TEST_TMPDIR/resource-check"

  run env TEST_RESOURCE_ACTION=1 TEST_RESOURCE_DIR="$destination_dir" "$BATS_TEST_TMPDIR/resource-check"
  [ "$status" -eq 0 ]
  cmp -s "$resource" "$destination"

  printf 'version two\n' > "$resource"
  run env TEST_RESOURCE_ACTION=1 TEST_RESOURCE_DIR="$destination_dir" TEST_RESOURCE_MODE='?!R' "$BATS_TEST_TMPDIR/resource-check"
  [ "$status" -eq 0 ]
  cmp -s "$resource" "$destination"

  rm -f "$destination"
  ln -s "$resource" "$destination"
  run env TEST_RESOURCE_ACTION=1 TEST_RESOURCE_DIR="$destination_dir" "$BATS_TEST_TMPDIR/resource-check"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Refusing unsafe resource destination"* ]]
}

@test "header refreshes oemcp and triggered_time when stale; baseexec stays on demand" {
  run out/wslview --help
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_STATE_HOME/wslu/baseexec" ]
  [[ -s "$XDG_STATE_HOME/wslu/oemcp" ]]
  [[ -s "$XDG_STATE_HOME/wslu/triggered_time" ]]

  printf '1\n' > "$XDG_STATE_HOME/wslu/triggered_time"
  printf '2\n' > "$WSLU_DESTDIR/usr/share/wslu/updated_time"
  printf 'STALE\n' > "$XDG_STATE_HOME/wslu/baseexec"
  run out/wslview --help
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_STATE_HOME/wslu/baseexec" ]
  [ "$(cat "$XDG_STATE_HOME/wslu/triggered_time")" -gt 2 ]
}
