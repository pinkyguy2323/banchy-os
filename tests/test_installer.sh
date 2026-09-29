#!/usr/bin/env bash
# Installer helpers: answers files (aliases, malformed lines, missing file),
# package list merging and multilib detection, [multilib] toggling, the
# generated-password shape and the verification gate over a fake target.
#
# Only library functions are exercised: installer/banchy-install is an
# interactive main (it executes on source) and is covered by scripts/lint.sh
# (bash -n + shellcheck) instead.
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

t_setup

install_log="$WORK/install.log"
bad_key_probe() {
  # bad_key_probe <key...> — fails when any of them landed in B_ANS.
  local key
  for key in "$@"; do
    if [[ -n "${B_ANS[$key]+x}" ]]; then
      echo "invalid key accepted: $key"
      return 1
    fi
  done
  return 0
}

cat >"$WORK/answers.conf" <<'EOF'
# unattended answers
TARGET_DISK=/dev/sda
FILESYSTEM=btrfs
SWAP=4G
HOSTNAME=banchybox
LOCALE=it_IT.UTF-8
KEYMAP=it
TIMEZONE=UTC
PROFILE=gaming
USER_NAME=alice
USER_PASSWORD=secret
ROOT_PASSWORD=other
EOF

cat >"$WORK/answers-alias.conf" <<'EOF'
DISK=/dev/sdb
FS=ext4
USERNAME=bob
PASSWORD=hunter2
EOF

cat >"$WORK/answers-malformed.conf" <<'EOF'
# comment line
this line has no equals sign
1INVALID=x
BAD KEY=y
GOOD=value
EOF

# --- valid answers -----------------------------------------------------------
rc=0
# shellcheck disable=SC2030,SC2031 # exports must stay inside this subshell
out="$(
  set -euo pipefail
  export B_INSTALL_LOG="$install_log"
  source "$REPO/installer/lib/common.sh"
  answers_load "$WORK/answers.conf"
  answers_defaults
  printf 'disk=%s fs=%s swap=%s host=%s locale=%s keymap=%s tz=%s profile=%s\n' \
    "${B_ANS[TARGET_DISK]}" "${B_ANS[FILESYSTEM]}" "${B_ANS[SWAP]}" \
    "${B_ANS[HOSTNAME]}" "${B_ANS[LOCALE]}" "${B_ANS[KEYMAP]}" \
    "${B_ANS[TIMEZONE]}" "${B_ANS[PROFILE]}"
  printf 'user=%s userpass=%s rootpass=%s\n' \
    "${B_ANS[USER_NAME]}" "${B_ANS[USER_PASSWORD]}" "${B_ANS[ROOT_PASSWORD]}"
)" || rc=$?
if ((rc != 0)); then
  t_fail "valid answers file rejected rc=$rc: $out"
fi
assert_contains "$out" "disk=/dev/sda" "TARGET_DISK parsed"
assert_contains "$out" "fs=btrfs" "FILESYSTEM parsed"
assert_contains "$out" "host=banchybox" "HOSTNAME parsed"
assert_contains "$out" "profile=gaming" "PROFILE parsed"
assert_contains "$out" "user=alice" "USER_NAME parsed"
assert_contains "$out" "userpass=secret" "USER_PASSWORD parsed"
t_ok "answers file parses key=value pairs"

# --- documented aliases + malformed lines ------------------------------------
rc=0
# shellcheck disable=SC2030,SC2031 # exports must stay inside this subshell
out="$(
  set -euo pipefail
  export B_INSTALL_LOG="$install_log"
  source "$REPO/installer/lib/common.sh"
  answers_load "$WORK/answers-alias.conf"
  printf 'alias disk=%s fs=%s user=%s pass=%s\n' \
    "${B_ANS[TARGET_DISK]}" "${B_ANS[FILESYSTEM]}" \
    "${B_ANS[USER_NAME]}" "${B_ANS[USER_PASSWORD]}"
  answers_defaults
  printf 'default profile=%s locale=%s\n' "${B_ANS[PROFILE]}" "${B_ANS[LOCALE]}"
  B_ANS=()
  answers_load "$WORK/answers-malformed.conf"
  printf 'good=%s\n' "${B_ANS[GOOD]:-}"
  if ! bad_key_probe 1INVALID 'BAD KEY'; then
    exit 1
  fi
)" || rc=$?
if ((rc != 0)); then
  t_fail "alias/malformed answers group failed rc=$rc: $out"
fi
assert_contains "$out" "alias disk=/dev/sdb fs=ext4 user=bob pass=hunter2" \
  "DISK/FS/USERNAME/PASSWORD aliases mapped"
assert_contains "$out" "default profile=default" "defaults fill the gaps"
assert_contains "$out" "good=value" "valid line of a malformed file parsed"
t_ok "aliases resolve and malformed lines are skipped"

