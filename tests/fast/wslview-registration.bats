#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_fake_windows
  make_instrumented_command wslview \
    'distro=${TEST_DISTRO:-debian}; sudo() { "$@"; }; update-alternatives() { printf "alternatives %s\n" "$*" >> "$WSLU_TEST_LOG"; case "${TEST_SCENARIO:-}:$1:${2:-}:${3:-}" in registered:--query:*) printf "Alternative: %s\n" "$TEST_ALT";; rollback:--query:*) return 1;; rollback:--install:*:www-browser) return 7;; unregister:--remove:x-www-browser:*) return 8;; *) return 0;; esac; }' \
    "$BATS_TEST_TMPDIR/wslview"
}

@test "wslview registration is idempotent" {
  run env TEST_SCENARIO=registered TEST_ALT="$(readlink -f "$BATS_TEST_TMPDIR/wslview")" "$BATS_TEST_TMPDIR/wslview" --reg-as-browser
  [ "$status" -eq 0 ]
  assert_called 'alternatives --query x-www-browser'
  assert_called 'alternatives --query www-browser'
  refute_called 'alternatives --install'
}

@test "wslview registration rolls back a partial install" {
  run env TEST_SCENARIO=rollback "$BATS_TEST_TMPDIR/wslview" --reg-as-browser
  [ "$status" -eq 1 ]
  assert_called 'alternatives --install /usr/bin/x-www-browser x-www-browser'
  assert_called 'alternatives --install /usr/bin/www-browser www-browser'
  assert_called 'alternatives --remove x-www-browser'
}

@test "wslview unregister attempts both alternatives and propagates failure" {
  run env TEST_SCENARIO=unregister "$BATS_TEST_TMPDIR/wslview" --unreg-as-browser
  [ "$status" -eq 1 ]
  assert_called 'alternatives --remove x-www-browser'
  assert_called 'alternatives --remove www-browser'
}

@test "wslview browser registration rejects unsupported distributions" {
  run env TEST_DISTRO=archlinux "$BATS_TEST_TMPDIR/wslview" --reg-as-browser
  [ "$status" -eq 34 ]
  [[ "$output" == *"Unsupported action for this distro"* ]]
  refute_called 'alternatives '
}
