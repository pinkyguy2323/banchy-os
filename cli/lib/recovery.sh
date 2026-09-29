# shellcheck shell=bash
# banchy recovery — launch the recovery menu (root shell context).

banchy_cmd_recovery() {
  local script
  for script in "$BANCHY_SHARE/recovery/banchy-recovery" \
                "/usr/share/banchy/recovery/banchy-recovery" \
                "$BANCHY_LIB/../../boot/recovery/banchy-recovery"; do
    if [[ -x "$script" ]]; then
      exec "$script" "$@"
    fi
    if [[ -f "$script" ]]; then
      exec bash "$script" "$@"
    fi
  done
  b_err "recovery tool not installed (banchy-recovery)"
  b_info "Boot from the 'Banchy OS — Recovery' entry in Banchy Boot, then run:"
  b_info "  banchy boot repair     # reinstall bootloader entries"
  b_info "  banchy config restore  # restore configuration backup"
  b_info "  mkinitcpio -P          # regenerate initramfs"
  b_info "  pacman -Dk             # verify package database"
  return 1
}
