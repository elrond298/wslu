#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_fake_windows
}

@test "all commands provide self-contained help" {
  for command in wslact wslclip wslfetch wslgsu wslnotify wslsys wslupath wslusc wslvar wslview; do
    run "out/$command" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Options:"* ]]
    [[ "$output" != *"wslutiliti.es"* ]]
    [[ "$output" != *"man $command"* ]]
  done
}

@test "wslact commands provide command-specific help" {
  for command in time-sync auto-mount memory-reclaim; do
    run out/wslact "$command" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Options:"* ]]
  done
}

@test "help explains parameter values and effects" {
  run out/wslview --help
  [[ "$output" == *"powershell    Windows Shell association through PowerShell"* ]]
  [[ "$output" == *"cmd_explorer  explorer.exe invoked directly"* ]]
  [[ "$output" == *"WSLVIEW_SKIP_VALIDATION_CHECK=1"* ]]
  [[ "$output" == *"requires Windows build 1903"* ]]

  run out/wslfetch --help
  [[ "$output" == *"Path to a trusted Bash file"* ]]
  [[ "$output" == *"windows-install-date"* ]]
  [[ "$output" == *"WSLFETCH_INFO_SECTION defaults to:"* ]]
  [[ "$output" == *"omitted values keep the generic defaults"* ]]

  run out/wslgsu --help
  [[ "$output" == *'"service NAME start"'* ]]
  [[ "$output" == *"Existing Linux user"* ]]
  [[ "$output" == *"two-minute delay"* ]]
  [[ "$output" == *"or Wakeup with --wakeup"* ]]

  run out/wslsys --help
  [[ "$output" == *"Valid names are:"* ]]

  run out/wslupath --help
  [[ "$output" == *"Windows shell-folder registry name"* ]]

  run out/wslusc --help
  [[ "$output" == *"Shell fragment run before COMMAND"* ]]
  [[ "$output" == *"WSLUSC_GUITYPE=legacy"* ]]
  [[ "$output" == *"Windows build 21332 or newer"* ]]

  run out/wslvar --help
  [[ "$output" == *"List environment names and values accepted by --sys"* ]]

  run out/wslclip --help
  [[ "$output" == *"When CONTENT is omitted and input is piped"* ]]
  [[ "$output" == *"clear the clipboard"* ]]

  run out/wslact auto-mount --help
  [[ "$output" == *'passed unchanged to "mount -t drvfs -o"'* ]]
}

@test "wslview browser export is idempotent" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  printf '%s\n' \
    'export BROWSER="/usr/bin/wslview"' \
    'export BROWSER="firefox"' \
    'export BROWSER="/usr/bin/wslview"' > "$HOME/.bashrc"
  printf '%s\n' 'setenv BROWSER firefox' > "$HOME/.cshrc"

  run out/wslview --export-as-browser --bogus
  [ "$status" -eq 22 ]
  run out/wslview --export-as-browser ""
  [ "$status" -eq 22 ]
  grep -Fxq 'export BROWSER="firefox"' "$HOME/.bashrc"

  run out/wslview --export-as-browser
  [ "$status" -eq 0 ]
  run out/wslview --export-as-browser
  [ "$status" -eq 0 ]

  [ "$(grep -Fxc 'export BROWSER="/usr/bin/wslview"' "$HOME/.bashrc")" -eq 1 ]
  grep -Fxq '#export BROWSER="firefox"' "$HOME/.bashrc"
  grep -Fxq 'setenv BROWSER firefox' "$HOME/.cshrc"
}

