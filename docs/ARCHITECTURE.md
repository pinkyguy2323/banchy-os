# Banchy OS — Architecture

This document describes how the Banchy OS repository is laid out and how its
main pieces fit together. Banchy OS is an independent Arch Linux based
distribution (version 0.2.0, rolling release).

## Design principles

- **Fast, Minimal, Beautiful, Customizable, Stable, Developer Friendly.**
- Core rule: **stability > maintainability > usability > performance hacks.**
- Every critical change ships with **validation + backup + fallback + rollback.**
- Managed files carry a marker comment; user-modified files are never
  overwritten without `--force`.

## Repository layout

```
banchy-os/
├── installer/        # Banchy Installer (TUI + unattended), lib/ helpers
├── iso/              # archiso profile (iso/profile/: profiledef.sh, airootfs, efiboot, syslinux)
├── packages/         # package profile lists (packages/profiles/*.list)
├── configs/          # default user configs (hypr/, waybar/, kitty/, fuzzel/,
│                     #   mako/, hyprlock/, hyprpaper/, hypridle/, fastfetch/,
│                     #   gtk/)
├── themes/           # theme definitions (5 themes) + templates/ (render templates)
├── boot/             # Banchy Boot: loader entry templates, pacman hooks, recovery
├── scripts/          # build/lint/test automation (build-iso.sh,
│                     #   install-files.sh, test-vm.sh, lint.sh, gen-wallpapers.ps1)
├── first-run/        # banchy-welcome first-run wizard
├── apps/             # banchy-settings (Python/GTK4), banchy-cc control center
├── cli/              # banchy CLI: entrypoint + lib/*.sh modules + bin/ helper scripts
├── wallpapers/       # shipped wallpapers (PNG, generated from wallpapers/src)
├── branding/         # logo SVG, ASCII logo, brand assets
├── tests/            # smoke/unit tests (test_*.sh driven by tests/run.sh)
├── docs/             # documentation
└── .github/workflows # CI: lint+tests, ISO build, VM smoke, release
```

## Component overview

| Component | Role |
| --- | --- |
| `installer/` | `banchy-install` — whiptail TUI and unattended (`--unattended answers.conf`) installation; `lib/` holds shared helpers. Runs partitioning (GPT + UEFI), file copy, user/profile/theme setup, and the verification gate. |
| `iso/` | archiso profile consumed by `scripts/build-iso.sh` and `.github/workflows/iso.yml`: `iso/profile/` holds `profiledef.sh`, `pacman.conf`, `airootfs/` (live system content), `efiboot/` (UEFI boot content), `syslinux/` (legacy BIOS boot content). |
| `packages/` | One `.list` file per profile under `packages/profiles/`, consumed by `banchy profile <name>` and the installer. |
| `configs/` | Default user configuration files installed to `~/.config/` (Hyprland, Waybar, kitty, fuzzel, mako, hyprlock, hyprpaper, hypridle, fastfetch, GTK). |
| `themes/` | Five bundled themes plus `templates/` (`*.tmpl` with `{{KEY}}` placeholders) that drive the Theme Engine render pipeline. |
| `boot/` | Loader entry templates for systemd-boot, pre-transaction pacman hooks, and recovery assets (Banchy Boot). |
| `scripts/` | Automation: `build-iso.sh`, `install-files.sh`, `test-vm.sh`, `lint.sh`, `gen-wallpapers.ps1`. |
| `first-run/` | `banchy-welcome` — whiptail first-run wizard, triggered on first graphical login (flag `~/.config/banchy/first-run-done`) or `banchy welcome`. |
| `apps/` | `banchy-settings` (Python + GTK4/PyGObject) and `banchy-cc` control center (GTK4, `SUPER+N`). |
| `cli/` | The `banchy` entrypoint, `lib/*.sh` modules (one module per command family), `bin/` helper scripts. |
| `wallpapers/` | Shipped PNG wallpapers, generated from `wallpapers/src` via `scripts/gen-wallpapers.ps1`. |
| `branding/` | Logo SVG, ASCII logo, and other brand assets. |
| `tests/` | Unit/smoke suites grouped by area plus integration and VM tests. |
| `docs/` | This documentation. |
| `.github/workflows` | CI: `ci.yml` (lint + unit tests), `iso.yml` (ISO build, QEMU serial smoke, tagged release). |

## Desktop stack

Banchy OS runs **Hyprland on Wayland** with a fixed, deliberately small app set:

| Role | Application |
| --- | --- |
| Compositor | Hyprland |
| Bar | Waybar |
| Launcher | fuzzel |
| Terminal | kitty |
| Notifications | mako |
| Wallpaper | hyprpaper |
| Lock / idle | hyprlock / hypridle |
| Screenshots | grim + slurp |
| Clipboard | cliphist + wl-clipboard |
| Files / images / PDF | thunar / imv / zathura |
| Audio / Bluetooth | pavucontrol / blueman |
| CLI editor | neovim |
| Utilities | git, curl, wget, unzip, btop, fastfetch |
| Default apps | Visual Studio Code, Chromium, Obsidian |
| Containers | Docker (Developer profile only) |

