# Development

How to work on Banchy OS: build the ISO, run the tooling, and keep changes
safe. Read [ARCHITECTURE.md](ARCHITECTURE.md) first if you are new to the
repository.

## Prerequisites

- **ISO build**: Arch Linux, or Docker with a privileged container
  (`archlinux:base-devel`) and `archiso`.
- **Lint/tests**: `shellcheck`, `bash`, `python` (for `py_compile`), plus the
  repo scripts.
- **VM smoke**: QEMU with OVMF firmware and `expect`.

## Repository map (developer view)

```
cli/         banchy entrypoint, lib/*.sh modules, bin/ helper scripts
installer/   banchy-install (TUI + unattended), lib/ helpers
boot/        systemd-boot entry templates, pacman hooks, recovery assets
themes/      5 themes + templates/*.tmpl ({{KEY}} render templates)
configs/     default user configs (hypr/, waybar/, kitty/, fuzzel/, mako/, ...)
packages/    packages/profiles/*.list (one per profile)
iso/         archiso profile: iso/profile/{profiledef.sh, airootfs/, efiboot/}
scripts/     build-iso.sh, install-files.sh, test-vm.sh,
             lint.sh, gen-wallpapers.ps1
first-run/   banchy-welcome wizard
apps/        banchy-settings (Python/GTK4), banchy-cc
tests/       unit/smoke suites (boot/, configs/, themes/, packages/,
             integration/, vm/)
wallpapers/  shipped PNGs (generated from wallpapers/src)
branding/    logo SVG, ASCII logo, brand assets
docs/        documentation
```

## Building the ISO

`scripts/build-iso.sh` requires Arch Linux or a privileged Docker container
(`archlinux:base-devel`) with `archiso` installed.

On Arch Linux:

```bash
scripts/build-iso.sh
```

Anywhere with Docker:

```bash
docker run --rm --privileged -v "$PWD":/src -w /src archlinux:base-devel \
  bash -c "pacman -Syu --noconfirm archiso && scripts/build-iso.sh"
```

Output: `out/banchy-os-*.iso`.

Related scripts:

| Script | Purpose |
| --- | --- |
| `scripts/build-iso.sh` | Build the ISO with `mkarchiso` from the `iso/profile/` profile (stages the live system first) |
| `scripts/install-files.sh` | Install repo files to their target locations (used by installer/staging) |
| `scripts/gen-wallpapers.ps1` | Generate wallpaper PNGs from `wallpapers/src` |
| `scripts/lint.sh` | shellcheck + `bash -n` + `py_compile` + theme validation |
| `scripts/test-vm.sh` | QEMU + OVMF boot smoke test (serial console via `scripts/vm-smoke.exp`), logs to `test-results/` |

## Lint and tests

```bash
scripts/lint.sh          # must be clean before opening a PR
tests/run.sh            # unit/smoke suites
```

On a live or installed system:

```bash
banchy-test boot|desktop|configs|full
```

VM-level:

```bash
scripts/test-vm.sh
```

Details and the release-gate table: [TESTING.md](TESTING.md).

## Working on the CLI

```
cli/
├── banchy          # entrypoint (set -euo pipefail, dispatches to lib/)
├── lib/*.sh        # one module per command family (theme, config, boot, ...)
└── bin/            # standalone helper scripts
```

Conventions:

- `set -euo pipefail` in every script; shellcheck-clean.
- Colorized `[OK]` / `[WARN]` / `[FAIL]` output; append messages to
  `~/.local/state/banchy/banchy.log`.
- Validate before acting; back up before overwriting; support rollback.
- Never run destructive commands without confirmation (or an explicit
  non-interactive flag documented in `--help`).
- Managed files carry the marker comment; honor `--force` only when given.

## Working on themes

- Edit `themes/<name>/theme.conf` and/or `themes/templates/*.tmpl`, then:

  ```bash
  banchy theme validate <name>
  scripts/lint.sh
  ```

- Never commit generated files — they are produced by `banchy apply`.
- Render order: staging → validate (no unresolved `{{...}}`, valid hex) →
  atomic swap → `hyprctl` verify → rollback on failure.

See the theme section of [CONTRIBUTING.md](../CONTRIBUTING.md) and
[CUSTOMIZATION.md](CUSTOMIZATION.md).

## Working on the installer

- TUI flow and unattended mode live in `installer/` with shared helpers in
  `installer/lib/`.
- The verify gate must stay complete: root fs, EFI/ESP, fstab, kernel,
  initramfs, bootloader entries, network (NetworkManager), user + sudo,
  display stack (Hyprland, waybar, portal).
- Reboot is offered only when verification passes (explicit override prints
  warnings).
- Installer log: `/var/log/banchy-install.log`.
- Keep `tests/` installer syntax checks passing.

Details: [INSTALLATION.md](INSTALLATION.md).

## CI

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `ci.yml` | push / PR | `scripts/lint.sh` + `tests/run.sh` |
| `iso.yml` | push, tag `v*` | Build ISO (privileged archlinux container, `mkarchiso`) → QEMU serial smoke test → on `v*`: GitHub Release with `banchy-os-x86_64.iso` + `.sha256` |

A release is only published when **all** release gates pass (see
[TESTING.md](TESTING.md)).

## Versioning and releases

- Current version: `0.2.0` (see the `version` file).
- Rolling base on Arch Linux; the project itself uses tagged releases.
- Changelog: [../CHANGELOG.md](../CHANGELOG.md), Keep-a-Changelog format,
  short imperative commit subjects.

## Further reading

- [ARCHITECTURE.md](ARCHITECTURE.md) — components and pipelines
- [BOOT.md](BOOT.md) — Banchy Boot internals
- [RECOVERY.md](RECOVERY.md) — recovery flows
- [ROADMAP.md](ROADMAP.md) — phase status
- [../CONTRIBUTING.md](../CONTRIBUTING.md) — PR workflow and style rules
