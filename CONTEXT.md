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
