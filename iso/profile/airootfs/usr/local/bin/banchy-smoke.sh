#!/usr/bin/env bash
# Banchy OS live ISO smoke test — run by banchy-smoke.service.
# Success prints BANCHY_SMOKE_OK to stdout and /dev/console; failure prints
# BANCHY_SMOKE_FAIL plus the failing check. The markers land in the journal
# and on the serial console for humans/CI logs; pass/fail of CI itself comes
# from the interactive checks in scripts/vm-smoke.exp.
set -u

fail() {
  echo "BANCHY_SMOKE_FAIL: $1" >&2
  echo "BANCHY_SMOKE_FAIL: $1" > /dev/console 2>/dev/null || true
  exit 1
}

command -v banchy >/dev/null 2>&1 || fail "banchy CLI not found in PATH"
banchy version >/dev/null 2>&1 || fail "'banchy version' exited non-zero"
systemctl is-active --quiet NetworkManager || fail "NetworkManager is not active"
id -u banchy >/dev/null 2>&1 || fail "live user 'banchy' does not exist"
[[ -f /etc/banchy-live ]] || fail "/etc/banchy-live marker missing"

echo "BANCHY_SMOKE_OK"
echo "BANCHY_SMOKE_OK" > /dev/console 2>/dev/null || true
