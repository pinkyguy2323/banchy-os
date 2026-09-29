# Differences between Banchy OS and Omarchy

Banchy OS was **technically inspired** by Omarchy (MIT,
© David Heinemeier Hansson, https://github.com/omacom/omarchy) — its
installer-based Hyprland desktop idea and its theme-driven configuration
approach. That is where the similarity ends.

**Banchy OS is not a reskin of Omarchy, is not a fork, and is not affiliated
with, endorsed by, or connected to Omarchy or Basecamp.** No Omarchy source
code was copied into this repository; attribution and the full statement live
in [NOTICE](../NOTICE).

## Comparison

| Aspect | Omarchy | Banchy OS |
| --- | --- | --- |
| Distribution format | Installer-based dotfiles distribution (applies configuration to an existing setup) | Full ISO distribution with its own **installer** (`banchy-install`, TUI + unattended) and archiso-based build pipeline |
| Theme system | Theme-based configuration concept | Own **Theme Engine**: `theme.conf` key/value definitions, `{{KEY}}` templates, staged render → validate (no unresolved placeholders, valid hex) → atomic swap → `hyprctl` verification → rollback |
| Settings GUI | — | **`banchy-settings`**: Python + GTK4 GUI (Appearance, Wallpapers, Waybar, Fonts, Monitors, About), every change routed through `banchy set` / `banchy apply` |
| CLI | — | **`banchy` CLI** with `update`, `doctor`, `info`, `theme`, `package`, `profile`, `config`, `boot`, `keys`, `apply`, `welcome`, `recovery`, and more; colorized `[OK]`/`[WARN]`/`[FAIL]`, logs to `~/.local/state/banchy/banchy.log` |
| Boot setup | Conventional distribution bootloader | **Banchy Boot**: systemd-boot (not GRUB, not a custom bootloader) with a branded menu: main entry, **always-installed previous-kernel (linux-lts) fallback**, recovery entry, optional verbose; `loader.conf` timeout 3, editor disabled; pre-transaction pacman hooks backing up loader config to `/var/lib/banchy/boot-backup/`; `banchy boot check` / `repair` / `install` |
| Recovery | Depends on the host setup | Boot menu entry → `systemd.unit=rescue.target` root shell + **`banchy-recovery` TUI** (fsck, bootloader repair, `mkinitcpio -P`, pacman DB verify, network restore, config restore, Btrfs snapshot restore, shell, reboot) |
| Package selection | Setup driven | **Package profiles**: `minimal`, `default`, `developer`, `creator`, `gaming`, `full` (`packages/profiles/*.list`), large packages only on explicit choice |
| Config management | Dotfiles-style application | **Config management**: `banchy config backup/restore/diff/check/validate`, timestamped tar backups, managed-file markers; user-modified files never overwritten without `--force` |
| First-run experience | — | **`banchy-welcome`** first-run wizard (language, keyboard, timezone, Wi-Fi, theme, accent, wallpaper, profile, optional apps, git config), triggered on first graphical login |
| Control center | — | **`banchy-cc`** (GTK4, `SUPER+N`): Wi-Fi, Bluetooth, volume, mic, brightness, power profile, night mode, screenshot, screen recording, VPN, power actions |
| Branding / design | Omarchy branding and design language | Own branding and design language (logo, ASCII logo, wallpapers, five Banchy themes) |
| App set | Varies with setup | Deliberately minimized around **Visual Studio Code, Chromium, Obsidian** plus a small fixed Hyprland stack |
| Updates | Host package manager | **`banchy update`**: pre-checks (connectivity, ≥2 GB free, `pacman -Dk`, boot check, config backup, btrfs snapshot) → `pacman -Syu` → post-checks, with rollback guidance on critical failure |
| Code provenance | Omarchy (MIT) | Independent codebase, MIT licensed, **no Omarchy code copied** — attribution in [NOTICE](../NOTICE) |

## What the inspiration actually means

Similarities are *conceptual*, not textual:

- Both ship a Hyprland-based desktop configured by themes.
- Both favor a curated, minimal application set over "everything by default".
- Both keep configuration in files that can be re-rendered and restored.

Everything else — the installer, ISO profile, CLI, theme engine
implementation, boot safety design, recovery tooling, profiles, config
management, first-run wizard, control center, branding, tests, and CI — was
written from scratch for Banchy OS.

## Credits

- **Omarchy**: technical inspiration only. MIT © David Heinemeier Hansson —
  https://github.com/omacom/omarchy
- **Arch Linux**: the base distribution Banchy OS is built on —
  https://archlinux.org
- Full third-party inventory: [THIRD_PARTY_LICENSES.md](../THIRD_PARTY_LICENSES.md)
- Legal/attribution statement: [NOTICE](../NOTICE)
