# shellcheck shell=bash
# banchy info — Banchy-branded system information.

banchy_cmd_info() {
  b_settings_load 2>/dev/null || true

  local kernel wm theme accent pkgs uptime_s
  kernel="$(uname -r)"
  wm="Hyprland"
  if b_have hyprctl && hyprctl version >/dev/null 2>&1; then
    wm="$(hyprctl version 2>/dev/null | head -1 | sed 's/^Hyprland //; s/ .*//')"
    wm="Hyprland ${wm%% *}"
  fi
  theme="${B_SET[theme]:-unknown}"
  accent="${B_SET[accent]:-}"
  [[ -n "$accent" ]] || accent="(from theme)"
  pkgs="$(pacman -Q 2>/dev/null | wc -l)"
  uptime_s="$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)"

  local up_d up_h up_m
  up_d=$((uptime_s / 86400))
  up_h=$(((uptime_s % 86400) / 3600))
  up_m=$(((uptime_s % 3600) / 60))
  local uptime_str=""
  ((up_d)) && uptime_str+="${up_d}d "
  ((up_h)) && uptime_str+="${up_h}h "
  uptime_str+="${up_m}m"

  printf '%s\n' "${C_CYAN}"
  cat "$BANCHY_SHARE/branding/logo-ascii.txt" 2>/dev/null || echo "Banchy OS"
  printf '%s\n' "${C_RESET}"

  printf '  %-12s %s\n' "OS" "Banchy OS $(cat "$BANCHY_SHARE/version" 2>/dev/null || echo "${BANCHY_VERSION:-0.1.0}")"
  printf '  %-12s %s\n' "Base" "Arch Linux (rolling)"
  printf '  %-12s %s\n' "Kernel" "$kernel"
  printf '  %-12s %s\n' "WM" "$wm"
  printf '  %-12s %s\n' "Theme" "$theme"
  printf '  %-12s %s\n' "Accent" "$accent"
  printf '  %-12s %s\n' "Terminal" "kitty"
  printf '  %-12s %s\n' "Shell" "${SHELL##*/} $BASH_VERSION"
  printf '  %-12s %s\n' "Uptime" "$uptime_str"
  printf '  %-12s %s\n' "Packages" "$pkgs"
  printf '  %-12s %s\n' "Host" "$(hostname 2>/dev/null || echo unknown)"
  return 0
}
