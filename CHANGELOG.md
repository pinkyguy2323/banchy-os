# Changelog

All notable changes to Banchy OS are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
for tagged releases while the base system itself rolls forward on Arch Linux.

## [0.1.0] - 2026-09-29

Initial release.

### Added

- **Banchy OS base**: Arch Linux rolling-release base with systemd, NetworkManager,
  PipeWire, and pacman.
- **Hyprland desktop** on Wayland with Waybar, fuzzel, kitty, mako, hyprpaper,
  hyprlock, hypridle, grim + slurp, cliphist + wl-clipboard, thunar, imv,
  zathura, pavucontrol, blueman, neovim, btop, and fastfetch. Default apps:
  Visual Studio Code, Chromium, Obsidian. Docker available via the Developer
  profile.
- **`banchy` CLI**: `update`, `doctor`, `info`, `theme` (list/set/create/validate),
  `package` (install/remove), `profile` (minimal/default/developer/creator/gaming/full),
  `config` (backup/restore/diff/check/validate), `reset hyprland`, `boot`
  (check/repair/install), `system check`, `keys`, `set`/`get`, `apply`,
  `welcome`, `recovery`, `help`, `version`. Colorized `[OK]`/`[WARN]`/`[FAIL]`
  output with logs at `~/.local/state/banchy/banchy.log`.
- **Theme Engine**: template-based rendering with staging, validation, atomic
  swap, runtime verification via `hyprctl`, and rollback to the last good
  state. Five bundled themes: Banchy Midnight, Banchy Black, Banchy Frost,
  Banchy Neon, Banchy Minimal.
- **`banchy-settings`**: Python/GTK4 GUI (Appearance, Wallpapers, Waybar, Fonts,
  Monitors, About) backed entirely by `banchy set` + `banchy apply`.
- **`banchy-cc` control center**: Wi-Fi, Bluetooth, volume, mic, brightness,
  power profile, night mode, screenshot, screen recording, VPN, and power
  actions on `SUPER+N`.
- **Banchy Boot**: systemd-boot menu (main, previous-kernel fallback,
  recovery, optional verbose), `loader.conf` with timeout 3 and editor
  disabled, pre-transaction pacman hooks backing up loader config to
  `/var/lib/banchy/boot-backup/`.
- **Recovery**: `Banchy OS — Recovery` boot entry (`rescue.target`) and the
  `banchy-recovery` TUI (fsck, bootloader repair, initramfs regeneration,
  pacman DB verification, network restore, config restore, Btrfs snapshot
  restore, shell, reboot).
- **Banchy Installer**: whiptail TUI flow plus `--unattended <answers.conf>`,
  with a verification gate before reboot is offered and a log at
  `/var/log/banchy-install.log`.
- **`banchy-welcome` first-run wizard**: language, keyboard, timezone, Wi-Fi,
  theme, accent, wallpaper, profile, optional apps, and git config; runs on
  first graphical login or via `banchy welcome`.
- **Package profiles**: `minimal`, `default`, `developer`, `creator`, `gaming`,
  `full` under `packages/profiles/`.
- **Config management**: `banchy config backup/restore/diff/check/validate`
  with timestamped tar archives under `~/.local/share/banchy/backups/` and
  managed-file markers.
- **`banchy update`**: pre-checks (connectivity, disk space, pacman DB, boot
  check, config backup, optional Btrfs snapshot), `pacman -Syu`, post-checks,
  and rollback guidance on critical failure.
- **Build and test tooling**: `scripts/build-iso.sh`,
  `install-files.sh`, `test-vm.sh`, `lint.sh`, `gen-wallpapers.ps1`;
  `tests/run.sh` and QEMU/OVMF serial smoke tests.
- **CI**: lint + unit tests, ISO build with QEMU smoke test, and tagged
  GitHub Releases carrying `banchy-os-x86_64.iso` plus `.sha256`.
- **Documentation**: architecture, installation, boot, recovery,
  customization, testing, development, Omarchy differences, and roadmap.

[0.1.0]: https://github.com/pinkyguy2323/banchy-os/releases
