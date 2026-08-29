#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_fake_windows
  overrides='get_install_date() { echo 1700000000; }; get_branch() { echo ni_release; }; get_build() { echo 22631; }; get_full_build() { echo 22631.1.amd64fre; }; get_display_scaling() { echo 1.25; }; get_windows_locale() { echo en_US; }; get_theme() { echo dark; }; get_windows_uptime() { echo "2d 3h 4m"; }; get_wsl_version() { echo 2; }; get_wsl_uptime() { echo "1d 2h 3m"; }; get_wsl_release() { echo TestLinux; }; get_wsl_kernel() { echo "Linux 6.6-test"; }; get_wsl_packages() { echo 42; }; get_wsl_ip() { echo 192.0.2.2; }; get_win_system_type() { echo Desktop; }; get_systemd() { echo enabled; }'
  sed "/^# pre-handler$/i $overrides" out/wslsys > "$BATS_TEST_TMPDIR/wslsys"
  chmod +x "$BATS_TEST_TMPDIR/wslsys"
}

@test "wslsys maps every symbolic field to its getter" {
  while IFS='|' read -r name expected; do
    run "$BATS_TEST_TMPDIR/wslsys" --name "$name" -s
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
  done <<'EOF'
windows-install-date|1700000000
windows-rel-branch|ni_release
windows-build|22631
windows-full-build|22631.1.amd64fre
display-scaling|1.25
windows-locale|en_US
windows-theme|dark
windows-uptime|2d 3h 4m
wsl-version|2
wsl-uptime|1d 2h 3m
wsl-release|TestLinux
wsl-kernel|Linux 6.6-test
wsl-package-count|42
wsl-ip|192.0.2.2
win-system-type|Desktop
wsl-systemd-status|enabled
EOF
}

@test "wslsys labels fields and rejects getter failures" {
  run "$BATS_TEST_TMPDIR/wslsys" --win-theme
  [ "$status" -eq 0 ]
  [ "$output" = "Theme (Windows): dark" ]

  sed '/^# pre-handler$/i get_theme() { return 1; }' "$BATS_TEST_TMPDIR/wslsys" > "$BATS_TEST_TMPDIR/wslsys-fail"
  chmod +x "$BATS_TEST_TMPDIR/wslsys-fail"
  run "$BATS_TEST_TMPDIR/wslsys-fail" --name windows-theme -s
  [ "$status" -eq 22 ]
  [[ "$output" == *"Invalid input."* ]]
}
