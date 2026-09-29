# shellcheck shell=bash
# Banchy installer — stage Banchy files into the target and install the
# bootloader there ('banchy boot install' inside the chroot), with cleanup
# guidance on failure.
set -euo pipefail

boot_stage_files() {
  # Copy the Banchy repository into the target via scripts/install-files.sh.
  local repo script
  if ! repo="$(i_repo_dir)"; then
    die "Banchy sources not found: the live system must provide /usr/local/src/banchy-os (or run the installer from a repository checkout). Cannot stage Banchy files without them."
  fi
  script="$repo/scripts/install-files.sh"
  [[ -f "$script" ]] || die "staging script missing: $script"
  b_header "Staging Banchy files"
  i_cmd "$script" --root "$MNT"
  "$script" --root "$MNT"
  b_ok "Banchy files staged into $MNT"
}

boot_install_target() {
  # boot_install_target [--serial] — run 'banchy boot install' in the chroot.
  local serial=0
  [[ "${1:-}" == "--serial" ]] && serial=1
  local -a args=()
  if ((serial)); then
    args+=(--serial)
  fi
  b_header "Bootloader (Banchy Boot)"
  if run_chroot banchy boot install ${args[@]+"${args[@]}"}; then
    b_ok "bootloader installed — loader.conf and boot entries written"
    return 0
  fi

  # Failure cleanup: never proceed to verification or a reboot from here.
  b_fail "banchy boot install failed inside the target"
  log "FAIL: banchy boot install failed (serial=$serial)"
  b_info "the ESP was not (fully) configured — rebooting is blocked"
  b_info "recover with 'banchy boot repair' (recovery entry or a live shell),"
  b_info "then re-run 'banchy-install' or the verification gate from the menu"
  return 1
}
