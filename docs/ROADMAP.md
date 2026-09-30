# Roadmap

Banchy OS v0.1.1. Status of the twelve build phases and the release test
gates. **Nothing is claimed as tested until CI reports it.**

Status values used below:

- **implemented (code complete)** — phase delivered in the repository for 0.1.0
- **in CI pipeline** — wired into CI; awaiting passing runs
- **in progress** — active work right now

## Phases

| # | Phase | Scope | Status |
| --- | --- | --- | --- |
| 1 | Base system | Arch Linux base, pacman, systemd, NetworkManager, PipeWire, core userland | implemented (code complete) |
| 2 | Hyprland desktop | Hyprland + Waybar, fuzzel, kitty, mako, hyprpaper, hyprlock, hypridle, grim/slurp, cliphist, thunar, imv, zathura, pavucontrol, blueman, neovim, btop, fastfetch; default apps VS Code, Chromium, Obsidian; keybindings | implemented (code complete) |
| 3 | Themes | Theme Engine (merge → template render → staging → validate → atomic swap → verify → rollback), 5 bundled themes, templates, managed-file markers | implemented (code complete) |
| 4 | CLI | `banchy` entrypoint + `lib/*.sh` modules: update, doctor, info, theme, package, profile, config, reset, boot, system, keys, set/get, apply, welcome, recovery, help, version; colorized output + logging | implemented (code complete) |
| 5 | Settings | `banchy set`/`get` validation ranges, `banchy apply` pipeline, `banchy-settings` Python/GTK4 GUI, `banchy-cc` control center | implemented (code complete) |
| 6 | Boot + recovery | Banchy Boot (systemd-boot entries, loader.conf, ESP handling), pre-transaction pacman hooks, `boot check/repair/install`, recovery entry, `banchy-recovery` TUI | implemented (code complete) |
| 7 | Welcome | `banchy-welcome` first-run wizard, `first-run-done` trigger, `banchy welcome` | implemented (code complete) |
| 8 | Installer | `banchy-install` whiptail TUI flow, `--unattended answers.conf`, verify gate, install log | implemented (code complete) |
| 9 | ISO | archiso profile (`iso/profile/`), `scripts/build-iso.sh` + `install-files.sh`, `out/banchy-os-*.iso`, sha256 artifacts | implemented (code complete) |
| 10 | QEMU/KVM testing | `scripts/test-vm.sh` (QEMU + OVMF/SeaBIOS for UEFI and legacy BIOS, serial console via expect), `scripts/vm-smoke.exp`, `tests/vm/`, CI ISO build → serial smoke (both firmwares) | in CI pipeline |
| 11 | Update/rollback testing | `banchy update` pre/post-checks, config backup/restore, boot fallback verification, btrfs snapshot restore, rollback guidance | in CI pipeline |
| 12 | Documentation/release | docs/, README, CONTRIBUTING, CHANGELOG, THIRD_PARTY_LICENSES, CI release job (`iso.yml` → GitHub Release on `v*` tags) | in progress |

## Test status — release gates

All eleven gates must report **PASS** before a release is published. Current
state: **no gate has run yet**.

| # | Gate | Status |
| --- | --- | --- |
| 1 | ISO Build | pending first CI run |
| 2 | UEFI Boot | pending first CI run |
| 3 | Installation | pending first CI run |
| 4 | First Boot | pending first CI run |
| 5 | Hyprland | pending first CI run |
| 6 | Network | pending first CI run |
| 7 | Banchy Boot | pending first CI run |
| 8 | System Update | pending first CI run |
| 9 | Boot after Update | pending first CI run |
| 10 | Fallback Boot | pending first CI run |
| 11 | Recovery | pending first CI run |

The machine-generated copy of this table lives in `test-results/summary.md`
after a test run (see [TESTING.md](TESTING.md)).

## Notes

- v0.1.0 is a **code-complete first release candidate**: the implementation
  exists, but end-to-end verification depends on the first CI runs (phases
  10–11) and the documentation/release pass (phase 12).
- Boot splash (Plymouth) is intentionally **not** in 0.1.0 — see the rationale
  in [BOOT.md](BOOT.md); it is a candidate for v0.2.
- Future phases beyond 0.2 (splash, further rollback tooling) will follow the
  same rule: validation + backup + fallback + rollback before any feature
  lands.