@test "wslusc rejects malformed options" {
  run out/wslusc --env 'export GDK_SCALE=2;' --help
  [ "$status" -eq 0 ]

  run out/wslusc --unknown
  [ "$status" -eq 22 ]

  run out/wslusc --env
  [ "$status" -eq 22 ]

  run out/wslusc --name --gui true
  [ "$status" -eq 22 ]
  run out/wslusc --icon --gui true
  [ "$status" -eq 22 ]
  run out/wslusc --env --gui true
  [ "$status" -eq 22 ]

  run out/wslusc --shortcut-debug --gui
  [ "$status" -eq 22 ]

  run out/wslusc --shortcut-debug=
  [ "$status" -eq 22 ]

  run out/wslusc --shortcut-debug one.lnk --shortcut-debug two.lnk
  [ "$status" -eq 22 ]

  mkdir -p "$BATS_TEST_TMPDIR/invalid-config"
  printf '%s\n' 'WSLUSC_GUITYPE=invalid' > "$BATS_TEST_TMPDIR/invalid-config/.wslurc"
  run env HOME="$BATS_TEST_TMPDIR/invalid-config" out/wslusc true
  [ "$status" -eq 22 ]

  printf '%s\n' 'WSLUSC_BASE_CONVERTER_ENGINE=invalid' > "$BATS_TEST_TMPDIR/invalid-config/.wslurc"
  run env HOME="$BATS_TEST_TMPDIR/invalid-config" out/wslusc true
  [ "$status" -eq 22 ]

  printf '%s\n' icon > "$BATS_TEST_TMPDIR/icon.unsupported"
  run out/wslusc --icon "$BATS_TEST_TMPDIR/icon.unsupported" true
  [ "$status" -eq 22 ]

  run out/wslusc --native true
  [ "$status" -eq 22 ]

  run out/wslusc --debug definitely-not-a-wslu-command --wait
  [ "$status" -eq 30 ]
  [[ "$output" == *"cname_header: definitely-not-a-wslu-command cname: --wait"* ]]
}

@test "wslfetch rejects missing option values" {
  run out/wslfetch --theme
  [ "$status" -eq 22 ]

  run out/wslfetch --options
  [ "$status" -eq 22 ]

  run out/wslfetch --theme --generic
  [ "$status" -eq 22 ]

  run out/wslfetch --theme=
  [ "$status" -eq 22 ]

  run out/wslfetch --options --generic
  [ "$status" -eq 22 ]

  run out/wslfetch --options=
  [ "$status" -eq 22 ]

  run out/wslfetch --theme "$BATS_TEST_TMPDIR/missing-theme"
  [ "$status" -eq 22 ]

  printf '%s\n' false > "$BATS_TEST_TMPDIR/broken-theme"
  run out/wslfetch --theme "$BATS_TEST_TMPDIR/broken-theme"
  [ "$status" -eq 22 ]

  run out/wslfetch --options unknown-field
  [ "$status" -eq 22 ]

  run out/wslfetch --options windows-build,,wsl-kernel
  [ "$status" -eq 22 ]

  run out/wslfetch --options windows-build,
  [ "$status" -eq 22 ]
}

@test "commands reject malformed options before side effects" {
  run out/wslgsu --bogus
  [ "$status" -eq 22 ]
  run out/wslgsu --user
  [ "$status" -eq 22 ]
  run out/wslgsu --name
  [ "$status" -eq 22 ]
  run out/wslgsu --user --wakeup
  [ "$status" -eq 22 ]
  run out/wslgsu --user=
  [ "$status" -eq 22 ]
  run out/wslgsu --name --service
  [ "$status" -eq 22 ]
  run out/wslgsu --name=
  [ "$status" -eq 22 ]
  run out/wslgsu --service --wakeup
  [ "$status" -eq 22 ]
  run out/wslgsu --user alice --wakeup
  [ "$status" -eq 22 ]
  run out/wslgsu --wakeup ""
  [ "$status" -eq 22 ]

  run out/wslact time-sync --bogus
  [ "$status" -eq 22 ]
  run out/wslact auto-mount --mount-options
  [ "$status" -eq 22 ]
  run out/wslact auto-mount --mount-options --help
  [ "$status" -eq 22 ]
  run out/wslact auto-mount -m --bogus
  [ "$status" -eq 22 ]
  run out/wslact memory-reclaim --bogus
  [ "$status" -eq 22 ]
  run out/wslact
  [ "$status" -eq 21 ]
  run out/wslact bogus
  [ "$status" -eq 22 ]
  run out/wslact ""
  [ "$status" -eq 22 ]
  run out/wslact time-sync ""
  [ "$status" -eq 22 ]
  run out/wslact auto-mount ""
  [ "$status" -eq 22 ]
  run out/wslact memory-reclaim ""
  [ "$status" -eq 22 ]

  run out/wslview --bogus
  [ "$status" -eq 22 ]
  run out/wslview --engine
  [ "$status" -eq 22 ]
  run out/wslview --engine invalid https://example.com
  [ "$status" -eq 22 ]
  run out/wslview --export-as-browser target
  [ "$status" -eq 22 ]
  run out/wslview --export-as-browser --skip-validation-check
  [ "$status" -eq 22 ]
  run out/wslview --export-as-browser --reg-as-browser
  [ "$status" -eq 22 ]
  run out/wslview https://example.com --bogus
  [ "$status" -eq 22 ]
  mkdir -p "$BATS_TEST_TMPDIR/invalid-view-config"
  printf '%s\n' 'WSLVIEW_SKIP_VALIDATION_CHECK=invalid' > "$BATS_TEST_TMPDIR/invalid-view-config/.wslurc"
  run env HOME="$BATS_TEST_TMPDIR/invalid-view-config" out/wslview https://example.com
  [ "$status" -eq 22 ]

  run out/wslsys --build --bogus
  [ "$status" -eq 22 ]
  run out/wslsys --name wsl-version --bogus
  [ "$status" -eq 22 ]
  run out/wslsys -n --build
  [ "$status" -eq 22 ]
  run out/wslsys -n 3
  [ "$status" -eq 22 ]
  run out/wslsys windows-build
  [ "$status" -eq 22 ]
  run out/wslsys 3
  [ "$status" -eq 22 ]

  run out/wslusc --shortcut-debug test.lnk --gui
  [ "$status" -eq 22 ]

  run out/wslclip -hvg
  [ "$status" -eq 22 ]
  run out/wslclip --get --bogus
  [ "$status" -eq 22 ]
  run out/wslclip --get content
  [ "$status" -eq 22 ]
  run out/wslclip --get ""
  [ "$status" -eq 22 ]
  run timeout 2 bash -c 'tail -f /dev/null | out/wslclip --get --bogus'
  [ "$status" -eq 22 ]
  run timeout 10 bash -c 'tail -f /dev/null | out/wslclip --get'
  [ "$status" -eq 0 ]

  run out/wslfetch stray
  [ "$status" -eq 22 ]
}

