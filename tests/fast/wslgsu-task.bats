#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_fake_windows
  make_instrumented_command wslgsu \
    'wslu_get_build() { echo 22631; }; wslvar() { case "$*" in *TMP*) echo "C:\\Temp";; *USERPROFILE*) echo "C:\\Users\\Test";; esac; }; wslpath() { echo "$BATS_TEST_TMPDIR"; }; wslu_file_check() { :; }; winps_exec() { printf "%s\n" "$*" > "$WSLU_TEST_LOG"; }' \
    "$BATS_TEST_TMPDIR/wslgsu"
}

@test "wslgsu generates complete bounded scheduled task" {
  run "$BATS_TEST_TMPDIR/wslgsu" --user alice --name Backup echo hello
  [ "$status" -eq 0 ]
  encoded=$(sed -n "s/.*-EncodedCommand '\([^']*\)'.*/\1/p" "$WSLU_TEST_LOG")
  [ -n "$encoded" ]
  printf %s "$encoded" | base64 -d | iconv -f UTF-16LE -t UTF-8 > "$BATS_TEST_TMPDIR/task.ps1"
  grep -Fq 'New-ScheduledTaskAction' "$BATS_TEST_TMPDIR/task.ps1"
  grep -Fq 'New-ScheduledTaskTrigger -AtLogOn' "$BATS_TEST_TMPDIR/task.ps1"
  grep -Fq "Delay = 'PT2M'" "$BATS_TEST_TMPDIR/task.ps1"
  grep -Fq 'AllowStartIfOnBatteries' "$BATS_TEST_TMPDIR/task.ps1"
  grep -Fq 'Register-ScheduledTask' "$BATS_TEST_TMPDIR/task.ps1"
  decoded=$(grep -oE "FromBase64String\('[A-Za-z0-9+/=]+'\)" "$BATS_TEST_TMPDIR/task.ps1" | sed -e "s/^FromBase64String('//" -e "s/')$//" | while read -r value; do printf %s "$value" | base64 -d; printf '\n'; done)
  [[ "$decoded" == *'wsl.exe -d "TestDistro" -u "alice" echo hello'* ]]
  [[ "$decoded" == *'WSLUtilities_Actions_Startup_Backup_'* ]]
}
