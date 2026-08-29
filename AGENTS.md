# AGENTS.md

## Scope and layout

- This is a Bash project for Windows Subsystem for Linux (WSL). The README marks it as discontinued, and `.github/PULL_REQUEST_TEMPLATE.md` says breaking changes are no longer accepted.
- Edit utility implementations in `src/<utility>.sh`. `src/wslu-header` provides the shared runtime, variables, and functions; `make` prepends it to every utility and writes executables to `out/`.
- Shared installed resources live in `src/etc/`. `src/etc/conf` is the packaged default configuration; `src/etc/user/conf` is the user override template.
- Bats tests are split by effect: hermetic tests in `tests/fast/`, automated Windows/WSL tests in `tests/integration/`, and explicitly disruptive tests in `tests/manual/`. Shared fakes and helpers live directly under `tests/`. Manpage sources are `docs/<utility>.1` and `docs/wslu.7`.
- Packaging definitions and helper scripts are under `extras/build/`; packaging CI also relies on external builder repositories. Do not treat packaging as part of the normal local verification path.

## Generated files and hazardous commands

- Do not edit or commit `out/` or `out-docs/`; both are generated and ignored. Rebuild with `make`, and remove them with `make clean`.
- Do not run `./configure.sh` without an argument or with `-P`/`--pkg`: it invokes distro package managers through `sudo` and may remove an installed `wslu` package.
- Avoid `configure.sh --build`, `--deb`, and `--rpm` during ordinary development. They mutate tracked header or packaging templates, and RPM preparation creates archives/directories outside the checkout.
- `make install`, `make res_install`, and `make uninstall` write to system locations by default (`PREFIX=/usr`) and may remove installed files. Use them only in an explicitly disposable environment with an intentional `DESTDIR`/`PREFIX`.

## Verification

Prerequisites for the normal checks are Bash, GNU Make, gzip, ShellCheck, and Bats.

```bash
make shellcheck             # repository lint command; uses .shellcheckrc
make                        # builds out/* and compressed manpages in out-docs/
make test                   # hermetic tests; safe on ordinary Linux or WSL
```

There is no repository formatter or type-checker task. Do not invent one.

Use the smallest relevant fast Bats file after building:

```bash
make
bats tests/fast/wslact.bats
bats tests/fast/header.bats
```

`make test-integration` runs bounded, non-interactive tests against real PowerShell, CMD, registry, `wslpath`, clipboard, and temporary shortcut files. Run it in Windows-hosted WSL; tests must clean their artifacts and must not open applications or write the real Desktop.

`make test-manual` is guarded by `WSLU_RUN_MANUAL_TESTS=1` and may open Windows applications, write Desktop shortcuts, request UAC, change time, mount drives, or drop caches. Run it only in an explicitly disposable environment.

## Change rules

- Keep shared behavior in `src/wslu-header`; changes there affect every generated executable.
- Change source files, not their concatenated copies in `out/`.
- Preserve LF line endings. The Windows CI job explicitly disables Git CRLF conversion before checkout.
- For public command behavior, keep the corresponding Bats file and manpage source aligned. See `CONTRIBUTING.md` for the documented shared header API and build targets.
- Do not place credentials in scripts or workflows. Deployment workflows consume repository secrets such as package and hosting tokens; never replace those secret references with literal values or print them.

## Completion criteria

- The change is non-breaking.
- `make shellcheck` passes.
- `make` and `make test` pass.
- Run `make test-integration` when the change affects shared header behavior or Windows interoperability; otherwise state clearly that the Windows-hosted suite was not run.
- Only source, tests, manpage/configuration sources, and other intentional files are changed; generated output and configure-script side effects are absent.
