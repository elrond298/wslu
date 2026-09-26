# wslu

Utilities for Windows Subsystem for Linux. This glossary pins the domain language shared across utilities, tests, and manpages.

## Services

**Windows service**:
A program managed by the Windows Service Control Manager; the object `wslsvc` reads and controls.
_Avoid_: service (unqualified), daemon

**Linux service**:
A program running inside the WSL distro, managed by `wslgsu`. Outside `wslsvc`'s reach.
_Avoid_: service (unqualified)

**service name**:
The unique canonical identifier of a Windows service, e.g. `Spooler`.
_Avoid_: id, key

**display name**:
The human-readable label of a Windows service, e.g. `Print Spooler`. Not guaranteed unique.
_Avoid_: title, label

**state**:
The runtime condition of a Windows service: Running, Stopped, Paused, and related values. The exact PowerShell values `wslsvc` surfaces are Running, Stopped, StartPending, StopPending, Paused, ContinuePending, and PausePending.
_Avoid_: status — `status` names the subcommand that reports state; as a field name it is ambiguous

**start type**:
The boot configuration of a Windows service: Automatic, Manual, or Disabled. A different axis from state.
_Avoid_: enabled/disabled (conflates with state), systemd's "enabled"

**restart**:
An operation consisting of stop followed by start, regardless of the service's current state.

**ambiguous match**:
Service input that resolves to more than one Windows service by name or display name.

## Remote open

**target**:
The machine where remote opens land, addressed by an ssh alias that reaches its WSL instance.
_Avoid_: host (reserved for hostnames), machine, remote

**share root**:
A directory exposed by the file server for remote browsing, registered automatically on first open and dropped when the file server stops.
_Avoid_: mount point, export, share

**inbox**:
The directory on a target where files copied for open (app) land.
_Avoid_: staging area, cache, downloads

**open (app)**:
An open that launches the file's associated Windows application on the target's desktop.
_Avoid_: open (unqualified), mount

**open (browse)**:
An open that shows a directory listing in a web file browser on the target.
_Avoid_: open (unqualified), mount
