# shellcheck shell=bash
# banchy update — safe rolling-release system update.
#
# pre-flight  -> backup -> snapshot (btrfs) -> pacman -Syu -> post-flight
# Any failed critical post-check produces an explicit rollback guidance block.

b_update_have_network() {
  if ! b_have curl; then
    b_have ping && ping -c1 -W5 archlinux.org >/dev/null 2>&1
    return $?
  fi
  curl -fsSI -m 10 https://archlinux.org/ >/dev/null 2>&1
}

b_update_free_space_gb() {
  df -P --output=avail / 2>/dev/null | tail -1 | awk '{ printf "%.1f", $1/1024/1024 }'
}

b_update_snapshot() {
  # Best-effort read-only Btrfs snapshot before the update.
  local fstype
  fstype="$(findmnt -rn -o FSTYPE / 2>/dev/null | head -1)"
  [[ "$fstype" == "btrfs" ]] || return 0
  if [[ ! -d /.snapshots ]]; then
    b_info "btrfs detected but /.snapshots missing — skipping snapshot"
    return 0
  fi
  local name
  name="/.snapshots/banchy-pre-update-$(date +%Y%m%d-%H%M%S)"
  if b_sudo btrfs subvolume snapshot -r / "$name" >/dev/null 2>&1; then
    b_ok "snapshot created: $name"
  else
    b_warn "could not create btrfs snapshot (continuing)"
  fi
}

b_update_postflight() {
  local rc=0
  b_header "Post-update verification"

  # Kernel + initramfs on disk.
  if [[ -f /boot/vmlinuz-linux && -f /boot/initramfs-linux.img ]]; then
    b_ok "kernel + initramfs present"
  else
    b_fail "kernel or initramfs missing under /boot"
    rc=1
  fi

  # Boot entries.
  local boot_rc=0
  b_boot_check >/dev/null 2>&1 || boot_rc=$?
  if ((boot_rc == 0)); then
    b_ok "Banchy Boot entries valid"
  else
    b_fail "Banchy Boot verification failed ($boot_rc problem(s))"
    b_info "attempting automatic boot repair..."
    if b_boot__install --auto >/dev/null 2>&1; then
      b_ok "automatic boot repair succeeded"
    else
      b_fail "automatic boot repair failed — boot from 'Previous Kernel' if needed"
      rc=1
    fi
  fi

  # Failed systemd units.
  local failed
  failed="$(systemctl --failed --no-legend --no-pager 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
  if [[ -z "${failed// /}" ]]; then
    b_ok "no failed systemd units"
  else
    b_warn "failed units after update: $failed"
  fi

  # Banchy configuration still renders.
  if b_apply --check >/dev/null 2>&1; then
    b_ok "Banchy configuration renders"
  else
    b_fail "Banchy configuration is broken after update"
    rc=1
  fi

  # Package database sanity.
  if [[ -z "$(pacman -Dk 2>&1 || true)" ]]; then
    b_ok "package database"
  else
    b_warn "package database reports issues: $(pacman -Dk 2>&1 | head -1)"
  fi

  return $rc
}

banchy_cmd_update() {
  local check_only=0
  [[ "${1:-}" == "--check" ]] && check_only=1

  b_header "Banchy OS system update"

  # ---- PRE-FLIGHT ----
  b_info "step 1/6: pre-flight checks"
  local pre_fail=0

  if b_update_have_network; then
    b_ok "network reachable"
  else
    b_fail "no internet connection"
    pre_fail=1
  fi

  local free_gb
  free_gb="$(b_update_free_space_gb)"
  if b_math "$free_gb >= 2.0" >/dev/null 2>&1; then
    b_ok "disk space: ${free_gb} GB free"
  else
    b_fail "not enough disk space: ${free_gb} GB (need >= 2 GB)"
    pre_fail=1
  fi

  if [[ -z "$(pacman -Dk 2>&1 || true)" ]]; then
    b_ok "pacman database healthy"
  else
    b_fail "pacman database has issues — run 'pacman -Dk' first"
    pre_fail=1
  fi

  if ((BANCHY_LIVE == 0)); then
    local boot_rc=0
    b_boot_check >/dev/null 2>&1 || boot_rc=$?
    if ((boot_rc == 0)); then
      b_ok "boot configuration healthy"
    else
      b_fail "boot configuration is broken — run 'banchy boot check' first"
      pre_fail=1
    fi
  fi

  if ((pre_fail)); then
    b_err "pre-flight checks failed — update aborted, nothing was changed"
    return 1
  fi

  if ((check_only)); then
    b_ok "ready to update (dry run — nothing changed)"
    return 0
  fi

  # ---- BACKUP ----
  b_info "step 2/6: configuration backup"
  b_config_backup "pre-update" >/dev/null
  b_ok "configuration backup complete"

  # ---- SNAPSHOT ----
  b_info "step 3/6: filesystem snapshot"
  b_update_snapshot

  # ---- UPDATE ----
  b_info "step 4/6: applying update (pacman -Syu)"
  if [[ -t 0 ]]; then
    b_confirm "Start the system update now?" || { b_info "cancelled"; return 0; }
  fi
  b_ensure_root
  local rc=0
  if ! b_sudo pacman -Syu --color auto; then
    b_fail "pacman reported errors during the update"
    b_info "check the output above; fix and re-run 'banchy update'"
    b_info "your configuration backup is safe in $BANCHY_BACKUP_DIR"
    return 1
  fi

  # ---- POST-FLIGHT ----
  b_info "step 5/6: verification"
  rc=0
  b_update_postflight || rc=$?

  # ---- REPORT ----
  b_info "step 6/6: summary"
  if ((rc == 0)); then
    b_ok "update completed and verified"
    b_info "a reboot is recommended if the kernel was updated"
    if b_have notify-send && pgrep -x Hyprland >/dev/null 2>&1; then
      notify-send -u low "Banchy OS" "System update completed successfully." 2>/dev/null || true
    fi
    return 0
  fi
  b_fail "update finished but verification found problems"
  cat <<EOF

  Rollback guidance:
    * Boot previous kernel:  restart and pick 'Banchy OS - Previous Kernel'
    * Restore configs:       banchy config restore
    * Repair boot entries:   banchy boot repair
    * Inspect failed units:  systemctl --failed
    * Package snapshot:      btrfs snapshots in /.snapshots (if enabled)
EOF
  return 1
}
