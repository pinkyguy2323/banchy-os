#!/usr/bin/env bash
# apply --check writes nothing, apply renders all 14 manifest targets,
# light mode and accent overrides land in the generated files, and
# user-modified files are left alone unless --force is given.
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

t_setup

manifest="$BANCHY_SHARE/templates/manifest"
assert_file "$manifest"

targets=()
while read -r tmpl rel _; do
  if [[ -z "${tmpl:-}" || "$tmpl" == \#* ]]; then
    continue
  fi
  targets+=("$rel")
done <"$manifest"
assert_eq 14 "${#targets[@]}" "manifest target count"

run_capture "$BANCHY" apply --check
assert_rc 0 "apply --check"
for rel in "${targets[@]}"; do
  assert_no_file "$HOME/$rel"
done
if [[ -d "$XDG_CONFIG_HOME" ]]; then
  leftovers="$(find "$XDG_CONFIG_HOME" -type f | head -3 || true)"
  if [[ -n "$leftovers" ]]; then
    t_fail "apply --check wrote into the home directory: $leftovers"
  fi
fi
t_ok "apply --check is a pure dry run"

run_capture "$BANCHY" apply
assert_rc 0 "apply"
hypr="$HOME/.config/banchy/generated/hypr-dynamic.conf"
for rel in "${targets[@]}"; do
  file="$HOME/$rel"
  assert_file "$file"
  if ! grep -q "Managed by Banchy OS" "$file"; then
    t_fail "marker missing in rendered file: $rel"
  fi
  if grep -q '{{' "$file"; then
    t_fail "unresolved placeholder in $rel"
  fi
done
grep -q '#6C8CFF' "$hypr" || t_fail "midnight accent missing from hypr-dynamic"
t_ok "apply renders all 14 targets with markers and no placeholders"

run_capture "$BANCHY" set mode light
assert_rc 0 "set mode light"
grep -q '#F5F7FA' "$HOME/.config/waybar/style.css" ||
  t_fail "light palette missing from waybar style"
t_ok "mode=light renders the light palette"

run_capture "$BANCHY" set accent '#FF0000'
assert_rc 0 "set accent"
grep -q '#FF0000' "$hypr" || t_fail "accent override missing from hypr-dynamic"
t_ok "accent override lands in hypr-dynamic"

run_capture "$BANCHY" set mode dark
assert_rc 0 "restore dark"
run_capture "$BANCHY" set accent ''
assert_rc 0 "clear accent"
if grep -q '#F5F7FA' "$HOME/.config/waybar/style.css"; then
  t_fail "light colour still present after returning to dark"
fi
t_ok "dark mode restored"

target="$HOME/.config/waybar/style.css"
sed -i '/Managed by Banchy OS/d' "$target"
printf '\n/* USEREDIT */\n' >>"$target"
run_capture "$BANCHY" apply
assert_rc 0 "apply over a user-modified file"
grep -q 'USEREDIT' "$target" || t_fail "apply overwrote a user-modified file"
if grep -q 'Managed by Banchy OS' "$target"; then
  t_fail "user-modified file was replaced despite the protection"
fi
run_capture "$BANCHY" apply --force
assert_rc 0 "apply --force"
if grep -q 'USEREDIT' "$target"; then
  t_fail "--force did not overwrite the user-modified file"
fi
grep -q 'Managed by Banchy OS' "$target" || t_fail "marker missing after --force"
t_ok "user-modified protection honours --force"

t_ok "render pipeline"
