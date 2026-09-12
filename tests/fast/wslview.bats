#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_fake_windows
  make_instrumented_command wslview \
    'wslu_get_build() { echo 22631; }; curl() { printf "curl %s\n" "$*" >> "$WSLU_TEST_LOG"; return "${TEST_CURL_STATUS:-22}"; }; winps_exec() { printf "launch %s\n" "$*" >> "$WSLU_TEST_LOG"; }' \
    "$BATS_TEST_TMPDIR/wslview"
}

@test "wslview - No parameter" {
  run "$BATS_TEST_TMPDIR/wslview"
  [ "$status" -eq 21 ]
}

@test "wslview - Help" {
  run "$BATS_TEST_TMPDIR/wslview" --help
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "wslview - Part of wslu, a collection of utilities for Windows Subsystem for Linux (WSL)" ]
  [[ "${lines[1]}" =~ ^Usage:\ .*wslview\ \[OPTIONS\]\ LINK_OR_FILE\ \[LINK_OR_FILE\ \.\.\.\]$ ]]
}

@test "wslview - Help - Alt." {
  run "$BATS_TEST_TMPDIR/wslview" -h
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "wslview - Part of wslu, a collection of utilities for Windows Subsystem for Linux (WSL)" ]
  [[ "${lines[1]}" =~ ^Usage:\ .*wslview\ \[OPTIONS\]\ LINK_OR_FILE\ \[LINK_OR_FILE\ \.\.\.\]$ ]]
}

@test "wslview - Linux - relative" {
  path="$WSLU_TEST_ROOT/linux/relative"
  mkdir -p "$path"
  cd "$path"
  run "$BATS_TEST_TMPDIR/wslview" --skip-validation-check .
  [ "$status" -eq 0 ]
  assert_called "wslpath -w $path"
  assert_called 'ShellExecute('
}

@test "wslview - Linux - absolute" {
  path="$WSLU_TEST_ROOT/linux/absolute"
  mkdir -p "$path"
  run "$BATS_TEST_TMPDIR/wslview" --skip-validation-check "$path"
  [ "$status" -eq 0 ]
  assert_called "wslpath -w $path"
  assert_called 'ShellExecute('
}

@test "wslview - Linux - file protocol" {
  path="$WSLU_TEST_ROOT/linux/file-protocol"
  mkdir -p "$path"
  run "$BATS_TEST_TMPDIR/wslview" --skip-validation-check "file://$path"
  [ "$status" -eq 0 ]
  assert_called "wslpath -w $path"
  assert_called 'ShellExecute('
}

@test "wslview - Windows folder in Linux - absolute" {
  path="$WSLU_TEST_ROOT/mnt/c/Windows"
  mkdir -p "$path"
  run "$BATS_TEST_TMPDIR/wslview" --skip-validation-check "$path"
  [ "$status" -eq 0 ]
  assert_called "wslpath -w $path"
  assert_called 'ShellExecute('
}

@test "wslview - Windows folder in Linux - file protocol" {
  path="$WSLU_TEST_ROOT/mnt/c/Users"
  mkdir -p "$path"
  run "$BATS_TEST_TMPDIR/wslview" --skip-validation-check "file://$path"
  [ "$status" -eq 0 ]
  assert_called "wslpath -w $path"
  assert_called 'ShellExecute('
}

@test "wslview - Windows - absolute" {
  target='C:/Users/Public'
  run "$BATS_TEST_TMPDIR/wslview" --skip-validation-check "$target"
  [ "$status" -eq 0 ]
  refute_called "wslpath -w $target"
  decoded=$(decode_winps_log)
  [[ "$decoded" == *"$target"* ]]
}

@test "wslview - Windows - file protocol" {
  target='file:///C:/Windows/System32'
  run "$BATS_TEST_TMPDIR/wslview" --skip-validation-check "$target"
  [ "$status" -eq 0 ]
  refute_called "wslpath -w $target"
  decoded=$(decode_winps_log)
  [[ "$decoded" == *"$target"* ]]
}

@test "wslview - Internet - no protocol" {
  target='www.duckduckgo.com'
  run "$BATS_TEST_TMPDIR/wslview" "$target"
  [ "$status" -eq 0 ]
  refute_called 'curl'
  refute_called "wslpath -w $target"
  decoded=$(decode_winps_log)
  [[ "$decoded" == *"$target"* ]]
}

@test "wslview - Internet - http" {
  target='http://info.cern.ch'
  run "$BATS_TEST_TMPDIR/wslview" "$target"
  [ "$status" -eq 0 ]
  refute_called 'curl'
  refute_called "wslpath -w $target"
  decoded=$(decode_winps_log)
  [[ "$decoded" == *"$target"* ]]
}

@test "wslview - Internet - https" {
  target='https://wslutiliti.es/'
  run "$BATS_TEST_TMPDIR/wslview" "$target"
  [ "$status" -eq 0 ]
  refute_called 'curl'
  refute_called "wslpath -w $target"
  decoded=$(decode_winps_log)
  [[ "$decoded" == *"$target"* ]]
}

@test "wslview - Internet - with brackets" {
  target='https://www.duckduckgo.com/?q=[wslu]'
  run "$BATS_TEST_TMPDIR/wslview" "$target"
  [ "$status" -eq 0 ]
  refute_called 'curl'
  refute_called "wslpath -w $target"
  decoded=$(decode_winps_log)
  [[ "$decoded" == *"$target"* ]]
}

