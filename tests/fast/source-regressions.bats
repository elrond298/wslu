#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_fake_windows
}

@test "auto-mount uses mount state rather than directory contents" {
  mkdir -p "$BATS_TEST_TMPDIR/mnt/d"
  printf stale > "$BATS_TEST_TMPDIR/mnt/d/file"
  make_instrumented_command wslact \
    'interop_prefix() { printf "%s/" "$TEST_MNT"; }; sysdrive_prefix() { echo c; }; mountpoint() { [[ ${TEST_MOUNTED:-0} == 1 ]]; }; mount() { printf "mount %s\n" "$*" >> "$WSLU_TEST_LOG"; }' \
    "$BATS_TEST_TMPDIR/wslact"
  sed -i 's/if \[ "$EUID" -ne 0 \]; then/if false; then/' "$BATS_TEST_TMPDIR/wslact"

  run env TEST_MNT="$BATS_TEST_TMPDIR/mnt" TEST_MOUNTED=0 "$BATS_TEST_TMPDIR/wslact" auto-mount
  [ "$status" -eq 0 ]
  assert_called 'mount -t drvfs d:'

  : > "$WSLU_TEST_LOG"
  rm -f "$BATS_TEST_TMPDIR/mnt/d/file"
  run env TEST_MNT="$BATS_TEST_TMPDIR/mnt" TEST_MOUNTED=1 "$BATS_TEST_TMPDIR/wslact" auto-mount
  [ "$status" -eq 0 ]
  refute_called 'mount -t drvfs d:'
}

@test "base executable discovery has no hard-coded C system drive" {
  run grep -F '$(interop_prefix)"c/Windows/System32' src/wslu-header
  [ "$status" -eq 1 ]
}

@test "Debian package count includes only fully installed packages" {
  fixture="$BATS_TEST_TMPDIR/dpkg.txt"
  cat > "$fixture" <<'EOF'
ii  installed 1 amd64 installed
iU  unpacked 1 amd64 unpacked
iF  broken 1 amd64 broken
rc  removed 1 amd64 removed
EOF
  make_instrumented_command wslsys \
    'distro=debian; dpkg() { cat "$TEST_DPKG"; }' \
    "$BATS_TEST_TMPDIR/wslsys"

  run env TEST_DPKG="$fixture" "$BATS_TEST_TMPDIR/wslsys" --name wsl-package-count -s
  [ "$status" -eq 0 ]
  [ "$output" = 1 ]
}

@test "configured System32 path is used for Windows executables" {
  run out/wslsys --build -s
  [ "$status" -eq 0 ]
  [ "$output" = 22631 ]
  assert_called 'reg.exe query'
}
