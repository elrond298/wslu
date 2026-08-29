#!/usr/bin/env bats

load test_helper

setup() {
  require_windows_wsl
  export REAL_WSLVAR="$PWD/out/wslvar"
  temp_win=$(out/wslvar --sys TEMP | tr -d '\r')
  export TEST_DESKTOP_WIN="$temp_win\\wslu-integration-${BATS_TEST_NUMBER}-$$"
  export TEST_DESKTOP_LINUX
  TEST_DESKTOP_LINUX=$(wslpath "$TEST_DESKTOP_WIN")
  mkdir -p "$TEST_DESKTOP_LINUX" "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/wslvar" <<'EOF'
#!/bin/bash
if [[ $1 == -l || $1 == --shell ]] && [[ $2 == Desktop ]]; then
  printf '%s\n' "$TEST_DESKTOP_WIN"
else
  exec "$REAL_WSLVAR" "$@"
fi
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/wslvar"
  export PATH="$BATS_TEST_TMPDIR/bin:$PWD/out:$PATH"
}

teardown() {
  rm -rf "${TEST_DESKTOP_LINUX:-}"
}

@test "real COM shortcut is created and inspected outside Desktop" {
  run out/wslusc --name WsluIntegration printf '%s' 'argument with spaces'
  [ "$status" -eq 0 ]
  shortcut="$TEST_DESKTOP_LINUX/WsluIntegration.lnk"
  [ -f "$shortcut" ]

  encoded_shortcut=$(printf %s "$(wslpath -w "$shortcut")" | base64 | tr -d '\n')
  run "$WSLU_TEST_POWERSHELL" -NoProfile -NonInteractive -Command "\$p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded_shortcut')); \$s=(New-Object -ComObject WScript.Shell).CreateShortcut(\$p); \$s.TargetPath; \$s.Arguments; \$s.IconLocation"
  [ "$status" -eq 0 ]
  [[ "$output" == *printf* ]]
  encoded_command=$(printf '%s\n' "$output" | sed -n "s/.*printf %s '\([^']*\)'.*/\1/p")
  [ -n "$encoded_command" ]
  decoded_command=$(printf %s "$encoded_command" | base64 -d)
  [[ "$decoded_command" == *'printf %s argument\ with\ spaces'* ]]
}
