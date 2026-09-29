#!/usr/bin/env bash
# Banchy OS — copy the repository into an FHS filesystem layout.
#
#   scripts/install-files.sh                 stage into / (needs root)
#   scripts/install-files.sh --root DIR      stage into DIR (archiso/VM/installer)
#
# Used by: the archiso build (into airootfs), banchy-install (target system)
# and local development staging (.devroot). Every source file is required:
# a missing file is a hard error, never a silent skip. Directories that do
# not exist yet (configuration shipping in a later release) are reported and
# skipped by d_opt.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="/"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:?--root needs a directory}"; shift ;;
    *) echo "install-files: unknown option '$1'" >&2; exit 2 ;;
  esac
  shift
done

f() { # f <mode> <repo-rel-file> <root-rel-file>
  local mode="$1" rel="$2" dest="$3"
  [[ -f "$REPO/$rel" ]] || { echo "install-files: missing $rel" >&2; exit 1; }
  mkdir -p "$ROOT/$(dirname "$dest")"
  cp "$REPO/$rel" "$ROOT/$dest"
  chmod "$mode" "$ROOT/$dest"
}

d() { # d <mode> <repo-rel-dir> <root-rel-dir> — copy all files, keep structure
  local mode="$1" rel="$2" dest="$3" p r
  [[ -d "$REPO/$rel" ]] || { echo "install-files: missing $rel/" >&2; exit 1; }
  while IFS= read -r -d '' p; do
    r="${p#"$REPO/$rel"/}"
    mkdir -p "$ROOT/$dest/$(dirname "$r")"
    cp "$p" "$ROOT/$dest/$r"
    chmod "$mode" "$ROOT/$dest/$r"
  done < <(find "$REPO/$rel" -type f -print0)
}

# d_opt — like d, but a directory that does not exist yet (placeholders for
# configuration that ships in a later release) is reported and skipped.
# Files inside an existing directory are still required: never skipped.
d_opt() {
  [[ -d "$REPO/$2" ]] || { echo "install-files: note: $2/ not present — skipped"; return 0; }
  d "$@"
}

echo "install-files: staging $REPO -> $ROOT"

# --- command line ------------------------------------------------------------
f 755 cli/banchy usr/bin/banchy
d 755 cli/bin usr/bin
d 644 cli/lib usr/lib/banchy

# --- system defaults (seeded into ~/.config by b_seed_defaults) --------------
d 644 configs/banchy usr/share/banchy/defaults/banchy
d 644 configs/hypr usr/share/banchy/defaults/hypr
d_opt 644 configs/waybar usr/share/banchy/defaults/waybar
d 644 configs/kitty usr/share/banchy/defaults/kitty
d_opt 644 configs/fuzzel usr/share/banchy/defaults/fuzzel
d_opt 644 configs/mako usr/share/banchy/defaults/mako
d_opt 644 configs/hyprlock usr/share/banchy/defaults/hyprlock
d_opt 644 configs/hyprpaper usr/share/banchy/defaults/hyprpaper
d 644 configs/hypridle usr/share/banchy/defaults/hypridle
d 644 configs/fastfetch usr/share/banchy/defaults/fastfetch
d_opt 644 configs/gtk usr/share/banchy/defaults/gtk

# --- user skeleton -----------------------------------------------------------
d 644 configs/skel etc/skel

# --- theme engine ------------------------------------------------------------
d 644 themes/templates usr/share/banchy/templates
local_theme=""
for local_theme in "$REPO"/themes/*/; do
  local_theme="$(basename "$local_theme")"
  [[ "$local_theme" == "templates" ]] && continue
  d 644 "themes/$local_theme" "usr/share/banchy/themes/$local_theme"
done

# --- assets ------------------------------------------------------------------
d 644 wallpapers usr/share/banchy/wallpapers
d 644 branding usr/share/banchy/branding
f 644 version usr/share/banchy/version
d 644 packages usr/share/banchy/packages

# --- applications and helpers ------------------------------------------------
d 755 first-run usr/bin
f 755 apps/banchy-settings usr/bin/banchy-settings
f 755 apps/banchy-cc usr/bin/banchy-cc

# --- boot / recovery ---------------------------------------------------------
f 755 boot/recovery/banchy-recovery usr/share/banchy/recovery/banchy-recovery
d 644 boot/hooks etc/pacman.d/hooks

# --- installer ---------------------------------------------------------------
f 755 installer/banchy-install usr/bin/banchy-install
d 644 installer/lib usr/lib/banchy/installer

# --- licenses ----------------------------------------------------------------
mkdir -p "$ROOT/usr/share/licenses/banchy-os"
f 644 LICENSE usr/share/licenses/banchy-os/LICENSE
f 644 NOTICE usr/share/licenses/banchy-os/NOTICE

echo "install-files: done"
