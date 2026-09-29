# shellcheck shell=bash
# Banchy installer — verification gate. Runs before any reboot is offered.
# Prints a PASS/FAIL table; verify_run returns the number of failed checks
# (0 = pass).
set -euo pipefail

declare -ga B_VERIFY_FAILS=()

v_row() {
  # v_row <PASS|WARN|FAIL> <label> [detail]
  local st="$1" label="$2" detail="${3:-}"
  case "$st" in
    PASS)
      printf '%sPASS%s  %s%s\n' "$C_GREEN" "$C_RESET" "$label" "${detail:+ — $detail}"
      ;;
    WARN)
      printf '%sWARN%s  %s%s\n' "$C_YELLOW" "$C_RESET" "$label" "${detail:+ — $detail}"
      ;;
    FAIL)
      printf '%sFAIL%s  %s%s\n' "$C_RED" "$C_RESET" "$label" "${detail:+ — $detail}"
      B_VERIFY_FAILS+=("$label${detail:+ — $detail}")
      ;;
  esac
  log "VERIFY $st: $label${detail:+ — $detail}"
  return 0
}

v_run_capture() {
  # v_run_capture <label> <cmd...> — PASS when the command exits 0; on
  # failure show the captured output indented under the FAIL row.
  local label="$1"
  shift
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  if ((rc == 0)); then
    v_row PASS "$label"
  else
    v_row FAIL "$label" "exit $rc"
    while IFS= read -r line; do
      printf '       %s\n' "$line"
    done <<<"$out"
  fi
  return 0
}

verify_run() {
  # verify_run <user> — table over the target at $MNT; returns fail count.
  local user="$1" k missing
  B_VERIFY_FAILS=()
  b_header "Verification gate"

  # 1. ESP loader entry.
  if [[ -f "$MNT/boot/loader/entries/01-banchy.conf" ]]; then
    v_row PASS "ESP entry 01-banchy.conf"
  else
    v_row FAIL "ESP entry 01-banchy.conf" "missing under /boot/loader/entries"
  fi

  # 2. Kernel files on the ESP (required by 01-banchy.conf).
  missing=""
  for k in vmlinuz-linux initramfs-linux.img; do
    [[ -f "$MNT/boot/$k" ]] || missing+="$k "
  done
  if [[ -z "$missing" ]]; then
    v_row PASS "kernel files on ESP" "vmlinuz-linux, initramfs-linux.img"
  else
    v_row FAIL "kernel files on ESP" "missing: $missing"
  fi

  # 3. Fallback kernel (always installed per BOOT.md).
  if [[ -f "$MNT/boot/vmlinuz-linux-lts" && -f "$MNT/boot/initramfs-linux-lts.img" ]]; then
    v_row PASS "fallback kernel (linux-lts)"
  else
    v_row WARN "fallback kernel (linux-lts)" "previous-kernel entry unavailable"
  fi

  # 4. banchy boot check inside the chroot.
  v_run_capture "banchy boot check (chroot)" run_chroot banchy boot check

  # 5. Render check for the future user's configuration.
  if [[ -n "$user" && "$user" != "-" ]]; then
    v_run_capture "configuration render (apply --check)" \
      run_chroot banchy apply --no-reload --root "/home/$user" --check
  else
    v_row WARN "configuration render (apply --check)" "no user selected yet"
  fi

  # 6. fstab must be non-empty (more than comments/blank lines).
  if [[ -s "$MNT/etc/fstab" ]] && grep -qvE '^[[:space:]]*(#|$)' "$MNT/etc/fstab"; then
    v_row PASS "/etc/fstab has entries"
  else
    v_row FAIL "/etc/fstab has entries"
  fi

  # 7. Primary user account.
  if [[ -n "$user" && "$user" != "-" ]] && grep -q "^${user}:" "$MNT/etc/passwd" 2>/dev/null; then
    v_row PASS "user account" "$user in /etc/passwd"
  else
    v_row FAIL "user account" "${user:-<none>} not found in /etc/passwd"
  fi

  # 8. banchy CLI in the target.
  if [[ -x "$MNT/usr/bin/banchy" ]]; then
    v_row PASS "/usr/bin/banchy installed"
  else
    v_row FAIL "/usr/bin/banchy installed" "missing or not executable"
  fi

  local fails="${#B_VERIFY_FAILS[@]}"
  if ((fails > 0)); then
    b_fail "verification: $fails check(s) failed"
  else
    b_ok "verification: all checks passed"
  fi
  return "$fails"
}
