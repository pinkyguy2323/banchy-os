# Contributing to Banchy OS

Thanks for helping. Banchy OS values stability above all: every critical change
should ship with validation, a backup path, a fallback, and a rollback.

## Workflow

1. Fork the repository and create a feature branch from the default branch:

   ```bash
   git checkout -b fix/boot-entry-check
   ```

2. Make your change. Keep it scoped — one concern per PR.
3. Run lint and tests locally (see below). Both must pass.
4. Open a pull request with a short description of *what* changed and *why*,
   plus how you validated it.
5. Respond to review. Squash or amend only if asked; never force-push over a
   reviewed branch without agreement.

Repo: https://github.com/pinkyguy2323/banchy-os

## Shell style rules

- Start every script with `set -euo pipefail`.
- Must be `shellcheck` clean (`scripts/lint.sh` runs it).
- Parse-check with `bash -n` for anything sourced or executed.
- **No destructive commands** (`rm -rf`, `mkfs`, `dd`, partitioning, loader
  rewrites) without an explicit confirmation prompt or a documented
  non-interactive flag. Destructive operations must offer a backup first.
- Prefer small, sourced modules under `cli/lib/*.sh` over duplicated logic.
- Quote every variable expansion; use `$(...)` rather than backticks.
- Write to staging locations first, validate, then swap atomically — the same
  pattern the Theme Engine uses.
- Never overwrite a user-modified file unless the file is untouched (marker
  comment present) or the user passed `--force`.
- Python (GTK apps) must pass `python -m py_compile`.

## Running lint and tests

```bash
scripts/lint.sh          # shellcheck + bash -n + py_compile + theme validation
tests/run.sh            # unit/smoke: settings, render pipeline, themes,
                         # profiles, config backup/restore, installer syntax
```

On a live or installed system:

```bash
banchy-test boot
banchy-test desktop
banchy-test configs
banchy-test full
```

ISO/VM work: `scripts/test-vm.sh` (QEMU + OVMF, serial console via expect,
logs under `test-results/`). See [docs/TESTING.md](docs/TESTING.md).

## Theme contributions

1. Copy an existing theme under `themes/` as a starting point.
2. Define `theme.conf` with `KEY=VALUE` pairs only: `NAME`, `DISPLAY_NAME`,
   `MODE`, `BG`, `SURFACE`, `SURFACE_ALT`, `TEXT`, `TEXT_DIM`, `ACCENT`,
   `ACCENT_ALT`, `BORDER_ACTIVE`, `BORDER_INACTIVE`, `DANGER`, `WARNING`,
   `SUCCESS`, `WALLPAPER` (plus light-mode variants where applicable).
3. Use 6-digit hex colors (`#RRGGBB`). Do not hardcode raw CSS or config syntax
   in `theme.conf` — colors go through the templates in
   `themes/templates/*.tmpl` (`{{KEY}}` placeholders).
4. Do not hand-edit generated files (`Hyprland dynamic.conf`, `style.css`,
   kitty colors include, fuzzel ini, mako config, hyprlock, hyprpaper, GTK CSS,
   `theme.env`) — they are produced by the render pipeline.
5. Validate:

   ```bash
   banchy theme validate <name>
   scripts/lint.sh
   ```

   Validation fails on unresolved `{{...}}` placeholders or invalid hex colors.
6. Include a wallpaper reference that exists, or ship the asset under
   `wallpapers/`.

User themes live in `~/.config/banchy/themes/<name>/theme.conf`.

## Commit style

Short, imperative, lowercase-first subject line, no trailing period:

```
fix boot check for missing initramfs
add frost theme accent variants
document unattended installer answers
```

Reference issue numbers in the body when relevant. Do not commit build output
(`out/`), logs (`test-results/`), or generated files.

## Code of conduct

Be respectful and constructive. Disagree on ideas, not people. Harassment or
personal attacks are not welcome. Maintainers may close or edit contributions
that violate this. Keep it light: act like a professional working with peers.

## Where to look

| Area | Location |
| --- | --- |
| CLI entrypoint and modules | `cli/`, `cli/lib/`, `cli/bin/` |
| Installer | `installer/` |
| Boot templates and hooks | `boot/` |
| Theme engine templates | `themes/`, `themes/templates/` |
| Default configs | `configs/` |
| Tests | `tests/`, `scripts/lint.sh` |
| Docs | `docs/` |

Architecture background: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
