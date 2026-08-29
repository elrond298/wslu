#!/usr/bin/env bats

load test_helper

clipboard_text_base64() {
  "$WSLU_TEST_POWERSHELL" -NoProfile -NonInteractive -Command '$ErrorActionPreference="Stop"; Add-Type -AssemblyName System.Windows.Forms; $text=[System.Windows.Forms.Clipboard]::GetText(); [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))' | tr -d '\r\n'
}

restore_clipboard() {
  if [[ -n $saved_clipboard_base64 ]]; then
    printf %s "$saved_clipboard_base64" | base64 -d | out/wslclip
  else
    out/wslclip ""
  fi
}

setup() {
  require_windows_wsl
  clipboard_snapshot_ok=0
  run "$WSLU_TEST_POWERSHELL" -NoProfile -NonInteractive -Command '$ErrorActionPreference="Stop"; Add-Type -AssemblyName System.Windows.Forms; $data=[System.Windows.Forms.Clipboard]::GetDataObject(); if ($null -ne $data) { $allowed=@("Text","UnicodeText","System.String","Locale","OEMText"); $extra=@($data.GetFormats($false) | Where-Object { $_ -notin $allowed }); if ($extra.Count -gt 0) { exit 42 } }; $text=[System.Windows.Forms.Clipboard]::GetText(); [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))'
  if [[ $status -eq 42 ]]; then
    skip "clipboard contains non-text formats that cannot be restored losslessly"
  fi
  [ "$status" -eq 0 ]
  saved_clipboard_base64=${output//$'\r'/}
  saved_clipboard_base64=${saved_clipboard_base64//$'\n'/}
  clipboard_snapshot_ok=1
}

teardown() {
  if [[ ${clipboard_snapshot_ok:-0} -eq 1 ]]; then
    restore_clipboard
  fi
}

@test "clipboard round-trip restores the exact original text" {
  value="wslu-integration-${BATS_TEST_NUMBER}-$$"
  printf %s "$value" | out/wslclip
  run out/wslclip --get
  [ "$status" -eq 0 ]
  [ "${output//$'\r'/}" = "$value" ]

  restore_clipboard
  [ "$(clipboard_text_base64)" = "$saved_clipboard_base64" ]
  clipboard_snapshot_ok=0
}
