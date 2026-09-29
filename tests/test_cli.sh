#!/usr/bin/env bash
# Version, help, unknown command, and keys list.
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

t_setup

expected="$(tr -d '[:space:]' <"$REPO/version")"
assert_nonempty "$expected" "version file"

run_capture "$BANCHY" version
assert_rc 0 "banchy version"
assert_contains "$OUT" "$expected" "version output"

run_capture "$BANCHY" help
assert_rc 0 "banchy help"
assert_contains "$OUT" "Usage:" "help usage"

run_capture "$BANCHY" definitely-not-a-command
assert_rc 2 "unknown command"

run_capture "$BANCHY" keys
assert_rc 0 "banchy keys"
assert_nonempty "$OUT" "banchy keys output"

t_ok "version, help, unknown command, keys"
