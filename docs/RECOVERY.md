# Recovery

Banchy OS ships a recovery path that does not depend on a working desktop, a
working pacman database, or a working main kernel: a boot menu entry into
`rescue.target`, plus a small TUI (`banchy-recovery`) for common repairs.

## Entering recovery

1. At the **Banchy Boot** menu, select **Banchy OS — Recovery**.
   This boots with `systemd.unit=rescue.target` and drops you to a
   **root shell** on the real root filesystem.
2. Log in as `root`. The installer sets the root password to the user's chosen
   password; change it any time with:

   ```bash
   passwd root
   ```

3. Start the recovery TUI:

   ```bash
   banchy-recovery
   ```

If the main kernel is broken, pick **Banchy OS — Previous Kernel** (linux-lts,
always installed) instead, then repair from there.

## `banchy-recovery` menu

| Menu item | What it runs | Use when |
| --- | --- | --- |
| Filesystem check | `fsck` on the root filesystem (and other mounted partitions) | Mount errors, unclean shutdown, corrupted files |
| Bootloader repair | `banchy boot repair` (re-install bootctl, regenerate entries) | Missing/damaged menu entries, ESP problems |
| Regenerate initramfs | `mkinitcpio -P` | Kernel or driver changes left an initramfs mismatch |
| Verify pacman DB | `pacman -Dk`, `pacman-key` | Dependency or keyring errors after a failed update |
| Restore network | `NetworkManager restart` | No connectivity in the running system |
| Restore configs | `banchy config restore` | A config change broke the session (picks a timestamped backup) |
| Btrfs snapshot restore | Lists `/.snapshots`, snapper-style manual snapshots | Roll back the whole system to a pre-change state |
| Open shell | Drops to the root shell | Anything not covered above |
| Reboot | Reboot the machine | Done |

All CLI output uses the standard colorized `[OK]` / `[WARN]` / `[FAIL]` lines
and is logged (`~/.local/state/banchy/banchy.log` when a home directory is
available).

## Btrfs snapshots

- If the system was installed with **btrfs**, snapshots live under
  `/.snapshots` (snapper-style layout).
- `banchy update` creates a snapshot before upgrading when btrfs is detected.
- In recovery, choose **Btrfs snapshot restore** to list snapshots and restore
  one manually; the same snapshots are visible in a shell:

  ```bash
  ls /.snapshots
  ```

On ext4 installs this menu item reports there is nothing to restore — the
config backup/restore path (`banchy config restore`) still works everywhere.

## Recovering from a failed update

`banchy update` sequence: pre-checks (internet, ≥2 GB free, `pacman -Dk`
clean, `banchy boot check`, config backup, btrfs snapshot when applicable) →
`pacman -Syu` → post-checks (kernel + initramfs files, boot entries,
`systemd --failed`, `banchy config check`).

If a **critical** post-check fails, `banchy update` warns you and prints
rollback guidance. The standard order is:

1. **Boot the fallback** — select **Banchy OS — Previous Kernel** at the menu.
2. **Check the bootloader** — `banchy boot check`, and
   `banchy boot repair` if entries are damaged (loader config backups are in
   `/var/lib/banchy/boot-backup/`).
3. **Check the database** — run the recovery menu's *Verify pacman DB* item
   (`pacman -Dk` and `pacman-key`).
4. **Roll back configs** — `banchy config restore` and pick a backup from
   `~/.local/share/banchy/backups/`.
5. **Roll back the system** — on btrfs, restore a snapshot from
   `/.snapshots` (recovery menu or shell).
6. **Verify services** — `systemctl --failed` to see what stopped.

The last known good boot entry is never auto-deleted, so step 1 is always
available.

## Repairing a broken desktop (without booting recovery)

From a working login (TTY or repaired session):

```bash
banchy doctor                 # overall health, colorized report
banchy config diff            # show drift from defaults
banchy config restore         # restore a timestamped backup
banchy reset hyprland         # reset Hyprland configuration
banchy boot check             # verify the boot chain
banchy theme validate <name>  # verify theme output has no unresolved {{...}}
banchy apply                  # re-render and apply settings/themes
```

## Related documents

- [BOOT.md](BOOT.md) — entries, hooks, and why there is no splash in 0.1.0
- [INSTALLATION.md](INSTALLATION.md) — verify gate and first boot
- [CUSTOMIZATION.md](CUSTOMIZATION.md) — settings, themes, config backups
