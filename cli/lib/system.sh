# shellcheck shell=bash
# banchy system check — quick system status subset.

banchy_cmd_system() {
  local sub="${1:-check}"
  shift || true
  case "$sub" in
    check)
      local filter="quick"
      [[ "${1:-}" == "--full" ]] && filter="all"
      # Reuse the doctor machinery with a subset of checks.
      banchy_cmd_doctor "$filter"
      ;;
    status)
      if b_have systemctl; then
        systemctl is-system-running 2>/dev/null || true
      fi
      ;;
    *) b_err "usage: banchy system [check|status]"; return 2 ;;
  esac
}
