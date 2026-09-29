# shellcheck shell=bash
# Banchy settings: defaults, validation, atomic read/write.
# Settings file format: KEY=VALUE, one per line, '#' comments allowed.

# Fixed key order used when (re)writing the settings file.
B_SETTINGS_KEYS=(
  theme mode accent transparency blur border_size border_radius
  gaps_in gaps_out animations anim_speed font font_size terminal_font
  cursor_size waybar_position waybar_height wallpaper night_location
)

declare -Ag B_SET=()

b_settings_default_file() {
  echo "$BANCHY_SHARE/defaults/banchy/settings.conf"
}

# Validate a single setting. Prints a human readable error and returns 1 on
# failure. Usage: b_settings_validate <key> <value>
b_settings_validate() {
  local key="$1" value="$2"
  case "$key" in
    theme)
      if [[ -z "$value" ]]; then
        b_err "theme must not be empty"
        return 1
      fi
      if ! b_theme_file "$value" >/dev/null; then
        b_err "unknown theme '$value' (run 'banchy theme list')"
        return 1
      fi
      ;;
    mode)
      [[ "$value" == "dark" || "$value" == "light" ]] || {
        b_err "mode must be 'dark' or 'light' (got '$value')"
        return 1
      }
      ;;
    accent|BORDER_ACTIVE)
      if [[ -n "$value" ]] && ! b_is_hex "$value"; then
        b_err "$key must be a hex color like #6C8CFF (got '$value')"
        return 1
      fi
      ;;
    transparency)
      if ! b_is_float "$value" || ! awk "BEGIN{exit !($value >= 0 && $value <= 0.6)}"; then
        b_err "transparency must be a number between 0 and 0.6 (got '$value')"
        return 1
      fi
      ;;
    blur|animations)
      [[ "$value" == "on" || "$value" == "off" ]] || {
        b_err "$key must be 'on' or 'off' (got '$value')"
        return 1
      }
      ;;
    border_size)     b_settings_range "$key" "$value" 0 8 || return 1 ;;
    border_radius)   b_settings_range "$key" "$value" 0 20 || return 1 ;;
    gaps_in)         b_settings_range "$key" "$value" 0 30 || return 1 ;;
    gaps_out)        b_settings_range "$key" "$value" 0 40 || return 1 ;;
    anim_speed)      b_settings_range "$key" "$value" 0.1 3.0 || return 1 ;;
    font_size)       b_settings_range "$key" "$value" 8 32 || return 1 ;;
    cursor_size)     b_settings_range "$key" "$value" 16 48 || return 1 ;;
    waybar_height)   b_settings_range "$key" "$value" 24 64 || return 1 ;;
    font|terminal_font)
      if [[ ! "$value" =~ ^[A-Za-z0-9\ _.-]{1,64}$ ]]; then
        b_err "$key must be a font name (1-64 chars, got '$value')"
        return 1
      fi
      ;;
    waybar_position)
      [[ "$value" == "top" || "$value" == "bottom" ]] || {
        b_err "waybar_position must be 'top' or 'bottom' (got '$value')"
        return 1
      }
      ;;
    wallpaper)
      # Empty means "use the theme's wallpaper".
      if [[ -z "$value" ]]; then
        return 0
      fi
      local wp="$value"
      if [[ "$wp" != /* ]]; then
        wp="$BANCHY_SHARE/wallpapers/$wp"
      fi
      if [[ ! -f "$wp" ]]; then
        b_err "wallpaper file not found: $wp"
        return 1
      fi
      case "$wp" in
        *.png|*.jpg|*.jpeg|*.webp|*.bmp) ;;
        *) b_err "wallpaper must be an image file (got '$value')"; return 1 ;;
      esac
      ;;
    night_location)
      if [[ ! "$value" =~ ^-?[0-9]+(\.[0-9]+)?,-?[0-9]+(\.[0-9]+)?$ ]]; then
        b_err "night_location must be 'LAT,LON' (e.g. 55.75,37.61), got '$value'"
        return 1
      fi
      ;;
    *)
      b_err "unknown setting '$key'"
      return 1
      ;;
  esac
  return 0
}

b_settings_range() {
  local key="$1" value="$2" min="$3" max="$4"
  if ! b_is_float "$value"; then
    b_err "$key must be a number between $min and $max (got '$value')"
    return 1
  fi
  if ! awk "BEGIN{exit !($value >= $min && $value <= $max)}"; then
    b_err "$key must be between $min and $max (got '$value')"
    return 1
  fi
  return 0
}

# Load defaults + user overrides into B_SET.
b_settings_load() {
  local -A raw=()
  b_kv_load "$(b_settings_default_file)" raw || {
    b_err "cannot read system defaults: $(b_settings_default_file)"
    return 1
  }
  local k
  for k in "${!raw[@]}"; do
    B_SET["$k"]="${raw[$k]}"
  done
  if [[ -f "$BANCHY_SETTINGS_FILE" ]]; then
    local -A user=()
    b_kv_load "$BANCHY_SETTINGS_FILE" user
    for k in "${!user[@]}"; do
      B_SET["$k"]="${user[$k]}"
    done
  fi
  # Empty overrides mean "use theme value".
  [[ -n "${B_SET[accent]:-}" ]] || B_SET[accent]=""
  [[ -n "${B_SET[wallpaper]:-}" ]] || B_SET[wallpaper]=""
  return 0
}

b_settings_get() {
  local key="$1"
  b_settings_load
  if [[ -z "${B_SET[$key]+x}" ]]; then
    b_err "unknown setting '$key'"
    return 1
  fi
  printf '%s\n' "${B_SET[$key]}"
}

# Write a validated setting atomically. Does NOT apply/render.
b_settings_set() {
  local key="$1" value="$2"
  b_settings_validate "$key" "$value" || return 1

  mkdir -p "$(dirname "$BANCHY_SETTINGS_FILE")"
  local tmp
  tmp="$(mktemp "${BANCHY_SETTINGS_FILE}.XXXXXX")"

  local -A current=()
  if [[ -f "$BANCHY_SETTINGS_FILE" ]]; then
    b_kv_load "$BANCHY_SETTINGS_FILE" current
  else
    local -A defs=()
    b_kv_load "$(b_settings_default_file)" defs || true
    local k
    for k in "${!defs[@]}"; do
      current["$k"]="${defs[$k]}"
    done
  fi
  current["$key"]="$value"

  local out_key written=""
  for out_key in "${B_SETTINGS_KEYS[@]}"; do
    if [[ -n "${current[$out_key]+x}" ]]; then
      printf '%s=%s\n' "$out_key" "${current[$out_key]}" >>"$tmp"
      written+=" $out_key"
    fi
  done
  # Preserve unknown keys (forward compatibility with newer versions).
  for out_key in "${!current[@]}"; do
    case " $written " in
      *" $out_key "*) ;;
      *) printf '%s=%s\n' "$out_key" "${current[$out_key]}" >>"$tmp" ;;
    esac
  done

  chmod 644 "$tmp"
  mv -f "$tmp" "$BANCHY_SETTINGS_FILE"
  b_log INFO "setting $key=$value"
  return 0
}

b_settings_list() {
  b_settings_load
  local k
  for k in "${B_SETTINGS_KEYS[@]}"; do
    printf '%-18s %s\n' "$k" "${B_SET[$k]:-}"
  done
}