## Configuration layering

```
/usr/share/banchy/defaults/     # system defaults shipped by the package/repo
        │
        ▼
/usr/share/banchy/themes/<name>/theme.conf    # system themes
~/.config/banchy/themes/<name>/theme.conf     # user themes (banchy theme create)
        │
        ▼  (settings.conf + theme.conf merged)
themes/templates/*.tmpl          # {{KEY}} placeholders
        │
        ▼  (render → validate → atomic swap → verify)
generated user files under ~/.config/   # Hyprland dynamic.conf, style.css, ...
```

- User configs live under `~/.config/` and are never overwritten needlessly.
- `banchy config backup` writes a timestamped tar to
  `~/.local/share/banchy/backups/`; `restore`, `diff`, `check`, and `validate`
  operate on the same set.
- Runtime logs go to `~/.local/state/banchy/banchy.log`; the installer logs to
  `/var/log/banchy-install.log`.

## Theme render pipeline

1. **Merge** — `settings.conf` (theme, mode, accent, transparency, blur, …) and
   the selected `theme.conf` are merged into one key/value context.
2. **Render** — each `themes/templates/*.tmpl` is rendered with `{{KEY}}
   placeholders into generated files: Hyprland `dynamic.conf`, Waybar
   `style.css`, kitty colors include, fuzzel ini, mako config, hyprlock,
   hyprpaper, GTK CSS, and `theme.env`.
3. **Stage** — output is written to a staging location first, never directly
   over live files.
4. **Validate** — fail on any unresolved `{{...}}` placeholder or invalid hex
   color.
5. **Swap** — atomically move staged files into place.
6. **Verify** — if Hyprland is running, confirm via `hyprctl getoption`.
7. **Rollback** — on any failure, restore the last good state and surface the
   error. Managed files carry a marker comment so untouched files can be
   refreshed safely and modified ones require `--force`.

## The `banchy` CLI

One entrypoint with lib modules; every command emits colorized
`[OK]` / `[WARN]` / `[FAIL]` lines and appends to the log file.

| Group | Subcommands |
| --- | --- |
| System | `update`, `doctor`, `info`, `system check`, `keys`, `version`, `help` |
| Theming | `theme list/set/create/validate`, `apply` |
| Settings | `set`, `get` (validated keys — see [CUSTOMIZATION.md](CUSTOMIZATION.md)) |
| Packages | `package install/remove`, `profile <minimal\|default\|developer\|creator\|gaming\|full>` |
| Config | `config backup/restore/diff/check/validate` |
| Desktop | `reset hyprland` |
| Boot | `boot check/repair/install` |
| Onboarding | `welcome`, `recovery` |

## Boot and recovery

Banchy Boot is **systemd-boot** (not GRUB, not a custom bootloader). Safety is
implemented in three layers:

1. Entry templates in `boot/` (main kernel, always-installed LTS fallback,
   recovery, optional verbose).
2. Pre-transaction pacman hooks that back up the loader configuration to
   `/var/lib/banchy/boot-backup/` before upgrades.
3. Tooling: `banchy boot check` (diagnostics), `banchy boot repair`
   (re-install bootctl, regenerate entries), `banchy boot install` (used by
   the installer).

The last known good entry is never auto-deleted. Full detail:
[BOOT.md](BOOT.md) and [RECOVERY.md](RECOVERY.md).

## Update flow

`banchy update` = pre-checks (internet, ≥2 GB free, `pacman -Dk` clean,
`banchy boot check`, config backup, Btrfs snapshot when applicable) →
`pacman -Syu` → post-checks (kernel + initramfs files, boot entries,
`systemd --failed`, `banchy config check`). On critical failure the user is
warned and given rollback guidance. Details: [RECOVERY.md](RECOVERY.md).

## Build, CI, and release

- **Build**: `scripts/build-iso.sh` on Arch Linux or in a privileged
  `archlinux:base-devel` container with archiso; output `out/banchy-os-*.iso`.
  See [DEVELOPMENT.md](DEVELOPMENT.md).
- **CI**: `.github/workflows/ci.yml` (lint + unit tests on push/PR) and
  `iso.yml` (ISO build in a privileged container → QEMU serial smoke test →
  GitHub Release on `v*` tags with `banchy-os-x86_64.iso` + `.sha256`).
- **Release gates**: eleven checks must PASS before a release ships; status
  table lives in [TESTING.md](TESTING.md) and `test-results/summary.md`.

## Related documents

- [INSTALLATION.md](INSTALLATION.md) — installer flows and verify gate
- [BOOT.md](BOOT.md) — Banchy Boot internals
- [RECOVERY.md](RECOVERY.md) — recovery entry and `banchy-recovery`
- [CUSTOMIZATION.md](CUSTOMIZATION.md) — themes, settings, keybindings
- [TESTING.md](TESTING.md) — test layers, CI, release gates
- [DEVELOPMENT.md](DEVELOPMENT.md) — building and hacking on the ISO