# --- missing answers file must die -------------------------------------------
rc=0
# shellcheck disable=SC2030,SC2031 # exports must stay inside this subshell
out="$(
  set -euo pipefail
  export B_INSTALL_LOG="$install_log"
  source "$REPO/installer/lib/common.sh"
  answers_load "$WORK/no-such-answers.conf" 2>&1
  echo "answers_load continued"
)" || rc=$?
if ((rc == 0)); then
  t_fail "a missing answers file was accepted: $out"
fi
assert_contains "$out" "answers file not found" "clear error for a missing file"
t_ok "missing answers file is fatal"

# --- synthetic lists: dedupe across includes + !multilib ---------------------
# Layout mirrors the installed share: $BANCHY_SHARE/packages/{base,desktop}.list
# plus $BANCHY_SHARE/packages/profiles/<name>.list.
share="$WORK/fakeshare"
mkdir -p "$share/packages/profiles"
printf 'alpha\nbeta\n' >"$share/packages/base.list"
printf 'beta\ngamma\n' >"$share/packages/desktop.list"
printf '!multilib\nalpha\ndelta\n' >"$share/packages/profiles/demo.list"

rc=0
# shellcheck disable=SC2030,SC2031 # exports must stay inside this subshell
out="$(
  set -euo pipefail
  export B_INSTALL_LOG="$install_log"
  export BANCHY_SHARE="$share"
  source "$REPO/installer/lib/common.sh"
  source "$REPO/installer/lib/packages.sh"
  pkg_resolve demo
  printf 'pkgs=%s\n' "${B_PKG_PKGS[*]}"
  printf 'flags=%s\n' "${B_PKG_FLAGS[*]:-}"
)" || rc=$?
if ((rc != 0)); then
  t_fail "synthetic package merge failed rc=$rc: $out"
fi
assert_contains "$out" "pkgs=alpha beta gamma delta" "dedupe across include chains"
assert_contains "$out" "flags=multilib" "!multilib directive collected"
t_ok "lists merge, dedupe and carry directives"

# --- real profiles -----------------------------------------------------------
rc=0
# shellcheck disable=SC2030,SC2031 # exports must stay inside this subshell
out="$(
  set -euo pipefail
  export B_INSTALL_LOG="$install_log"
  export BANCHY_SHARE="$STAGE/usr/share/banchy"
  source "$REPO/installer/lib/common.sh"
  source "$REPO/installer/lib/packages.sh"
  for profile in gaming full; do
    pkg_resolve "$profile"
    dupes="$(printf '%s\n' "${B_PKG_PKGS[@]}" | sort | uniq -d)"
    if [[ -n "$dupes" ]]; then
      echo "duplicate packages in $profile: $dupes"
      exit 1
    fi
    if ! pkg_needs_multilib; then
      echo "$profile must carry !multilib"
      exit 1
    fi
    printf '%s count=%d\n' "$profile" "${#B_PKG_PKGS[@]}"
  done
  for profile in minimal default; do
    pkg_resolve "$profile"
    if ((${#B_PKG_PKGS[@]} == 0)); then
      echo "$profile resolved to zero packages"
      exit 1
    fi
    dupes="$(printf '%s\n' "${B_PKG_PKGS[@]}" | sort | uniq -d)"
    if [[ -n "$dupes" ]]; then
      echo "duplicate packages in $profile: $dupes"
      exit 1
    fi
    if pkg_needs_multilib; then
      echo "$profile must not need multilib"
      exit 1
    fi
    printf '%s count=%d\n' "$profile" "${#B_PKG_PKGS[@]}"
  done
)" || rc=$?
if ((rc != 0)); then
  t_fail "real profile resolution failed rc=$rc: $out"
fi
assert_contains "$out" "gaming count=" "gaming resolves"
assert_contains "$out" "full count=" "full resolves"
assert_contains "$out" "minimal count=" "minimal resolves"
assert_contains "$out" "default count=" "default resolves"
t_ok "real profiles resolve without duplicates, multilib only where needed"

# --- [multilib] toggling -----------------------------------------------------
rc=0
# shellcheck disable=SC2030,SC2031 # exports must stay inside this subshell
out="$(
  set -euo pipefail
  export B_INSTALL_LOG="$install_log"
  source "$REPO/installer/lib/common.sh"
  source "$REPO/installer/lib/packages.sh"
  conf="$WORK/pacman-commented.conf"
  cat >"$conf" <<'PACMAN'
[options]
HoldPkg = pacman glibc
#[multilib]
#Include = /etc/pacman.d/mirrorlist
[core]
Include = /etc/pacman.d/mirrorlist
PACMAN
  pkg_enable_multilib_conf "$conf"
  printf 'commented=%s\n' "$(grep -c '^\[multilib\]$' "$conf" || true)"
  # Count Include lines *inside* the [multilib] section (the fixture already
  # has one under [core], so a whole-file count would be off by one).
  printf 'commented_include=%s\n' \
    "$(awk '/^\[multilib\]$/ { f = 1; next } /^\[/ { f = 0 } f && /^Include = / { c++ } END { print c + 0 }' "$conf")"
  pkg_enable_multilib_conf "$conf"
  printf 'idempotent=%s\n' "$(grep -c '^\[multilib\]$' "$conf" || true)"
  plain="$WORK/pacman-plain.conf"
  printf '[options]\n[core]\nInclude = /etc/pacman.d/mirrorlist\n' >"$plain"
  pkg_enable_multilib_conf "$plain"
  printf 'plain=%s\n' "$(grep -c '^\[multilib\]$' "$plain" || true)"
)" || rc=$?
if ((rc != 0)); then
  t_fail "[multilib] toggling failed rc=$rc: $out"
fi
assert_contains "$out" "commented=1" "commented [multilib] enabled"
assert_contains "$out" "commented_include=1" "Include line follows the section"
assert_contains "$out" "idempotent=1" "second call changes nothing"
assert_contains "$out" "plain=1" "missing section is appended"
t_ok "[multilib] toggling: uncomment, append, idempotent"
t_note "pkg_make_pacman_conf needs /etc/pacman.conf (live system) — not exercised here"

# --- generated password shape ------------------------------------------------
rc=0
# shellcheck disable=SC2030,SC2031 # exports must stay inside this subshell
out="$(
  set -euo pipefail
  export B_INSTALL_LOG="$install_log"
  source "$REPO/installer/lib/common.sh"
  first="$(i_gen_password)"
  second="$(i_gen_password)"
  if [[ ! "$first" =~ ^[A-Za-z0-9]{16}$ ]]; then
    echo "bad password shape: '$first'"
    exit 1
  fi
  if [[ ! "$second" =~ ^[A-Za-z0-9]{16}$ ]]; then
    echo "bad second password shape: '$second'"
    exit 1
  fi
  if [[ "$first" == "$second" ]]; then
    echo "generated passwords are identical"
    exit 1
  fi
  echo "passwords ok"
)" || rc=$?
if ((rc != 0)); then
  t_fail "i_gen_password failed rc=$rc: $out"
