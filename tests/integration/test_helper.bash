integration_unavailable() {
  if [[ ${CI:-} == true ]]; then
    printf 'Windows integration unavailable in CI: %s\n' "$1" >&2
    return 1
  fi
  skip "$1"
}

require_windows_wsl() {
  if [[ -z ${WSL_INTEROP:-} ]] && ! grep -qi microsoft /proc/sys/kernel/osrelease /proc/version 2>/dev/null; then
    integration_unavailable "requires WSL on Windows"
    return $?
  fi
  local system32
  for system32 in /mnt/*/Windows/System32; do
    if [[ -x "$system32/WindowsPowerShell/v1.0/powershell.exe" && -x "$system32/cmd.exe" ]]; then
      export WSLU_TEST_SYSTEM32="$system32"
      export WSLU_TEST_POWERSHELL="$system32/WindowsPowerShell/v1.0/powershell.exe"
      export WSLU_TEST_CMD="$system32/cmd.exe"
      export PATH="$PWD/out:$PATH"
      return
    fi
  done
  integration_unavailable "Windows System32 executables are unavailable"
}
