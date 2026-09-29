#!/usr/bin/env bash
# get/set round trip, invalid key, invalid value, mode switch.
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

t_setup

settings="$XDG_CONFIG_HOME/banchy/settings.conf"

run_capture "$BANCHY" get theme
assert_rc 0 "banchy get theme"
assert_eq "midnight" "$OUT" "default theme"

run_capture "$BANCHY" set theme black
assert_rc 0 "set theme black"
run_capture "$BANCHY" get theme
assert_eq "black" "$OUT" "theme after set"

before="$(digest_file "$settings")"
run_capture "$BANCHY" set not_a_real_key 1
if [[ "$RC" -eq 0 ]]; then
  t_fail "invalid key was accepted (rc=0) — output: $OUT"
fi
after="$(digest_file "$settings")"
assert_eq "$before" "$after" "settings file untouched after invalid key"

before="$after"
run_capture "$BANCHY" set border_size abc
if [[ "$RC" -eq 0 ]]; then
  t_fail "border_size=abc was accepted (rc=0) — output: $OUT"
fi
after="$(digest_file "$settings")"
assert_eq "$before" "$after" "settings file untouched after invalid value"

run_capture "$BANCHY" get border_size
assert_rc 0 "get border_size"
assert_eq "2" "$OUT" "border_size kept its default"

run_capture "$BANCHY" set mode light
assert_rc 0 "set mode light"
run_capture "$BANCHY" get mode
assert_eq "light" "$OUT" "mode after set"

t_ok "get/set round trip, invalid key and value rejected"
