# Remote open rides WSL↔WSL SSH, a reverse tunnel, and a web file server

`wslview --on` opens local files and directories on another machine's desktop. The
network may only assume WSL-instance-to-WSL-instance ssh (mirrored networking, so
host IP:port reaches the distro); Windows-to-Windows and WSL-to-Windows channels
are not assumed. We serve the files from a web file server on the originating
distro (loopback-bound, reachable only through tunnels we open) and reach it on
the target through an ssh reverse tunnel. Neither side attaches any filesystem.

## Considered Options

- **SSHFS-Win / WinFsp mount on the target's Windows side** — Explorer-native,
  but installs a third-party filesystem driver on the target and needs key setup
  pointing back at the origin. (An sshfs mount *inside* WSL is not an option:
  `\\wsl.localhost` does not proxy FUSE subtrees, so Explorer cannot open it.)
- **SMB re-export** (Samba in the target's WSL, or a Windows share for `/mnt/c`
  paths) — native Explorer behavior, but per-share admin and credential setup,
  and a second code path for non-NTFS paths.
- **WebDAV to the target's built-in WebClient** — zero installs, but Windows caps
  it at 50MB per file and 1MB per folder listing by default, with weak app
  compatibility.

Second decision in the same change: single **files** are copied to the target's
inbox and open (app)'d in their associated application; **directories** are
open (browse)'d in a web file server where each directory is registered on first
use and stays available. Copy-everything is slow for large trees; browse-everything
loses associated-application opening for files.

## Consequences

- Files clicked inside a browse view are previewed or downloaded in the browser,
  not launched in their associated app — accepted gap; a Windows-side mount
  remains the documented upgrade path if it ever bites.
- "Mount" and "host" are avoided in this feature's user-facing text; the vocabulary lives in
  CONTEXT.md.
