# shellcheck shell=bash
# Banchy Theme Engine: list / validate / set / create themes.

B_THEME_REQUIRED_KEYS=(
  NAME DISPLAY_NAME MODE
  BG SURFACE SURFACE_ALT TEXT TEXT_DIM
  ACCENT ACCENT_ALT BORDER_ACTIVE BORDER_INACTIVE
  DANGER WARNING SUCCESS WALLPAPER
)

b_theme_user_dir() {
  echo "${XDG_CONFIG_HOME:-$HOME/.config}/banchy/themes"
}

# Print the file backing a theme (user themes override system themes).
b_theme_file() {
  local name="$1"
  [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  local user_file system_file
  user_file="$(b_theme_user_dir)/$name/theme.conf"
  system_file="$BANCHY_SHARE/themes/$name/theme.conf"
  if [[ -f "$user_file" ]]; then
    echo "$user_file"
    return 0
  fi
  if [[ -f "$system_file" ]]; then
    echo "$system_file"
    return 0
  fi
  return 1
}

b_theme_names() {
  local -A seen=()
  local d name
  for d in "$BANCHY_SHARE"/themes/*/theme.conf; do
    [[ -f "$d" ]] || continue
    name="$(basename "$(dirname "$d")")"
    seen["$name"]=1
  done
  for d in "$(b_theme_user_dir)"/*/theme.conf; do
    [[ -f "$d" ]] || continue
    name="$(basename "$(dirname "$d")")"
    seen["$name"]=1
  done
  local k
  for k in "${!seen[@]}"; do
    echo "$k"
  done | sort
}

b_theme_current() {
  b_settings_load
  echo "${B_SET[theme]:-}"
}

b_theme_validate() {
  local name="$1"
  local file
  if ! file="$(b_theme_file "$name")"; then
    b_err "theme '$name' does not exist"
    return 1
  fi

  local -A T=()
  b_kv_load "$file" T || {
    b_err "cannot parse $file"
    return 1
  }

  local k errors=0
  for k in "${B_THEME_REQUIRED_KEYS[@]}"; do
    if [[ -z "${T[$k]:-}" ]]; then
      b_err "theme '$name': missing key $k"
      errors=$((errors + 1))
    fi
  done
  ((errors == 0)) || return 1

  # Color keys must be valid hex.
  for k in BG SURFACE SURFACE_ALT TEXT TEXT_DIM ACCENT ACCENT_ALT \
           BORDER_ACTIVE BORDER_INACTIVE DANGER WARNING SUCCESS \
           LIGHT_BG LIGHT_SURFACE LIGHT_SURFACE_ALT LIGHT_TEXT LIGHT_TEXT_DIM \
           LIGHT_BORDER_INACTIVE; do
    if [[ -n "${T[$k]:-}" ]] && ! b_is_hex "${T[$k]}"; then
      b_err "theme '$name': $k is not a valid hex color: ${T[$k]}"
      errors=$((errors + 1))
    fi
  done

  # Wallpaper must resolve to a real file.
  local wp="${T[WALLPAPER]}"
  if [[ "$wp" != /* ]]; then
    if [[ -f "$(dirname "$file")/$wp" ]]; then
      wp="$(dirname "$file")/$wp"
    else
      wp="$BANCHY_SHARE/wallpapers/$wp"
    fi
  fi
  if [[ ! -f "$wp" ]]; then
    b_err "theme '$name': wallpaper not found: ${T[WALLPAPER]}"
    errors=$((errors + 1))
  fi

  # Light mode requires a complete light palette.
  if [[ "${T[MODE]:-dark}" == "light" ]]; then
    : # theme is inherently light; fine
  fi

  ((errors == 0)) || return 1
  return 0
}

b_theme_cmd_list() {
  local current
  current="$(b_theme_current)"
  local name file display marker
  printf '%-12s %-22s %s\n' "THEME" "NAME" "ACCENT"
  printf '%-12s %-22s %s\n' "------------" "----------------------" "------"
  while read -r name; do
    [[ -n "$name" ]] || continue
    marker=" "
    [[ "$name" == "$current" ]] && marker="*"
    file="$(b_theme_file "$name")"
    display="$(grep -E '^DISPLAY_NAME=' "$file" | head -1 | cut -d= -f2- | tr -d '"')"
    local accent
    accent="$(grep -E '^ACCENT=' "$file" | head -1 | cut -d= -f2-)"
    printf '%s %-10s %-22s %s\n' "$marker" "$name" "${display:-$name}" "$accent"
  done < <(b_theme_names)
  b_info "* = active theme"
}

b_theme_cmd_set() {
  local name="${1:-}"
  [[ -n "$name" ]] || { b_err "usage: banchy theme set <name>"; return 2; }
  b_theme_validate "$name" || return 1
  b_settings_set theme "$name" || return 1
  if b_apply; then
    b_ok "theme: $name"
    if b_have notify-send && pgrep -x Hyprland >/dev/null 2>&1; then
      notify-send -u low "Banchy OS" "Theme applied: $name" 2>/dev/null || true
    fi
    return 0
  fi
  return 1
}

b_theme_cmd_validate() {
  local name="${1:-}"
  [[ -n "$name" ]] || { b_err "usage: banchy theme validate <name>"; return 2; }
  if b_theme_validate "$name"; then
    b_ok "theme '$name' is valid"
    return 0
  fi
  return 1
}

b_theme_cmd_create() {
  local name="${1:-}" from="" accent=""
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from) from="${2:?}"; shift ;;
      --accent) accent="${2:?}"; shift ;;
      *) b_err "theme create: unknown option '$1'"; return 2 ;;
    esac
    shift
  done
  [[ -n "$name" ]] || { b_err "usage: banchy theme create <name> [--from <base>] [--accent #RRGGBB]"; return 2; }
  [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || { b_err "theme name may only contain letters, digits, - and _"; return 1; }

  local user_dir dest
  user_dir="$(b_theme_user_dir)"
  dest="$user_dir/$name"
  if [[ -e "$dest" ]]; then
    b_err "theme already exists: $dest"
    return 1
  fi

  [[ -n "$from" ]] || from="$(b_theme_current)"
  local base
  base="$(b_theme_file "$from")" || { b_err "base theme '$from' not found"; return 1; }

  mkdir -p "$dest"
  cp "$base" "$dest/theme.conf"
  # Copy wallpapers referenced from the theme dir if any.
  local w
  for w in "$(dirname "$base")"/*.{png,jpg,jpeg,webp}; do
    if [[ -f "$w" ]]; then
      cp "$w" "$dest/" 2>/dev/null || true
    fi
  done

  if [[ -n "$accent" ]]; then
    if ! b_is_hex "$accent"; then
      b_err "--accent must be a hex color like #6C8CFF"
      rm -rf "$dest"
      return 1
    fi
    sed -i "s/^ACCENT=.*/ACCENT=$accent/" "$dest/theme.conf"
    sed -i "s/^BORDER_ACTIVE=.*/BORDER_ACTIVE=$accent/" "$dest/theme.conf"
  fi
  sed -i "s/^NAME=.*/NAME=$name/" "$dest/theme.conf"
  sed -i "s/^DISPLAY_NAME=.*/DISPLAY_NAME=\"Banchy $name\"/" "$dest/theme.conf"

  b_theme_validate "$name" || {
    b_err "the generated theme failed validation — removing it"
    rm -rf "$dest"
    return 1
  }
  b_ok "created theme '$name' at $dest/theme.conf"
  b_info "edit the file, then run: banchy theme set $name"
  return 0
}

banchy_cmd_theme() {
  local sub="${1:-list}"
  shift || true
  case "$sub" in
    list) b_theme_cmd_list "$@" ;;
    set) b_theme_cmd_set "$@" ;;
    create) b_theme_cmd_create "$@" ;;
    validate) b_theme_cmd_validate "$@" ;;
    *) b_err "usage: banchy theme [list|set|create|validate]"; return 2 ;;
  esac
}
