# shellcheck shell=bash
# banchy keys — pretty-print the Hyprland keybindings.
# Keybindings are parsed from the default keybindings.conf so that the file
# remains the single source of truth. A comment line directly above a bind
# becomes its description. Parsing is pure bash (no cut/sed/xargs per line).

b_keys_trim() {
  # trim leading/trailing whitespace in $1
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

banchy_cmd_keys() {
  local xdg="${XDG_CONFIG_HOME:-$HOME/.config}"
  local file="$xdg/hypr/keybindings.conf"
  if [[ ! -f "$file" ]]; then
    file="$BANCHY_SHARE/defaults/hypr/keybindings.conf"
  fi
  if [[ ! -f "$file" ]]; then
    b_err "keybindings file not found"
    return 1
  fi

  b_header "Banchy OS keybindings"

  local pending="" line rest mods key dispatcher args
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Trim leading whitespace.
    line="${line#"${line%%[![:space:]]*}"}"
    if [[ "$line" == "#"* ]]; then
      pending="${line#\#}"
      pending="$(b_keys_trim "$pending")"
      continue
    fi
    if [[ "$line" =~ ^bind[a-z]*[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      rest="${BASH_REMATCH[1]}"
      # Split "MODS, KEY, DISPATCHER, ARGS..." — the last field keeps its commas.
      IFS=',' read -r mods key dispatcher args <<<"$rest"
      mods="$(b_keys_trim "$mods")"
      key="$(b_keys_trim "$key")"
      dispatcher="$(b_keys_trim "$dispatcher")"
      args="$(b_keys_trim "$args")"

      local combo="$mods+$key"
      combo="${combo//SUPER SHIFT/SUPER+SHIFT}"
      combo="${combo//SUPER CTRL/SUPER+CTRL}"
      combo="${combo//SUPER ALT/SUPER+ALT}"
      combo="${combo//,/+}"
      combo="${combo//SHIFT+/Shift+}"
      combo="${combo//CTRL+/Ctrl+}"
      combo="${combo//ALT+/Alt+}"
      combo="${combo//SUPER/Super}"

      local desc="$pending"
      if [[ -z "$desc" ]]; then
        local arrow="$args"
        case "$args" in
          l) arrow="left" ;;
          d) arrow="down" ;;
          u) arrow="up" ;;
          r) arrow="right" ;;
        esac
        case "$dispatcher" in
          exec) desc="$args" ;;
          killactive) desc="Close active window" ;;
          togglefloating) desc="Toggle floating" ;;
          fullscreen) desc="Toggle fullscreen" ;;
          movefocus) desc="Focus window $arrow" ;;
          movewindow) desc="Move window $arrow" ;;
          workspace) desc="Switch to workspace $args" ;;
          movetoworkspace) desc="Move window to workspace $args" ;;
          locksession) desc="Lock screen" ;;
          exit) desc="Exit Hyprland" ;;
          *) desc="$dispatcher" ;;
        esac
      fi
      printf '%-18s %s\n' "$combo" "$desc"
      pending=""
    fi
  done <"$file"

  printf '\n'
  b_info "edit: $file"
  return 0
}
