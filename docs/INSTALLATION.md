# Installation

Banchy OS installs from its live ISO via the **Banchy Installer**
(`banchy-install`), a whiptail TUI. The same installer supports fully
unattended runs for provisioning.

## Requirements

- UEFI firmware (the layout is **GPT + UEFI**; the ESP is FAT32 at `/boot`,
  GPT type `EF00`).
- x86_64 machine.
- Enough disk space for the chosen profile (large packages are only installed
  when explicitly selected).
- Network access is recommended so the installer can fetch packages.

## Interactive install (TUI)

Boot the ISO and run:

```bash
banchy-install
```

Flow:

| Step | What happens |
| --- | --- |
| Welcome | Introduction to the installer. |
| Language | System language selection. |
| Keyboard | Keymap selection. |
| Network | Network setup (NetworkManager). |
| Disk | Target disk; partitioning **GPT + UEFI**; filesystem **ext4** or **btrfs** (btrfs uses `@` and `@home` subvolumes); swap file. |
| User | Username, password, hostname; user added to `wheel` for sudo. |
| Profile | `minimal`, `default` (installer default), `developer`, `creator`, `gaming`, `full`. |
| Applications | Optional applications beyond the profile (large packages on explicit choice only). |
| Theme | One of the five bundled themes (Midnight, Black, Frost, Neon, Minimal). |
| Install | Copy system, install packages, write configs, install bootloader. |
| Verify | Verification gate (see below). |
| Reboot | Offered only when verification passes (or with an explicit override, with warnings). |

The root filesystem password is set from the user's chosen password; the
installer also sets the **root password to the same value** (documented, and
changeable later with `passwd root`). This is what makes the Recovery entry
usable — see [RECOVERY.md](RECOVERY.md).

Install log: `/var/log/banchy-install.log`.

## Unattended install

```bash
banchy-install --unattended /path/to/answers.conf
```

`answers.conf` is a `key=value` file:

| Key | Meaning |
| --- | --- |
| `DISK` | Target block device |
| `FS` | Filesystem (`ext4` or `btrfs`) |
| `HOSTNAME` | System hostname |
| `USERNAME` | Primary user |
| `PASSWORD` | User (and root) password |
| `TIMEZONE` | e.g. `Europe/Rome` |
| `KEYMAP` | Keyboard layout |
| `PROFILE` | `minimal` \| `default` \| `developer` \| `creator` \| `gaming` \| `full` |
| `THEME` | Theme name (e.g. `midnight`) |
| `SERIAL_CONSOLE` | Serial console settings for headless/VM installs |

Example:

```ini
DISK=/dev/vda
FS=btrfs
HOSTNAME=banchy
USERNAME=alice
PASSWORD=change-me
TIMEZONE=UTC
KEYMAP=us
PROFILE=default
THEME=midnight
SERIAL_CONSOLE=ttyS0
```

## Verification gate

Before a reboot is offered, the installer verifies:

- [ ] Root filesystem mounted and writable
- [ ] EFI/ESP present (FAT32 at `/boot`)
- [ ] `fstab` written and consistent
- [ ] Kernel installed
- [ ] initramfs generated
- [ ] Bootloader entries present (Banchy Boot — see [BOOT.md](BOOT.md))
- [ ] Network: NetworkManager enabled
- [ ] User account and sudo (`wheel`) configured
- [ ] Display stack: Hyprland binary present, `waybar` present, xdg desktop
      portal configured

Reboot is offered **only when all checks pass**. An explicit override exists,
but it prints warnings for every failed check. Results are also written to the
install log.

## After first boot

1. On the first graphical login, `banchy-welcome` starts automatically (flag
   file: `~/.config/banchy/first-run-done`). It configures language, keyboard,
   timezone, Wi-Fi, theme, accent, wallpaper, profile, optional apps, and git
   config. You can re-run it any time with `banchy welcome`.
2. Check system health:

   ```bash
   banchy doctor
   banchy boot check
   ```

3. Apply or change the theme:

   ```bash
   banchy theme list
   banchy theme set frost
   banchy apply
   ```

## Profile reference

| Profile | Contents |
| --- | --- |
| `minimal` | System + Hyprland + core utilities |
| `default` | minimal + VS Code + Chromium + Obsidian (**installer default**) |
| `developer` | default + git, docker, nodejs, npm, python, base-devel, … |
| `creator` | default + OBS Studio, Blender, GIMP, Kdenlive |
| `gaming` | default + steam, gamescope, mangohud, gamemode (enables multilib) |
| `full` | everything |

Profiles are plain lists under `packages/profiles/*.list` and can be applied
later with `banchy profile <name>`.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Install log needed | `less /var/log/banchy-install.log` (or from a live shell) |
| Boot menu missing entries | Boot recovery entry, run `banchy-recovery` → bootloader repair, or `banchy boot repair` |
| Verification failed | Re-run `banchy-install`; fix the reported item before overriding the reboot gate |
| System unhealthy after install | `banchy doctor`, then `banchy config check` |

If the system does not boot at all, use the recovery flow described in
[RECOVERY.md](RECOVERY.md).