@test "wslview opens a URL with a fragment without probing the network" {
  target='http://127.0.0.1:9077/#token=ffba2f59377788ee57edb31aeb859f335cb665a4e34fe116f4e8048cce8d0070'
  run "$BATS_TEST_TMPDIR/wslview" "$target"
  [ "$status" -eq 0 ]
  refute_called 'curl'
  refute_called "wslpath -w $target"
  assert_called 'Shell.Application'
  assert_called 'ShellExecute('
  assert_called 'FromBase64String'
  decoded=$(decode_winps_log)
  [[ "$decoded" == *"$target"* ]]
  refute_called 'Start ('
}

@test "wslview still accepts the deprecated validation configuration" {
  printf '%s\n' 'WSLVIEW_SKIP_VALIDATION_CHECK=0' > "$HOME/.wslurc"
  run "$BATS_TEST_TMPDIR/wslview" --skip-validation-check 'https://example.test'
  [ "$status" -eq 0 ]
  refute_called 'curl'
  decoded=$(decode_winps_log)
  [[ "$decoded" == *"https://example.test"* ]]
}

@test "wslview selects Explorer without opening it" {
  run "$BATS_TEST_TMPDIR/wslview" --skip-validation-check --engine cmd_explorer 'C:/Users/Public'
  [ "$status" -eq 0 ]
  refute_called 'curl --head'
  assert_called '& explorer.exe ('
}

@test "wslview converts Linux paths before launching" {
  mkdir -p "$WSLU_TEST_ROOT/mnt/c/folder with spaces"
  run "$BATS_TEST_TMPDIR/wslview" --skip-validation-check "$WSLU_TEST_ROOT/mnt/c/folder with spaces"
  [ "$status" -eq 0 ]
  assert_called 'wslpath -w'
  assert_called 'ShellExecute('
}

@test "wslview propagates launcher failures" {
  make_instrumented_command wslview \
    'wslu_get_build() { echo 22631; }; winps_exec() { return 9; }' \
    "$BATS_TEST_TMPDIR/wslview-fail"
  run "$BATS_TEST_TMPDIR/wslview-fail" --skip-validation-check https://example.test
  [ "$status" -eq 9 ]
}

@test "wslview opens multiple Linux paths" {
  path1="$WSLU_TEST_ROOT/mnt/c/multi/one"
  path2="$WSLU_TEST_ROOT/mnt/c/multi/two"
  mkdir -p "$path1" "$path2"
  run "$BATS_TEST_TMPDIR/wslview" --skip-validation-check "$path1" "$path2"
  [ "$status" -eq 0 ]
  assert_called "wslpath -w $path1"
  assert_called "wslpath -w $path2"
  [ "$(grep -cF 'ShellExecute(' "$WSLU_TEST_LOG")" -eq 2 ]
}

@test "wslview opens a URL and a path in one call" {
  path="$WSLU_TEST_ROOT/mnt/c/mixed"
  mkdir -p "$path"
  run "$BATS_TEST_TMPDIR/wslview" --skip-validation-check https://example.test "$path"
  [ "$status" -eq 0 ]
  assert_called "wslpath -w $path"
  decoded=$(decode_winps_log)
  [[ "$decoded" == *"https://example.test"* ]]
}

@test "wslview rejects an empty argument among multiple" {
  path="$WSLU_TEST_ROOT/mnt/c/multi/three"
  mkdir -p "$path"
  run "$BATS_TEST_TMPDIR/wslview" --skip-validation-check "" "$path"
  [ "$status" -eq 22 ]
  refute_called 'ShellExecute('
}

@test "wslview reports the first launcher failure across multiple" {
  make_instrumented_command wslview \
    'wslu_get_build() { echo 22631; }; winps_exec() { return 9; }' \
    "$BATS_TEST_TMPDIR/wslview-multi-fail"
  run "$BATS_TEST_TMPDIR/wslview-multi-fail" --skip-validation-check https://a.test https://b.test
  [ "$status" -eq 9 ]
}

@test "wslview --reveal highlights a Linux path in Explorer" {
  path="$WSLU_TEST_ROOT/mnt/c/reveal/report.pdf"
  mkdir -p "$(dirname "$path")"
  touch "$path"
  run "$BATS_TEST_TMPDIR/wslview" --reveal "$path"
  [ "$status" -eq 0 ]
  assert_called "wslpath -w $path"
  refute_called 'ShellExecute('
  decoded=$(decode_winps_log)
  [[ "$decoded" == *"/select,C:\\reveal\\report.pdf"* ]]
}

@test "wslview --reveal accepts a Windows path" {
  run "$BATS_TEST_TMPDIR/wslview" --reveal 'C:/Users/Public'
  [ "$status" -eq 0 ]
  refute_called "wslpath -w C:/Users/Public"
  decoded=$(decode_winps_log)
  [[ "$decoded" == *"/select,C:/Users/Public"* ]]
}

@test "wslview --reveal rejects a URL" {
  run "$BATS_TEST_TMPDIR/wslview" --reveal https://example.test
  [ "$status" -eq 22 ]
  refute_called '& explorer.exe ('
}

@test "wslview --reveal rejects a missing Linux path" {
  run "$BATS_TEST_TMPDIR/wslview" --reveal "$WSLU_TEST_ROOT/does-not-exist"
  [ "$status" -eq 22 ]
  refute_called '& explorer.exe ('
}

@test "wslview --reveal rejects combining with LINK_OR_FILE" {
  run "$BATS_TEST_TMPDIR/wslview" --reveal 'C:/Users/Public' 'C:/Windows'
  [ "$status" -eq 22 ]
  refute_called '& explorer.exe ('
}
