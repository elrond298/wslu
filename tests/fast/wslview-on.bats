#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_fake_windows
  export WSLVIEW_ON_PORT=18090
  mkdir -p "$WSLU_TEST_ROOT/shared/docs/my dir" "$WSLU_TEST_ROOT/other/docs"
  printf 'hello\n' > "$WSLU_TEST_ROOT/shared/docs/a b.txt"
  printf 'quote\n' > "$WSLU_TEST_ROOT/shared/docs/a'b.txt"
  printf 'win\n' > "$WSLU_TEST_ROOT/mnt/c/Temp/rep.pdf"
  printf '\nWSLVIEW_ON_PORT=18090\n' >> "$WSLU_DESTDIR/usr/share/wslu/conf"
  make_instrumented_command wslview '
    ssh() {
      printf "ssh %s\n" "$*" >> "$WSLU_TEST_LOG"
      if [[ "$*" == *"-fN"* ]]; then
        local prev="" a
        for a in "$@"; do
          [ "$prev" == "-S" ] && touch "$a"
          prev="$a"
        done
      fi
      if [[ "$*" == *"tar -xf -"* ]]; then
        cat > /dev/null
      fi
      if [[ "$*" == *"-O check"* ]]; then
        [ "${TEST_SSH_CHECK_UP:-0}" = 1 ] && return 0
        return 1
      fi
      if [[ "$*" == *"exec wslview"* ]]; then
        return "${TEST_SSH_RC:-0}"
      fi
      return 0
    }
    copyparty() {
      printf "copyparty %s\n" "$*" >> "$WSLU_TEST_LOG"
      exec -a copyparty sleep 60
    }
    sleep() { :; }
    timeout() { return 1; }  # port probe: fail fast (mirrored mode hangs on dead ports)
  ' "$BATS_TEST_TMPDIR/wslview"
}

teardown() {
  if [ -f "$XDG_STATE_HOME/wslu/wslview-on-server.pid" ]; then
    kill "$(<"$XDG_STATE_HOME/wslu/wslview-on-server.pid")" 2>/dev/null || true
  fi
}

@test "wslview --on - URL is forwarded to the target unchanged, no tunnel" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget https://example.com/x
  [ "$status" -eq 0 ]
  assert_called "ssh -o ConnectTimeout=10 mytarget"
  assert_called "https://example.com/x"
  refute_called "copyparty"
  refute_called "inbox"
  refute_called "ssh -fN"
}

@test "wslview --on - single file is copied to the inbox and opened there, no tunnel" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget "$WSLU_TEST_ROOT/shared/docs/a b.txt"
  [ "$status" -eq 0 ]
  assert_called "mkdir -p ~/.cache/wslu/inbox/"
  assert_called "a b.txt"
  assert_called "mtime +7"
  refute_called "copyparty"
  refute_called "ssh -fN"
}

@test "wslview --on - any directory works without configuration" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget "$WSLU_TEST_ROOT/shared/docs"
  [ "$status" -eq 0 ]
  assert_called "copyparty -i 127.0.0.1 --http-only -p 18090"
  assert_called ":/docs:rw"
  assert_called "http://localhost:18090/docs/"
  assert_called "ssh -fN"
}

@test "wslview --on - source names are readable" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget "$WSLU_TEST_ROOT/shared/docs/my dir"
  [ "$status" -eq 0 ]
  assert_called "http://localhost:18090/my-dir/"
}

@test "wslview --on - duplicate names get a numeric suffix" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget "$WSLU_TEST_ROOT/shared/docs" "$WSLU_TEST_ROOT/other/docs"
  [ "$status" -eq 0 ]
  assert_called "http://localhost:18090/docs/"
  assert_called "http://localhost:18090/docs-2/"
}

@test "wslview --on - a nested directory reuses the parent source and the server" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget "$WSLU_TEST_ROOT/shared"
  [ "$status" -eq 0 ]
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget "$WSLU_TEST_ROOT/shared/docs"
  [ "$status" -eq 0 ]
  assert_called "http://localhost:18090/shared/docs"
  [ "$(grep -c -- "copyparty -i" "$WSLU_TEST_LOG")" -eq 1 ]
  [ "$(wc -l < "$XDG_STATE_HOME/wslu/wslview-on-sources")" -eq 1 ]
}

@test "wslview --on - multiple directories share one file server" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget "$WSLU_TEST_ROOT/shared/docs"
  [ "$status" -eq 0 ]
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget "$WSLU_TEST_ROOT/other"
  [ "$status" -eq 0 ]
  assert_called "http://localhost:18090/other/"
  [ "$(wc -l < "$XDG_STATE_HOME/wslu/wslview-on-sources")" -eq 2 ]
  [ -f "$XDG_STATE_HOME/wslu/wslview-on-server.pid" ]
}

