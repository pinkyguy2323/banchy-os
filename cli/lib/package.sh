# shellcheck shell=bash
# banchy package — thin, safe wrapper around pacman.

b_package_log() {
  mkdir -p "$BANCHY_STATE_DIR"
  printf '%s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "${*:2}" \
    >>"$BANCHY_STATE_DIR/packages.log"
}

b_package_install_do() {
  local -a pkgs=("$@")
  [[ ${#pkgs[@]} -gt 0 ]] || { b_err "no packages given"; return 2; }
  b_ensure_root
  b_package_log install "${pkgs[@]}"
  if b_sudo pacman -S --needed --noconfirm --color auto "${pkgs[@]}"; then
    b_ok "installed: ${pkgs[*]}"
    return 0
  fi
  b_err "pacman failed for: ${pkgs[*]}"
  return 1
}

banchy_cmd_package() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    install)
      [[ $# -gt 0 ]] || { b_err "usage: banchy package install <pkg...>"; return 2; }
      b_header "Install packages"
      printf '  %s\n' "$@"
      b_confirm "Proceed?" || { b_info "cancelled"; return 0; }
      b_package_install_do "$@"
      ;;
    remove)
      [[ $# -gt 0 ]] || { b_err "usage: banchy package remove <pkg...>"; return 2; }
      b_header "Remove packages"
      printf '  %s\n' "$@"
      b_confirm "Remove these packages (and unused dependencies)?" || {
        b_info "cancelled"
        return 0
      }
      b_ensure_root
      b_package_log remove "$@"
      if b_sudo pacman -Rns --noconfirm --color auto "$@"; then
        b_ok "removed: $*"
        return 0
      fi
      b_err "pacman removal failed"
      return 1
      ;;
    *)
      b_err "usage: banchy package [install|remove] <pkg...>"
      return 2
      ;;
  esac
}