@test "explicit empty clipboard content does not consume stdin" {
  sed '/^# shellcheck shell=bash$/i winps_exec_stdin() { cat > "$TEST_INPUT"; printf "%s\\n" "$1" > "$TEST_LOG"; }' out/wslclip > "$BATS_TEST_TMPDIR/wslclip"
  chmod +x "$BATS_TEST_TMPDIR/wslclip"

  run bash -c 'printf piped | TEST_INPUT="$1" TEST_LOG="$2" "$3" ""' _ "$BATS_TEST_TMPDIR/input" "$BATS_TEST_TMPDIR/winps.log" "$BATS_TEST_TMPDIR/wslclip"
  [ "$status" -eq 0 ]
  [ ! -s "$BATS_TEST_TMPDIR/input" ]

  content='"; Write-Output INJECTED; "'
  run env TEST_INPUT="$BATS_TEST_TMPDIR/input" TEST_LOG="$BATS_TEST_TMPDIR/winps.log" "$BATS_TEST_TMPDIR/wslclip" "$content"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/input")" = "$content" ]
  run grep -Fq 'Write-Output INJECTED' "$BATS_TEST_TMPDIR/winps.log"
  [ "$status" -eq 1 ]
  grep -Fq 'Set-Clipboard -Value' "$BATS_TEST_TMPDIR/winps.log"
}

