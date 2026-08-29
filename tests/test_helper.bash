setup_fake_windows() {
  export WSLU_TEST_ROOT="$BATS_TEST_TMPDIR/wslu-test"
  export HOME="$WSLU_TEST_ROOT/home"
  export XDG_CONFIG_HOME="$WSLU_TEST_ROOT/config"
  export XDG_STATE_HOME="$WSLU_TEST_ROOT/state"
  export WSLU_TEST_LOG="$WSLU_TEST_ROOT/windows.log"
  export WSLU_WINDOWS_SYSTEM32="$WSLU_TEST_ROOT/mnt/c/Windows/System32"
  export PATH="$BATS_TEST_DIRNAME/../fake-windows/bin:$PWD/out:$PATH"
  export WSL_DISTRO_NAME="TestDistro"
  export WSLU_DESTDIR="$WSLU_TEST_ROOT/rootfs"
  export WSLU_PROC_DIR="$WSLU_TEST_ROOT/proc"
  export WSL_INTEROP="$WSLU_TEST_ROOT/interop"
  mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME/wslu" "$WSLU_DESTDIR/etc" "$WSLU_DESTDIR/usr/share/wslu" "$WSLU_PROC_DIR" "$WSLU_TEST_ROOT/mnt/c/Windows/System32" "$WSLU_TEST_ROOT/mnt/c/Temp"
  cp -a "$BATS_TEST_DIRNAME/../fake-windows/System32/." "$WSLU_WINDOWS_SYSTEM32/"
  cp src/etc/conf "$WSLU_DESTDIR/usr/share/wslu/conf"
  printf '[automount]\nroot = %s\n' "$WSLU_TEST_ROOT/mnt" > "$WSLU_DESTDIR/etc/wsl.conf"
  : > "$WSLU_TEST_LOG"
}

assert_called() {
  grep -F -- "$1" "$WSLU_TEST_LOG"
}

refute_called() {
  ! grep -F -- "$1" "$WSLU_TEST_LOG"
}

decode_winps_log() {
  grep -oE "FromBase64String\('[A-Za-z0-9+/=]+'\)" "$WSLU_TEST_LOG" |
    sed -e "s/^FromBase64String('//" -e "s/')$//" |
    while IFS= read -r value; do printf '%s\n' "$value" | base64 -d; printf '\n'; done
}

make_instrumented_command() {
  local command=$1 overrides=$2 output=$3
  OVERRIDES="$overrides" awk '/^# shellcheck shell=bash$/ { print ENVIRON["OVERRIDES"] } { print }' "out/$command" > "$output"
  chmod +x "$output"
}
