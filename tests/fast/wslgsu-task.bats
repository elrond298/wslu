#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_fake_windows
  make_instrumented_command wslgsu \
    'wslu_get_build() { echo 22631; }; wslvar() { case "$*" in *TMP*) printf "%s\n" "C:\Temp";; *USERPROFILE*) printf "%s\n" "C:\Users\Test";; esac; }; wslpath() { if [[ $1 == -w ]]; then printf "%s\n" "C:\Windows\System32"; else echo "$BATS_TEST_TMPDIR"; fi; }; wslu_file_check() { :; }; winps_exec() { printf "%s\n" "$*" > "$WSLU_TEST_LOG"; }' \
    "$BATS_TEST_TMPDIR/wslgsu"
}

extract_task() {
  encoded=$(sed -n "s/.*-EncodedCommand '\([^']*\)'.*/\1/p" "$WSLU_TEST_LOG")
  [ -n "$encoded" ]
  printf %s "$encoded" | base64 -d | iconv -f UTF-16LE -t UTF-8 > "$BATS_TEST_TMPDIR/task.ps1"
}

decode_task_values() {
  grep -oE "FromBase64String\('[A-Za-z0-9+/=]+'\)" "$BATS_TEST_TMPDIR/task.ps1" |
    sed -e "s/^FromBase64String('//" -e "s/')$//" |
    while read -r value; do printf %s "$value" | base64 -d; printf '\n'; done
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
  grep -Fq "Import-Module 'C:\Windows\System32\WindowsPowerShell" "$BATS_TEST_TMPDIR/task.ps1"
  grep -Fq -- "-Execute 'C:\Windows\System32\wscript.exe'" "$BATS_TEST_TMPDIR/task.ps1"
  decoded=$(grep -oE "FromBase64String\('[A-Za-z0-9+/=]+'\)" "$BATS_TEST_TMPDIR/task.ps1" | sed -e "s/^FromBase64String('//" -e "s/')$//" | while read -r value; do printf %s "$value" | base64 -d; printf '\n'; done)
  [[ "$decoded" == *'wsl.exe -d "TestDistro" -u "alice" echo hello'* ]]
  [[ "$decoded" == *'WSLUtilities_Actions_Startup_Backup_'* ]]
}

@test "wslgsu constructs service and wakeup tasks" {
  run "$BATS_TEST_TMPDIR/wslgsu" --service --user daemon ssh
  [ "$status" -eq 0 ]
  extract_task
  decoded=$(decode_task_values)
  [[ "$decoded" == *'wsl.exe -d "TestDistro" -u "daemon" service "ssh" start'* ]]
  [[ "$decoded" == *'WSLUtilities_Actions_Startup_ssh_'* ]]

  run "$BATS_TEST_TMPDIR/wslgsu" --wakeup
  [ "$status" -eq 0 ]
  extract_task
  decoded=$(decode_task_values)
  [[ "$decoded" == *'wsl.exe -d "TestDistro" echo'* ]]
  [[ "$decoded" == *'WSLUtilities_Actions_Startup_Wakeup_'* ]]
}

@test "wslgsu propagates elevation failure" {
  make_instrumented_command wslgsu \
    'wslu_get_build() { echo 22631; }; wslvar() { echo "C:\Users\Test"; }; wslpath() { echo "$BATS_TEST_TMPDIR"; }; wslu_file_check() { :; }; winps_exec() { return 9; }' \
    "$BATS_TEST_TMPDIR/wslgsu-fail"
  run "$BATS_TEST_TMPDIR/wslgsu-fail" echo hello
  [ "$status" -eq 1 ]
  [[ "$output" == *'Adding Task "echo" failed.'* ]]
}