@test "wslview --on - distinct targets get distinct tunnels" {
  run "$BATS_TEST_TMPDIR/wslview" --on a_b "$WSLU_TEST_ROOT/shared/docs"
  [ "$status" -eq 0 ]
  run "$BATS_TEST_TMPDIR/wslview" --on a/b "$WSLU_TEST_ROOT/other"
  [ "$status" -eq 0 ]
  [ "$(grep -o -- '-S [^ ]*\.sock' "$WSLU_TEST_LOG" | sort -u | wc -l)" -ge 2 ]
}

@test "wslview --on - a stale registry is dropped when the server is not running" {
  printf 'oldname\t/old/path\trw\n' > "$XDG_STATE_HOME/wslu/wslview-on-sources"
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget "$WSLU_TEST_ROOT/shared/docs"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$XDG_STATE_HOME/wslu/wslview-on-sources")" -eq 1 ]
  ! grep -q "oldname" "$XDG_STATE_HOME/wslu/wslview-on-sources"
}

@test "wslview --on - missing absolute path is rejected" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget /nonexistent/xyz.txt
  [ "$status" -eq 22 ]
}

@test "wslview --on - missing relative path is rejected, not sent as URL" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget ./definitely-missing.txt
  [ "$status" -eq 22 ]
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget docs/definitely-missing.txt
  [ "$status" -eq 22 ]
  refute_called "exec wslview"
}

@test "wslview --on - Windows paths refer to this machine filesystem" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget C:/Temp/rep.pdf
  [ "$status" -eq 0 ]
  assert_called "mkdir -p ~/.cache/wslu/inbox/"
  assert_called "rep.pdf"
  refute_called "copyparty"
}

@test "wslview --on - a quote in a file name is escaped for the target shell" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget "$WSLU_TEST_ROOT/shared/docs/a'b.txt"
  [ "$status" -eq 0 ]
  assert_called "a'\\''b.txt"
}

@test "wslview --on --reveal opens the parent directory read-only" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget --reveal "$WSLU_TEST_ROOT/shared/docs/a b.txt"
  [ "$status" -eq 0 ]
  assert_called "http://localhost:18090/docs/"
  assert_called ":/docs:r"
  refute_called ":/docs:rw"
  refute_called "inbox"
}

@test "wslview --on - opening a reveal-only directory upgrades it to read-write" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget --reveal "$WSLU_TEST_ROOT/shared/docs/a b.txt"
  [ "$status" -eq 0 ]
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget "$WSLU_TEST_ROOT/shared/docs"
  [ "$status" -eq 0 ]
  assert_called ":/docs:rw"
}

@test "wslview --on - an existing tunnel is reused" {
  export TEST_SSH_CHECK_UP=1
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget https://example.com/
  [ "$status" -eq 0 ]
  refute_called "ssh -fN"
}

@test "wslview --on - remote failure propagates its exit code" {
  export TEST_SSH_RC=7
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget https://example.com/
  [ "$status" -eq 7 ]
}

@test "wslview --on - engine selection is forwarded to the target" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget -E cmd_explorer https://example.com/
  [ "$status" -eq 0 ]
  assert_called "exec wslview --engine cmd_explorer"
}

@test "wslview --on --stop tears down tunnels, server, and all state" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget "$WSLU_TEST_ROOT/shared/docs"
  [ "$status" -eq 0 ]
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget --stop
  [ "$status" -eq 0 ]
  assert_called "-O exit"
  [ ! -f "$XDG_STATE_HOME/wslu/wslview-on-server.pid" ]
  [ ! -f "$XDG_STATE_HOME/wslu/wslview-on-sources" ]
  [ ! -f "$XDG_STATE_HOME/wslu/wslview-on-server.args" ]
}

@test "wslview --stop without --on is rejected" {
  run "$BATS_TEST_TMPDIR/wslview" --stop
  [ "$status" -eq 22 ]
}

@test "wslview --on - --stop with input is rejected" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget --stop https://example.com/
  [ "$status" -eq 22 ]
}

@test "wslview --on - --stop with launch options is rejected" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget --stop -E powershell
  [ "$status" -eq 22 ]
}

@test "wslview --on - ACTION cannot be combined with --on" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget --reg-as-browser
  [ "$status" -eq 22 ]
}

@test "wslview --on - no input is rejected" {
  run "$BATS_TEST_TMPDIR/wslview" --on mytarget
  [ "$status" -eq 21 ]
}
