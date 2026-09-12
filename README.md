<div align="center">

<img width="150" height="150" src="extras/icon.png">

# wslu - A collection of utilities for WSL

[![GitHub license](https://img.shields.io/github/license/wslutilities/wslu?style=flat-square&label=license&color=blue&logo=github)](https://github.com/wslutilities/wslu/blob/master/LICENSE)
[![GitHub (pre-)release](https://img.shields.io/github/v/release/wslutilities/wslu?include_prereleases&logo=github&style=flat-square)](https://github.com/wslutilities/wslu)
[![Mastodon Follow](https://img.shields.io/mastodon/follow/108802672885079993?color=6364FF&domain=https%3A%2F%2Ffosstodon.org&label=follow&logo=mastodon&logoColor=6364FF&style=flat-square)](https://fosstodon.org/@wslutilities)

</div>

> [!IMPORTANT]
> This is a self-use repository maintained for the author's own needs.
This is a collection of utilities for the Windows Subsystem for Linux (WSL), such as converting Linux paths to Windows paths or creating Linux application shortcuts on the Windows Desktop.

- Requires at least Windows 10 Creators Update;
- Some of the features require a higher version of Windows;
- Supports WSL2;
- Supports Windows 11.


## Installation

Install this repository directly from source inside WSL:

```bash
git clone https://github.com/wslutilities/wslu.git
cd wslu
make
sudo make install
```

The build requires Bash, GNU Make, and gzip. By default, executables are installed in `/usr/bin`, manpages in `/usr/share/man`, shared resources in `/usr/share/wslu`, and configuration in `/etc/wslu`.

- `PREFIX` changes the installation prefix for executables and shared files. For example, `PREFIX=/usr/local` installs them under `/usr/local/bin` and `/usr/local/share`; configuration remains under `/etc/wslu`.
- `DESTDIR` prepends a staging root to every installed path. It is intended for building a package or inspecting the install tree without modifying the system.

Use the same values for both the build and install steps because they are embedded in the generated scripts.

Install under `/usr/local`:

```bash
make clean
make PREFIX=/usr/local
sudo make PREFIX=/usr/local install
```

Stage a package tree under `stage/` without `sudo`:

```bash
make clean
make PREFIX=/usr DESTDIR="$PWD/stage"
make PREFIX=/usr DESTDIR="$PWD/stage" install
```

This creates `stage/usr/bin`, `stage/usr/share`, and `stage/etc/wslu`.

To update an existing checkout:

```bash
git pull
make clean
make
sudo make install
```

## Guide

After installation, run `man 7 wslu` for the overview, `man 1 <command>` for a command's complete options, or `<command> --help` for a short summary.

| Command | Purpose | Manual |
| --- | --- | --- |
| `wslact` | Run WSL actions such as time synchronization, drive mounting, and memory reclamation. | [`docs/wslact.1`](docs/wslact.1) |
| `wslclip` | Read from or write to the Windows clipboard without X or Wayland. | [`docs/wslclip.1`](docs/wslclip.1) |
| `wslfetch` | Display WSL and Windows system information. | [`docs/wslfetch.1`](docs/wslfetch.1) |
| `wslgsu` | Create WSL startup tasks with Windows Task Scheduler. | [`docs/wslgsu.1`](docs/wslgsu.1) |
| `wslnotify` | Send Windows toast notifications from WSL. | [`docs/wslnotify.1`](docs/wslnotify.1) |
| `wsldoctor` | Check the WSL environment wslu depends on and suggest or apply fixes. | [`docs/wsldoctor.1`](docs/wsldoctor.1) |
| `wslsys` | Print WSL and Windows system information. | [`docs/wslsys.1`](docs/wslsys.1) |
| `wslusc` | Create Windows Desktop shortcuts for WSL commands. | [`docs/wslusc.1`](docs/wslusc.1) |
| `wslvar` | Read Windows environment and shell-folder variables. | [`docs/wslvar.1`](docs/wslvar.1) |
| `wslview` | Open URLs, files, and folders with Windows applications. Aliases: `wview`, `wslstart`, and `wstart`. | [`docs/wslview.1`](docs/wslview.1) |
| `wslupath` | Convert between Windows and WSL path forms. Deprecated. | [`docs/wslupath.1`](docs/wslupath.1) |

All commands accept `--debug` and `--verbose` through the shared wslu header.

### Configuration

The installed defaults are in `/usr/share/wslu/conf`. Override them, in load order, with `/etc/wslu/conf`, `/etc/wslu/custom.conf`, `$HOME/.config/wslu/conf`, or `$HOME/.wslurc`. See [`src/etc/conf`](src/etc/conf) for available settings and each command's manpage for command-specific behavior.

## Contributors

This project exists thanks to all the people who contribute. [ [Contribute](CONTRIBUTING.md) ].
<img src="https://opencollective.com/wslu/contributors.svg?width=890&button=false" />

## License & Credits

<img width="150" src="https://www.gnu.org/graphics/gplv3-with-text-136x68.png">

This project uses [GPLv3](LICENSE) License.

Logo of WSL Utilities and icons for `wslusc` desktop shortcuts are licensed under [CC BY 4.0 International License](http://creativecommons.org/licenses/by/4.0/).

For other third-party files and assets used, please refer to [THIRD_PARTY_LICENSE](THIRD_PARTY_LICENSE).