@test "PowerShell-bound values are encoded as data" {
  sed '/^# shellcheck shell=bash$/i wslu_get_build() { echo 26200; }\nwinps_exec() { printf "%s\\n" "$*" > "$TEST_LOG"; }' out/wslview > "$BATS_TEST_TMPDIR/wslview"
  sed '/^# shellcheck shell=bash$/i wslvar() { echo "C:\\\\Desktop"; }\nwinps_exec() { printf "%s\\n" "$*" > "$TEST_LOG"; }' out/wslusc > "$BATS_TEST_TMPDIR/wslusc-debug"
  sed '/^# shellcheck shell=bash$/i wslu_get_build() { echo 26200; }\nwslvar() { echo "C:\\\\Temp"; }\nwslpath() { echo "$TEST_TMP"; }\nwslu_file_check() { :; }\nwinps_exec() { printf "%s\\n" "$*" > "$TEST_LOG"; return 0; }\nrm() { :; }' out/wslgsu > "$BATS_TEST_TMPDIR/wslgsu-safe"
  sed '/^# shellcheck shell=bash$/i winps_exec() { printf "%s\\n" "$*" > "$TEST_LOG"; }' out/wslvar > "$BATS_TEST_TMPDIR/wslvar-safe"
  chmod +x "$BATS_TEST_TMPDIR/wslview" "$BATS_TEST_TMPDIR/wslusc-debug" "$BATS_TEST_TMPDIR/wslgsu-safe" "$BATS_TEST_TMPDIR/wslvar-safe"

  value='bad"; Write-Output INJECTED; "'

  run env TEST_LOG="$BATS_TEST_TMPDIR/view.log" "$BATS_TEST_TMPDIR/wslview" --skip-validation-check "https://example.com/$value"
  [ "$status" -eq 0 ]
  run grep -Fq 'Write-Output INJECTED' "$BATS_TEST_TMPDIR/view.log"
  [ "$status" -eq 1 ]
  grep -Fq 'FromBase64String' "$BATS_TEST_TMPDIR/view.log"

  run env TEST_LOG="$BATS_TEST_TMPDIR/shortcut.log" "$BATS_TEST_TMPDIR/wslusc-debug" --shortcut-debug "$value.lnk"
  [ "$status" -eq 0 ]
  run grep -Fq 'Write-Output INJECTED' "$BATS_TEST_TMPDIR/shortcut.log"
  [ "$status" -eq 1 ]
  grep -Fq 'FromBase64String' "$BATS_TEST_TMPDIR/shortcut.log"

  name="'}; Write-Output INJECTED; '"
  run env TEST_LOG="$BATS_TEST_TMPDIR/var.log" "$BATS_TEST_TMPDIR/wslvar-safe" --sys "$name"
  [ "$status" -eq 0 ]
  run grep -Fq 'Write-Output INJECTED' "$BATS_TEST_TMPDIR/var.log"
  [ "$status" -eq 1 ]
  grep -Fq 'FromBase64String' "$BATS_TEST_TMPDIR/var.log"

  run env TEST_LOG="$BATS_TEST_TMPDIR/var.log" "$BATS_TEST_TMPDIR/wslvar-safe" --shell "$name"
  [ "$status" -eq 0 ]
  run grep -Fq 'Write-Output INJECTED' "$BATS_TEST_TMPDIR/var.log"
  [ "$status" -eq 1 ]
  grep -Fq 'FromBase64String' "$BATS_TEST_TMPDIR/var.log"

  run env TEST_TMP="$BATS_TEST_TMPDIR" TEST_LOG="$BATS_TEST_TMPDIR/task.log" "$BATS_TEST_TMPDIR/wslgsu-safe" --name "$value" echo "$value"
  [ "$status" -eq 0 ]
  encoded_task=$(sed -n "s/.*-EncodedCommand '\([^']*\)'.*/\1/p" "$BATS_TEST_TMPDIR/task.log")
  [ -n "$encoded_task" ]
  printf %s "$encoded_task" | base64 -d | iconv -f UTF-16LE -t UTF-8 > "$BATS_TEST_TMPDIR/task.ps1"
  run grep -Fq 'Write-Output INJECTED' "$BATS_TEST_TMPDIR/task.ps1"
  [ "$status" -eq 1 ]
  grep -Fq 'FromBase64String' "$BATS_TEST_TMPDIR/task.ps1"
}

@test "Windows build requirements stop before side effects" {
  sed '/^# shellcheck shell=bash$/i wslu_get_build() { echo "$TEST_BUILD"; }' out/wslgsu > "$BATS_TEST_TMPDIR/wslgsu"
  sed '/^# shellcheck shell=bash$/i wslu_get_build() { echo "$TEST_BUILD"; }' out/wslusc > "$BATS_TEST_TMPDIR/wslusc"
  chmod +x "$BATS_TEST_TMPDIR/wslgsu" "$BATS_TEST_TMPDIR/wslusc"

  run env TEST_BUILD=10000 "$BATS_TEST_TMPDIR/wslgsu" --wakeup
  [ "$status" -eq 34 ]

  run env TEST_BUILD=invalid "$BATS_TEST_TMPDIR/wslgsu" --wakeup
  [ "$status" -eq 34 ]

  run env TEST_BUILD=999999999999999999999 "$BATS_TEST_TMPDIR/wslgsu" --wakeup
  [ "$status" -eq 34 ]

  run env TEST_BUILD=10000 "$BATS_TEST_TMPDIR/wslgsu" --debug echo -S
  [ "$status" -eq 34 ]
  [[ "$output" == *"isService: 0"* ]]
  [[ "$output" == *"wa_gs_commd: echo -S"* ]]

  run env TEST_BUILD=20000 "$BATS_TEST_TMPDIR/wslusc" --gui --native true
  [ "$status" -eq 35 ]

  run env TEST_BUILD=invalid "$BATS_TEST_TMPDIR/wslusc" --gui --native true
  [ "$status" -eq 35 ]

  run env TEST_BUILD=999999999999999999999 "$BATS_TEST_TMPDIR/wslusc" --gui --native true
  [ "$status" -eq 35 ]
}
