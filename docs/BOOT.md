# Banchy Boot

Banchy Boot is the boot setup of Banchy OS: **systemd-boot** (the standard
EFI boot manager shipped with systemd) driven by templates, with safety hooks
and repair tooling. It is **not GRUB** and **not a custom bootloader** — it is
systemd-boot with a Banchy-branded menu, entries, and guardrails.

## Boot menu

Menu title: **Banchy Boot**.

| Entry | Kernel / target | Notes |
| --- | --- | --- |
| **Banchy OS** | `linux` (main kernel), `quiet` | Default entry |
| **Banchy OS — Previous Kernel** | `linux-lts` | Fallback; the LTS kernel is **always installed** |
| **Banchy OS — Recovery** | `systemd.unit=rescue.target` | Root shell for repairs — see [RECOVERY.md](RECOVERY.md) |
| **Banchy OS — Verbose** | `linux`, no `quiet` | Optional, for debugging boot messages |

## Loader configuration

`loader.conf`:

```
timeout 3
editor no
```

- **timeout 3** — three seconds to pick an entry.
- **editor no** — kernel command line editing from the menu is **disabled for
  security** (an attacker with physical access could otherwise inject e.g.
  `init=/bin/bash` to reach a root shell without a password).

## Disk layout

| Item | Value |
| --- | --- |
| Firmware | UEFI only |
| Partition table | GPT |
| ESP | `/boot`, FAT32, GPT type `EF00` |
| Bootloader | systemd-boot (`bootctl`) |

Kernel and initramfs files live on the ESP so systemd-boot can load them
directly.

## Safety design

Three layers protect against a broken upgrade or a bad config change:

1. **Always-installed fallback kernel.** The `linux-lts` package (and its
   entry) is part of every install, so a broken main kernel is one menu pick
   away from bootable.
2. **Pre-transaction pacman hooks.** Before any package transaction that could
   touch the bootloader or kernels, the loader configuration is backed up to
   `/var/lib/banchy/boot-backup/`. Restoring is part of `banchy boot repair`.
3. **Never delete the last known good entry.** Repair regenerates entries from
   templates in `boot/`; it never removes the last known good entry, and no
   command auto-deletes it.

## Tooling

```bash
banchy boot check      # diagnostics, read-only
banchy boot repair     # re-install bootctl, regenerate entries from templates
banchy boot install     # used by the installer to set up the ESP from scratch
```

### `banchy boot check`

Verifies, reporting `[OK]` / `[WARN]` / `[FAIL]`:

- ESP present and writable
- Boot entries exist (Banchy OS, Previous Kernel, Recovery)
- Kernel and initramfs files exist for each entry
- Root filesystem UUID referenced in the entries matches `findmnt`
- `bootctl status` reports OK

### `banchy boot repair`

- Re-installs the bootloader with `bootctl install`
- Restores loader configuration from `/var/lib/banchy/boot-backup/` when the
  current copy is bad, otherwise regenerates entries from `boot/` templates
- Keeps the last known good entry intact
- Ends with a `banchy boot check` to confirm the result

### `banchy boot install`

Used by `banchy-install` during installation: prepares the ESP, writes
`loader.conf` and the entry templates, and installs systemd-boot.

## Pacman hooks (backup before upgrades)

| Hook | Timing | Action |
| --- | --- | --- |
| Boot config backup | PreTransaction | Copies loader configuration and entry files to `/var/lib/banchy/boot-backup/` before upgrades that could modify them |

Together with `banchy update`'s pre-checks (`banchy boot check` runs before
`pacman -Syu`) and post-checks (kernel + initramfs files, boot entries), a
failed upgrade always leaves a documented rollback path. See
[RECOVERY.md](RECOVERY.md).

## Why there is no Plymouth in 0.1.0

Banchy OS deliberately does **not** ship a boot splash (Plymouth) in 0.1.0.

Rationale:

- **Stability first.** The core rule of the project is
  *stability > maintainability > usability > performance hacks*. A splash
  sits directly on the boot path — it depends on the initramfs, GPU drivers,
  and the systemd unit ordering — exactly the area where a regression turns a
  cosmetic issue into an unbootable system.
- **Debuggability.** Boot messages remain visible, which makes the fallback
  and recovery entries far more useful during the early life of the distro.
- **Scope.** 0.1.0 focuses on a correct, verifiable boot chain (entries,
  hooks, check/repair). A splash is cosmetic and adds no function.

A boot splash is **on the roadmap for v0.2** (see
[ROADMAP.md](ROADMAP.md)) and will be evaluated against the same
validation/backup/fallback/rollback requirement as every other critical
change.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Menu entries missing | Recovery entry → `banchy-recovery` → bootloader repair; or `banchy boot repair` |
| System boots old kernel | Pick **Banchy OS — Previous Kernel** in the menu, then `banchy boot check` after login |
| UUID mismatch after disk change | `banchy boot repair` regenerates entries from templates with current `findmnt` values |
| Loader config clobbered by upgrade | Configs are in `/var/lib/banchy/boot-backup/`; `banchy boot repair` restores/regenerates |