fi
t_ok "i_gen_password emits 16 alphanumeric characters, twice"

# --- verification gate -------------------------------------------------------
target="$WORK/target"
mkdir -p "$target/boot/loader/entries" "$target/etc" "$target/usr/bin"
for kernel in vmlinuz-linux initramfs-linux.img vmlinuz-linux-lts initramfs-linux-lts.img; do
  printf 'stub\n' >"$target/boot/$kernel"
done
cat >"$target/boot/loader/entries/01-banchy.conf" <<'EOF'
title   Banchy OS
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=banchy-test rw quiet
EOF
cat >"$target/etc/fstab" <<'EOF'
# /etc/fstab: static file system information.
UUID=banchy-test / ext4 defaults 0 1
EOF
cat >"$target/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
tester:x:1000:1000::/home/tester:/bin/bash
EOF
printf '#!/bin/sh\n' >"$target/usr/bin/banchy"
chmod +x "$target/usr/bin/banchy"

rc=0
# shellcheck disable=SC2030,SC2031,SC2317,SC2329 # scoped exports + run_chroot stub
out="$(
  set -euo pipefail
  export B_INSTALL_LOG="$install_log"
  export B_INSTALL_MNT="$target"
  source "$REPO/installer/lib/common.sh"
  source "$REPO/installer/lib/verify.sh"
  run_chroot() { return 0; }
  verify_run tester || exit $?
  exit 0
)" || rc=$?
assert_eq 0 "$rc" "verify_run on a complete fake target — output: $out"
t_ok "verification gate passes on a complete target"

rm -f "$target/boot/loader/entries/01-banchy.conf"
printf '# only comments\n' >"$target/etc/fstab"
rc=0
# shellcheck disable=SC2030,SC2031,SC2317,SC2329 # scoped exports + run_chroot stub
out="$(
  set -euo pipefail
  export B_INSTALL_LOG="$install_log"
  export B_INSTALL_MNT="$target"
  source "$REPO/installer/lib/common.sh"
  source "$REPO/installer/lib/verify.sh"
  run_chroot() { return 0; }
  verify_run tester || exit $?
  exit 0
)" || rc=$?
assert_eq 2 "$rc" "verify_run counts the failures — output: $out"
assert_contains "$out" "FAIL" "failures are reported as FAIL rows"
t_ok "verification gate returns the failed-check count"

t_ok "installer"
