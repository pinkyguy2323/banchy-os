#!/usr/bin/env bash
# Five themes ship, each validates, wallpapers exist, theme list is consistent.
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

t_setup

themes_dir="$BANCHY_SHARE/themes"
assert_file "$BANCHY_SHARE/templates/manifest"

names=()
for dir in "$themes_dir"/*/; do
  if [[ -d "$dir" ]]; then
    names+=("$(basename "$dir")")
  fi
done
assert_eq 5 "${#names[@]}" "theme count"

for name in "${names[@]}"; do
  run_capture "$BANCHY" theme validate "$name"
  assert_rc 0 "theme validate $name"

  wallpaper="$(grep -E '^WALLPAPER=' "$themes_dir/$name/theme.conf" | head -1 | cut -d= -f2-)"
  assert_nonempty "$wallpaper" "WALLPAPER in theme $name"
  if [[ "$wallpaper" != /* ]]; then
    wallpaper="$BANCHY_SHARE/wallpapers/$wallpaper"
  fi
  [[ -f "$wallpaper" ]] || t_fail "wallpaper for theme '$name' not found: $wallpaper"
done

run_capture "$BANCHY" theme list
assert_rc 0 "theme list"
assert_contains "$OUT" "THEME" "theme list header"

listed=0
for name in "${names[@]}"; do
  case "$OUT" in
    *" $name "*) listed=$((listed + 1)) ;;
  esac
done
assert_eq 5 "$listed" "theme list entries"

rows="$(printf '%s\n' "$OUT" | grep -cE '^[* ] +[A-Za-z0-9_-]+ ' || true)"
assert_eq 5 "$rows" "theme list rows"

t_ok "five themes, valid, wallpapers present, list is consistent"
