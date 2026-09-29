#!/usr/bin/env bash
# iso/gen-packages.sh produces the gitignored pacman package list.
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

generator="$REPO/iso/gen-packages.sh"
assert_file "$generator"

out_file="$REPO/iso/profile/packages.x86_64"

run_capture bash "$generator"
assert_rc 0 "iso/gen-packages.sh"
assert_file "$out_file"

count="$(wc -l <"$out_file")"
count="${count//[[:space:]]/}"
if [[ ! "$count" =~ ^[0-9]+$ ]] || ((count == 0)); then
  t_fail "package count is not a positive integer: '$count'"
fi

bad="$(awk '!/^[a-z0-9@._+-]+$/ { print; exit }' "$out_file")"
if [[ -n "$bad" ]]; then
  t_fail "invalid package name in the generated list: '$bad'"
fi

grep -q 'iso/profile/packages.x86_64' "$REPO/.gitignore" ||
  t_fail "iso/profile/packages.x86_64 is not gitignored"

t_ok "gen-packages produced $count valid package names, gitignored"
