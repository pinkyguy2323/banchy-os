# shellcheck shell=bash
# Banchy render pipeline: theme + settings -> templates -> generated configs.
#
# Guarantees:
#   * nothing is written until every template renders successfully
#   * targets are backed up before being replaced
#   * files with a "Managed by Banchy OS" marker are owned by the engine
#   * a failed Hyprland verification triggers automatic rollback

declare -Ag B_ENV=()

B_MANAGED_MARKER="Managed by Banchy OS"

# --- environment collection ---------------------------------------------------
b_render_env() {
  local -A T=()

  b_settings_load || return 1

  local theme="${B_SET[theme]:-}"
  [[ -n "$theme" ]] || { b_err "no theme selected"; return 1; }
  local theme_file
  theme_file="$(b_theme_file "$theme")" || {
    b_err "theme '$theme' not found"
    return 1
  }
  b_theme_validate "$theme" || return 1

  local -A raw=()
  b_kv_load "$theme_file" raw || { b_err "cannot read $theme_file"; return 1; }
  local k
  for k in "${!raw[@]}"; do
    T["$k"]="${raw[$k]}"
  done

  # Light mode requires a light palette in the theme.
  local mode="${B_SET[mode]:-dark}"
  if [[ "$mode" == "light" ]]; then
    for k in BG SURFACE SURFACE_ALT TEXT TEXT_DIM BORDER_INACTIVE; do
      if [[ -z "${T[LIGHT_$k]:-}" ]]; then
        b_err "theme '$theme' has no light variant (missing LIGHT_$k)"
        return 1
      fi
      T["$k"]="${T[LIGHT_$k]}"
    done
  fi

  # Reset environment.
  for k in "${!B_ENV[@]}"; do
    unset 'B_ENV[$k]'
  done

  # Theme palette.
  for k in BG SURFACE SURFACE_ALT TEXT TEXT_DIM ACCENT ACCENT_ALT \
           BORDER_ACTIVE BORDER_INACTIVE DANGER WARNING SUCCESS; do
    [[ -n "${T[$k]:-}" ]] || { b_err "theme '$theme' missing key $k"; return 1; }
    B_ENV[$k]="${T[$k]}"
  done
  B_ENV[THEME]="$theme"
  B_ENV[THEME_NAME]="${T[DISPLAY_NAME]:-$theme}"
  B_ENV[MODE]="$mode"

  # Settings overrides.
  if [[ -n "${B_SET[accent]:-}" ]]; then
    B_ENV[ACCENT]="${B_SET[accent]}"
    B_ENV[BORDER_ACTIVE]="${B_SET[accent]}"
  fi

  local wallpaper="${B_SET[wallpaper]:-}"
  if [[ -z "$wallpaper" ]]; then
    wallpaper="${T[WALLPAPER]:-}"
  fi
  if [[ "$wallpaper" != /* ]]; then
    wallpaper="$BANCHY_SHARE/wallpapers/$wallpaper"
  fi
  if [[ ! -f "$wallpaper" ]]; then
    b_err "wallpaper not found: $wallpaper"
    return 1
  fi
  B_ENV[WALLPAPER]="$wallpaper"

  # Numeric settings.
  local transparency="${B_SET[transparency]:-0}"
  local anim_speed="${B_SET[anim_speed]:-1}"
  local border_size="${B_SET[border_size]:-2}"
  local border_radius="${B_SET[border_radius]:-10}"
  local gaps_in="${B_SET[gaps_in]:-5}"
  local gaps_out="${B_SET[gaps_out]:-10}"
  local font_size="${B_SET[font_size]:-11}"
  local cursor_size="${B_SET[cursor_size]:-24}"
  local waybar_height="${B_SET[waybar_height]:-34}"
  local alpha panel_alpha

  alpha="$(b_math "1 - ($transparency)")" || return 1
  panel_alpha="$(b_math "1 - ($transparency) * 0.5")" || return 1

  B_ENV[TRANSPARENCY]="$transparency"
  B_ENV[ALPHA_F]="$(awk 'BEGIN{printf "%.2f", '"$alpha"'}')"
  B_ENV[ALPHA_HEX]="$(b_alpha_hex "$alpha")"
  B_ENV[PANEL_ALPHA_F]="$panel_alpha"
  B_ENV[PANEL_ALPHA_HEX]="$(b_alpha_hex "$panel_alpha")"

  # RGB triples for rgba() usage in CSS, RAW hex without '#' for rgb() syntax.
  local color
  for color in BG SURFACE SURFACE_ALT TEXT TEXT_DIM ACCENT ACCENT_ALT \
               BORDER_ACTIVE BORDER_INACTIVE DANGER WARNING SUCCESS; do
    B_ENV["${color}_RGB"]="$(b_hex_to_rgb "${B_ENV[$color]}")"
    B_ENV["${color}_AA"]="${B_ENV[$color]#\#}${B_ENV[ALPHA_HEX]}"
    B_ENV["${color}_RAW"]="${B_ENV[$color]#\#}"
  done

  # Opacities: transparency affects decorations, not full readability.
  B_ENV[ACTIVE_OPACITY]="$(b_math "1 - ($transparency) * 0.5")" || return 1
  B_ENV[INACTIVE_OPACITY]="$(b_math "1 - ($transparency)")" || return 1

  # Hyprland toggles.
  B_ENV[BORDER_SIZE]="$border_size"
  B_ENV[BORDER_RADIUS]="$border_radius"
  B_ENV[GAPS_IN]="$gaps_in"
  B_ENV[GAPS_OUT]="$gaps_out"
  if [[ "${B_SET[blur]:-on}" == "on" ]]; then
    B_ENV[BLUR_ENABLED]=1
  else
    B_ENV[BLUR_ENABLED]=0
  fi
  if [[ "${B_SET[animations]:-on}" == "on" ]]; then
    B_ENV[ANIM_ENABLED]=1
  else
    B_ENV[ANIM_ENABLED]=0
  fi
  B_ENV[ANIM_SPEED]="$anim_speed"
  B_ENV[ANIM_S_WINDOW]="$(b_math_int "4 * ($anim_speed)")" || return 1
  B_ENV[ANIM_S_FADE]="$(b_math_int "5 * ($anim_speed)")" || return 1
  B_ENV[ANIM_S_WORKSPACE]="$(b_math_int "3 * ($anim_speed)")" || return 1
  B_ENV[ANIM_S_BORDER]="$(b_math_int "4 * ($anim_speed)")" || return 1

  # Fonts, cursor, GTK.
  B_ENV[FONT]="${B_SET[font]:-JetBrains Mono}"
  B_ENV[FONT_SIZE]="$font_size"
  B_ENV[TERMINAL_FONT]="${B_SET[terminal_font]:-${B_SET[font]:-JetBrains Mono}}"
  B_ENV[CURSOR_SIZE]="$cursor_size"
  B_ENV[CURSOR_THEME]="${T[CURSOR_THEME]:-Adwaita}"
  B_ENV[ICON_THEME]="${T[ICON_THEME]:-Adwaita}"
  if [[ "$mode" == "light" ]]; then
    B_ENV[GTK_THEME]="Adwaita"
    B_ENV[GTK_DARK]=0
  else
    B_ENV[GTK_THEME]="Adwaita-dark"
    B_ENV[GTK_DARK]=1
  fi
  B_ENV[KITTY_OPACITY]="$(b_math "1 - ($transparency) * 0.7")" || return 1
  B_ENV[TEMP_DAY]=6500
  if [[ "$mode" == "light" ]]; then
    B_ENV[TEMP_NIGHT]=5000
  else
    B_ENV[TEMP_NIGHT]=3500
  fi

  # Waybar.
  B_ENV[WAYBAR_POSITION]="${B_SET[waybar_position]:-top}"
  B_ENV[WAYBAR_HEIGHT]="$waybar_height"

  # Misc.
  B_ENV[NIGHT_LOCATION]="${B_SET[night_location]:-0,0}"
  B_ENV[BANCHY_VERSION]="${BANCHY_VERSION:-0.1.0}"

  return 0
}

# --- template rendering -------------------------------------------------------
b_render_template() {
  # b_render_template <src-file> <dst-file> — renders using B_ENV.
  local src="$1" dst="$2"
  local line key iter
  : >"$dst" || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    iter=0
    while [[ "$line" =~ \{\{([A-Za-z_][A-Za-z0-9_]*)\}\} ]]; do
      key="${BASH_REMATCH[1]}"
      if [[ -z "${B_ENV[$key]+x}" ]]; then
        b_err "template $src: unknown key {{$key}}"
        return 1
      fi
      line="${line//\{\{$key\}\}/${B_ENV[$key]}}"
      iter=$((iter + 1))
      if ((iter > 64)); then
        b_err "template $src: replacement loop detected"
        return 1
      fi
    done
    printf '%s\n' "$line" >>"$dst" || return 1
  done <"$src"
  return 0
}

b_render_manifest() {
  echo "$BANCHY_SHARE/templates/manifest"
}

# --- apply --------------------------------------------------------------------
b_apply() {
  local check=0 force=0 no_reload=0 home_root="$HOME"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) check=1 ;;
      --force) force=1 ;;
      --no-reload) no_reload=1 ;;
      --root) home_root="${2:?--root needs a directory}"; shift ;;
      *) b_err "apply: unknown option '$1'"; return 2 ;;
    esac
    shift
  done

  local manifest
  manifest="$(b_render_manifest)"
  if [[ ! -f "$manifest" ]]; then
    b_err "manifest not found: $manifest"
    return 1
  fi

  b_render_env || return 1

  local staging
  staging="$(mktemp -d "${TMPDIR:-/tmp}/banchy-render.XXXXXX")"

  local tmpl rel mode target
  local -a staged=() targets=()
  local -A skip_set=()
  while read -r tmpl rel mode; do
    [[ -z "${tmpl:-}" || "$tmpl" == \#* ]] && continue
    if [[ ! -f "$BANCHY_SHARE/templates/$tmpl" ]]; then
      rm -rf "$staging"
      b_err "template not found: $tmpl"
      return 1
    fi
    mkdir -p "$staging/$(dirname "$rel")"
    if ! b_render_template "$BANCHY_SHARE/templates/$tmpl" "$staging/$rel"; then
      rm -rf "$staging"
      b_err "render failed for $tmpl — no changes were applied"
      return 1
    fi
    staged+=("$staging/$rel")
    target="$home_root/$rel"
    targets+=("$target")

    # Target ownership policy: never clobber hand-edited files without --force.
    if [[ -e "$target" ]] && ! grep -q "$B_MANAGED_MARKER" "$target" 2>/dev/null; then
      if ((force == 0)); then
        skip_set["$target"]=1
      fi
    fi
  done <"$manifest"

  # Post-render sanity: no unresolved placeholders may remain.
  if grep -R -q '{{' "$staging" 2>/dev/null; then
    local leftover
    leftover="$(grep -R -n '{{' "$staging" 2>/dev/null | head -3)"
    rm -rf "$staging"
    b_err "unresolved placeholders remain — no changes were applied"
    b_info "$leftover"
    return 1
  fi

  if ((check)); then
    local s
    for s in "${!skip_set[@]}"; do
      b_warn "would skip (user-modified): $s"
    done
    b_ok "configuration renders cleanly (${#staged[@]} files)"
    rm -rf "$staging"
    return 0
  fi

  # Backup current targets before replacing them.
  local backup
  backup="$BANCHY_STATE_DIR/apply-backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup"
  local backed_up=0 i
  for i in "${!staged[@]}"; do
    target="${targets[$i]}"
    [[ -n "${skip_set[$target]:-}" ]] && continue
    if [[ -e "$target" ]]; then
      mkdir -p "$backup/$(dirname "${target#"$home_root"/}")"
      cp -a "$target" "$backup/${target#"$home_root"/}"
      backed_up=1
    fi
  done
  ((backed_up)) && echo "$backup" >"$BANCHY_STATE_DIR/last-backup"
  # Prune old backups, keep the newest 10.
  # shellcheck disable=SC2012
  ls -1dt "$BANCHY_STATE_DIR"/apply-backup-* 2>/dev/null | tail -n +11 | xargs -r rm -rf

  # Install staged files.
  local skipped_count=0 s
  for i in "${!staged[@]}"; do
    target="${targets[$i]}"
    if [[ -n "${skip_set[$target]:-}" ]]; then
      skipped_count=$((skipped_count + 1))
      b_warn "skipped user-modified file: $target (use --force to overwrite)"
      continue
    fi
    mkdir -p "$(dirname "$target")"
    cp -a "${staged[$i]}" "$target"
    chmod "${mode:-644}" "$target" 2>/dev/null || true
  done
  rm -rf "$staging"

  # Reload running components.
  if ((no_reload == 0)); then
    b_render_reload
  fi

  # Verify: the compositor must have accepted the new configuration.
  if ((no_reload == 0)); then
    if ! b_render_verify; then
      b_warn "verification failed — rolling back"
      if [[ -f "$BANCHY_STATE_DIR/last-backup" ]]; then
        b_render_restore "$(cat "$BANCHY_STATE_DIR/last-backup")"
        b_render_reload
      fi
      if b_have notify-send && pgrep -x Hyprland >/dev/null 2>&1; then
        notify-send -u critical "Banchy OS" "Configuration rejected — previous settings restored." 2>/dev/null || true
      fi
      b_err "${B_ERR:-configuration verification failed}"
      return 1
    fi
  fi

  date +%s >"$BANCHY_STATE_DIR/last-apply-ok"
  b_log INFO "apply completed ($skipped_count skipped)"
  return 0
}

b_render_reload() {
  if b_have hyprctl && hyprctl version >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 || b_warn "hyprctl reload reported an error"
  fi
  if pgrep -x waybar >/dev/null 2>&1; then
    pkill -x waybar 2>/dev/null || true
    sleep 0.2
    setsid -f waybar >/dev/null 2>&1 || true
  fi
  if pgrep -x mako >/dev/null 2>&1; then
    makoctl reload >/dev/null 2>&1 || {
      pkill -x mako 2>/dev/null || true
      setsid -f mako >/dev/null 2>&1 || true
    }
  fi
  if pgrep -x hyprpaper >/dev/null 2>&1; then
    pkill -x hyprpaper 2>/dev/null || true
    sleep 0.1
    setsid -f hyprpaper >/dev/null 2>&1 || true
  fi
  return 0
}

b_render_verify() {
  # Structural verification that the compositor parsed our configuration.
  if ! b_have hyprctl || ! hyprctl version >/dev/null 2>&1; then
    return 0
  fi
  local want got
  want="${B_SET[border_size]:-2}"
  got="$(hyprctl getoption general:border_size -j 2>/dev/null \
    | sed -n 's/.*"int":[[:space:]]*\([0-9-]*\).*/\1/p' | head -1)"
  if [[ -z "$got" ]]; then
    B_ERR="could not read back general:border_size from Hyprland"
    return 1
  fi
  if [[ "$got" != "$want" ]]; then
    B_ERR="Hyprland rejected the new configuration (border_size: expected $want, got $got)"
    return 1
  fi
  return 0
}

b_render_restore() {
  local backup="$1"
  local home_root="${2:-$HOME}"
  [[ -d "$backup" ]] || { b_err "backup not found: $backup"; return 1; }
  local f target
  while IFS= read -r -d '' f; do
    target="$home_root/${f#"$backup"/}"
    mkdir -p "$(dirname "$target")"
    cp -a "$f" "$target"
  done < <(find "$backup" -type f -print0)
  b_ok "restored configuration from $(basename "$backup")"
  return 0
}
