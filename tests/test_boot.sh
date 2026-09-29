#!/usr/bin/env bash
# systemd-boot entries: four entries, disabled editor, and a clean boot check.
#
# The real findmnt/blkid helpers need util-linux and would resolve the *host*
# mounts instead of the temporary ESP below, so the three mount probes are
# replaced with test doubles. That keeps this test deterministic on CI and on
# Windows; the entry writer and the checker logic themselves are untouched.
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

t_setup
# shellcheck source=/dev/null
source "$BANCHY_LIB/common.sh"
# shellcheck source=/dev/null
source "$BANCHY_LIB/boot.sh"

b_boot_esp() { printf '%s/boot\n' "${1:-/}"; }
b_boot_root_params() { printf 'root=UUID=banchy-test-uuid\n'; }
findmnt() { printf 'vfat\n'; }

root="$WORK/fakeroot"
mkdir -p "$root/boot"
for kernel in vmlinuz-linux initramfs-linux.img vmlinuz-linux-lts initramfs-linux-lts.img; do
  printf 'stub\n' >"$root/boot/$kernel"
done

rc=0
out="$(b_boot_write_entries "$root" 0 2>&1)" || rc=$?
if ((rc != 0)); then
  t_fail "b_boot_write_entries failed rc=$rc: $out"
fi

loader="$root/boot/loader/loader.conf"
assert_file "$loader"
grep -q '^timeout' "$loader" || t_fail "loader.conf has no timeout"
grep -q '^editor no$' "$loader" || t_fail "loader.conf does not disable the editor"
grep -q '^default 01-banchy' "$loader" || t_fail "loader.conf has no default entry"

for entry in 01-banchy 02-banchy-previous 03-banchy-recovery 04-banchy-verbose; do
  assert_file "$root/boot/loader/entries/$entry.conf"
done

grep -q 'vmlinuz-linux-lts' "$root/boot/loader/entries/02-banchy-previous.conf" ||
  t_fail "02-banchy-previous does not reference the lts kernel"
grep -q 'systemd.unit=rescue.target' "$root/boot/loader/entries/03-banchy-recovery.conf" ||
  t_fail "03-banchy-recovery lacks rescue.target"
if grep -q 'rescue.target' "$root/boot/loader/entries/01-banchy.conf"; then
  t_fail "01-banchy must not reference rescue.target"
fi
grep -q 'vmlinuz-linux\b' "$root/boot/loader/entries/01-banchy.conf" ||
  t_fail "01-banchy does not reference the main kernel"
if grep -q 'quiet' "$root/boot/loader/entries/04-banchy-verbose.conf"; then
  t_fail "04-banchy-verbose must not use the quiet flag"
fi
t_ok "loader.conf and all four boot entries"

rc=0
out="$(b_boot_check --root "$root" 2>&1)" || rc=$?
if ((rc != 0)); then
  t_fail "b_boot_check failed rc=$rc: $out"
fi
t_ok "b_boot_check passes on a complete fake target"

t_ok "boot"
