# Testing

Banchy OS treats testing as part of the stability rule: validation, backup,
fallback, rollback — and proof that it works.

## Test layers

| Layer | Command | Where it runs |
| --- | --- | --- |
| Lint | `scripts/lint.sh` | Dev machine, CI |
| Unit / smoke | `tests/run.sh` | Dev machine, CI |
| On-system | `banchy-test boot\|desktop\|configs\|full` | Live ISO or installed system |
| VM smoke | `scripts/test-vm.sh` | Dev machine (QEMU + OVMF) |
| CI | `.github/workflows/ci.yml`, `iso.yml` | GitHub Actions |

## Lint

```bash
scripts/lint.sh
```

Runs:

- `shellcheck` over the shell sources
- `bash -n` syntax checks
- `python -m py_compile` for the GTK/Python apps
- Theme validation (no unresolved `{{...}}`, valid hex colors)

Lint must pass before a PR is merged.

## Unit and smoke tests

```bash
tests/run.sh
```

Covers:

- Settings validation (every key and its range/format)
- Theme render pipeline (merge → render → validate → swap → rollback)
- Theme validation for all five bundled themes
- Package profile lists (`packages/profiles/*.list`)
- Config backup / restore round-trip
- Installer script syntax

Test sources live under `tests/` (`boot/`, `configs/`, `themes/`,
`packages/`, `integration/`, `vm/`).

## On-system tests

For a live session or an installed system:

```bash
banchy-test boot       # boot chain: ESP, entries, kernels, UUID, bootctl
banchy-test desktop    # Hyprland stack: waybar, portal, apps
banchy-test configs    # generated configs, markers, validation
banchy-test full       # everything above plus integration checks
```

Results are colorized `[OK]` / `[WARN]` / `[FAIL]` and logged to
`~/.local/state/banchy/banchy.log`.

## VM smoke test (QEMU + OVMF / SeaBIOS)

```bash
scripts/test-vm.sh <iso>          # UEFI boot (OVMF firmware)
scripts/test-vm.sh --bios <iso>   # legacy BIOS boot (SeaBIOS, El Torito/SYSLINUX)
```

- Boots the built ISO in QEMU — OVMF (UEFI) by default, SeaBIOS with `--bios`
- Drives the serial console with expect (`scripts/vm-smoke.exp`)
- Writes logs to `test-results/` (`vm-smoke.log` / `vm-smoke-bios.log`,
  including `test-results/summary.md`)

This is the same harness CI uses after building the ISO — CI runs **both**
firmware modes.

## CI pipelines

| Workflow | Trigger | Steps |
| --- | --- | --- |
| `ci.yml` | push, pull request | `scripts/lint.sh` → `tests/run.sh` |
| `iso.yml` | push (main), tag `v*` | Build ISO in a privileged `archlinux` container with `mkarchiso` → QEMU serial smoke tests of the ISO in **both** firmware modes (UEFI/OVMF + legacy BIOS/SeaBIOS) → on `v*` tags create a GitHub Release with `banchy-os-x86_64.iso` + `.sha256` |

## Release gates

All gates must report **PASS** before a release is published. Current status:

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

The authoritative table is generated alongside test runs in
`test-results/summary.md`. Nothing is claimed as passing until CI reports it —
see [ROADMAP.md](ROADMAP.md).

## Building an ISO to test

```bash
# On Arch Linux
scripts/build-iso.sh

# Anywhere with Docker (privileged container required)
docker run --rm --privileged -v "$PWD":/src -w /src archlinux:base-devel \
  bash -c "pacman -Syu --noconfirm archiso && scripts/build-iso.sh"
```

Output: `out/banchy-os-*.iso`. Then:

```bash
scripts/test-vm.sh
```

More detail: [DEVELOPMENT.md](DEVELOPMENT.md).
