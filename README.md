# Banchy OS

![License: MIT](https://img.shields.io/badge/license-MIT-blue)
![Based on: Arch Linux](https://img.shields.io/badge/base-Arch%20Linux-1793d1)
![Version: 0.1.1](https://img.shields.io/badge/version-0.1.1-green)

**Banchy OS** is an Arch Linux based distribution built around Hyprland. It ships a
complete, themed desktop with a first-class CLI (`banchy`), a safe boot setup, an
interactive installer, and an ISO you can flash and go.

Rolling release on Arch Linux. Code licensed MIT (copyright Banchy OS Contributors).

## Principles

Fast, Minimal, Beautiful, Customizable, Stable, Developer Friendly.

Core rule: **stability > maintainability > usability > performance hacks.**
Every critical change gets validation, backup, fallback, and rollback.

## Feature highlights

- **`banchy` CLI** — `update`, `doctor`, `info`, `theme`, `package`, `profile`,
  `config`, `boot`, `keys`, `apply`, `welcome`, `recovery`, and more. Colorized
  `[OK]` / `[WARN]` / `[FAIL]` output, logs to `~/.local/state/banchy/banchy.log`.
- **Theme Engine** — 5 built-in themes rendered from `{{KEY}}` templates into
  Hyprland, Waybar, kitty, fuzzel, mako, hyprlock, hyprpaper, and GTK. Staging →
  validate → atomic swap → verify → rollback on failure.
- **`banchy-settings`** — Python/GTK4 GUI (Appearance, Wallpapers, Waybar, Fonts,
  Monitors, About). Every change goes through `banchy set` then `banchy apply`,
  so CLI validation always applies.
- **Banchy Boot** — systemd-boot menu with a main entry, an always-installed
  previous-kernel fallback, and a recovery entry. Pacman hooks back up loader
  config before upgrades; `banchy boot check` / `repair` / `install` keep it sane.
- **Profiles** — `minimal`, `default`, `developer`, `creator`, `gaming`, `full`.
  Large packages are only installed on explicit choice.
- **Installer** — whiptail TUI or fully unattended (`--unattended answers.conf`),
  with a verify gate that must pass before reboot is offered.

## Quick start

1. Download the ISO from the
   [releases page](https://github.com/pinkyguy2323/banchy-os/releases)
   (direct: `banchy-os-x86_64.iso`).
2. Verify the checksum:

   ```bash
   sha256sum -c banchy-os-x86_64.iso.sha256
   ```

3. Flash it to a USB drive and boot it — the ISO boots in **UEFI** and legacy
   **BIOS** mode (installing the system currently requires UEFI; see
   [docs/INSTALLATION.md](docs/INSTALLATION.md)).
4. Run the installer from the live environment:

   ```bash
   banchy-install
   ```

5. Reboot when the verification step passes.

More detail: [docs/INSTALLATION.md](docs/INSTALLATION.md).

## Keybindings

| Keys | Action |
| --- | --- |
| `SUPER+Return` | Terminal (kitty) |
| `SUPER+Space` | Launcher (fuzzel) |
| `SUPER+E` | Files (thunar) |
| `SUPER+B` | Chromium |
| `SUPER+C` | Visual Studio Code |
| `SUPER+O` | Obsidian |
| `SUPER+Q` | Close window |
| `SUPER+1..9` | Switch workspace |
| `SUPER+Shift+1..9` | Move window to workspace |
| `SUPER+Shift+S` | Screenshot region (grim + slurp) |
| `SUPER+Ctrl+R` | Reload Hyprland |
| `SUPER+L` | Lock (hyprlock) |
| `SUPER+N` | Control center (banchy-cc) |
| `SUPER+P` | Settings (banchy-settings) |
| `SUPER+K` | Show keybindings |
| `SUPER+V` | Toggle floating |
| `SUPER+F` | Fullscreen |
| `SUPER+Shift+X` | Power menu |

Mouse bindings are also configured. On an installed system, run `banchy keys`
to pretty-print the full list.

## Project structure

```
banchy-os/
├── installer/   # Banchy Installer (TUI + unattended) and lib/ helpers
├── iso/         # archiso profile (iso/profile: profiledef.sh, airootfs, efiboot)
├── packages/    # package profile lists (packages/profiles/*.list)
├── configs/     # default user configs (hypr/, waybar/, kitty/, fuzzel/, ...)
├── themes/      # 5 theme definitions + templates/ render templates
├── boot/        # Banchy Boot: loader entry templates, pacman hooks, recovery
├── scripts/     # build/lint/test automation
├── first-run/   # banchy-welcome first-run wizard
├── apps/        # banchy-settings (Python/GTK4), banchy-cc control center
├── cli/         # banchy CLI: entrypoint + lib/*.sh + bin/ helpers
├── wallpapers/  # shipped wallpapers (PNG, generated from wallpapers/src)
├── branding/    # logo SVG, ASCII logo, brand assets
├── tests/       # smoke/unit tests
├── docs/        # documentation
└── .github/     # CI: lint+tests, ISO build, VM smoke, release
```

Full walkthrough: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Build from source

The ISO build requires Arch Linux or a privileged Docker container with
`archiso` installed:

```bash
docker run --rm --privileged -v "$PWD":/src -w /src archlinux:base-devel \
  bash -c "pacman -Syu --noconfirm archiso && scripts/build-iso.sh"
```

Output: `out/banchy-os-*.iso`. On a real Arch system, run
`scripts/build-iso.sh` directly. Details: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Testing

```bash
scripts/lint.sh          # shellcheck + bash -n + python py_compile + theme validation
tests/run.sh       # unit/smoke tests
banchy-test full         # on a live or installed system
scripts/test-vm.sh       # QEMU + OVMF boot smoke test (serial console)
```

CI runs lint and unit tests on every push/PR, builds the ISO, and smoke-tests it
in QEMU. See [docs/TESTING.md](docs/TESTING.md).

## Recovery quick reference

1. At the **Banchy Boot** menu choose **Banchy OS — Recovery**
   (boots `systemd.unit=rescue.target` to a root shell).
2. Run the recovery TUI:

   ```bash
   banchy-recovery
   ```

   It offers filesystem check, bootloader repair, initramfs regeneration,
   pacman DB verification, network restore, config restore, Btrfs snapshot
   restore, a shell, and reboot.

3. Back in the system: `banchy boot repair`, `banchy config restore`,
   `banchy doctor`.

Details: [docs/RECOVERY.md](docs/RECOVERY.md).

## Documentation

| Document | Contents |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Repo layout, components, render pipeline |
| [docs/INSTALLATION.md](docs/INSTALLATION.md) | TUI and unattended install, verify gate |
| [docs/BOOT.md](docs/BOOT.md) | Banchy Boot, entries, safety hooks |
| [docs/RECOVERY.md](docs/RECOVERY.md) | Recovery entry and `banchy-recovery` |
| [docs/CUSTOMIZATION.md](docs/CUSTOMIZATION.md) | Themes, settings keys, keybindings |
| [docs/TESTING.md](docs/TESTING.md) | Lint, tests, VM smoke, CI, release gates |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Building the ISO, dev workflow |
| [docs/DIFFERENCES_FROM_OMARCHY.md](docs/DIFFERENCES_FROM_OMARCHY.md) | Honest comparison with Omarchy |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Phases and test status |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute |
| [CHANGELOG.md](CHANGELOG.md) | Release history |
| [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) | Third-party components |

## Status

**v0.1.1 — see [ROADMAP.md](docs/ROADMAP.md) for test status; check the
[releases page](https://github.com/pinkyguy2323/banchy-os/releases) for the
current build state.**

## License and credits

- Code: [MIT](LICENSE), copyright Banchy OS Contributors.
- Based on **Arch Linux** and its package ecosystem (archlinux.org).
- Technically inspired by **Omarchy** (MIT, © David Heinemeier Hansson,
  https://github.com/omacom/omarchy). Banchy OS is **not** a fork and contains
  no Omarchy code — see [NOTICE](NOTICE) and
  [docs/DIFFERENCES_FROM_OMARCHY.md](docs/DIFFERENCES_FROM_OMARCHY.md).
- Third-party components: [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

Links: [repo](https://github.com/pinkyguy2323/banchy-os) ·
[website](https://pinkyguy2323.github.io/banchy-os-site/) ·
[releases](https://github.com/pinkyguy2323/banchy-os/releases)
