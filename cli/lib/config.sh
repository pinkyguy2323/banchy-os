# shellcheck shell=bash
# User configuration management: backup / restore / diff / check.

b_config_backup() {
  local label="${1:-manual}"
  [[ "$label" =~ ^[A-Za-z0-9._-]+$ ]] || { b_err "invalid backup label"; return 1; }
  mkdir -p "$BANCHY_BACKUP_DIR"
  local file
  file="$BANCHY_BACKUP_DIR/config-$(date +%Y%m%d-%H%M%S)-$label.tar.gz"
  local xdg="${XDG_CONFIG_HOME:-$HOME/.config}"
  local -a paths=()
  local p
  for p in hypr waybar kitty fuzzel mako hyprlock hyprpaper hypridle fastfetch \
           gammastep banchy gtk-3.0 gtk-4.0; do
    [[ -e "$xdg/$p" ]] && paths+=(".config/$p")
  done
  if [[ ${#paths[@]} -eq 0 ]]; then
    b_err "nothing to back up under $xdg"
    return 1
  fi
  tar -czf "$file" -C "$HOME" "${paths[@]}" 2>/dev/null || {
    b_err "backup failed"
    return 1
  }
  # Prune: keep the newest 20 backups.
  # shellcheck disable=SC2012
  ls -1t "$BANCHY_BACKUP_DIR"/config-*.tar.gz 2>/dev/null | tail -n +21 | xargs -r rm -f
  b_ok "configuration backup: $file"
  echo "$file"
  return 0
}

b_config_restore() {
  local file="${1:-}"
  if [[ -z "$file" || "$file" == "--last" ]]; then
    # shellcheck disable=SC2012
    file="$(ls -1t "$BANCHY_BACKUP_DIR"/config-*.tar.gz 2>/dev/null | head -1)"
    [[ -n "$file" ]] || { b_err "no backups found in $BANCHY_BACKUP_DIR"; return 1; }
  fi
  if [[ ! -f "$file" ]]; then
    # Allow bare names from the backup directory.
    if [[ -f "$BANCHY_BACKUP_DIR/$file" ]]; then
      file="$BANCHY_BACKUP_DIR/$file"
    else
      b_err "backup not found: $file"
      return 1
    fi
  fi

  b_header "Configuration backups"
  printf 'Restoring: %s\n' "$file"
  if ! b_confirm "This will overwrite current configuration files. Continue?"; then
    b_info "cancelled"
    return 0
  fi

  tar -xzf "$file" -C "$HOME" || {
    b_err "restore failed (archive may be corrupt)"
    return 1
  }
  b_ok "configuration restored from $(basename "$file")"
  b_info "run 'banchy apply' to regenerate derived files"
  if [[ -t 0 ]]; then
    if b_confirm "Apply the restored configuration now?"; then
      b_apply
    fi
  fi
  return 0
}

b_config_list_backups() {
  local f
  local found=0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    found=1
    printf '  %s  (%s)\n' "$(basename "$f")" "$(du -h "$f" | cut -f1)"
  done < <(ls -1t "$BANCHY_BACKUP_DIR"/config-*.tar.gz 2>/dev/null)
  ((found)) || b_info "no backups yet — create one with 'banchy config backup'"
  return 0
}

b_config_diff() {
  local xdg="${XDG_CONFIG_HOME:-$HOME/.config}"
  local default_file="$BANCHY_SHARE/defaults/banchy/settings.conf"
  local user_file="$BANCHY_SETTINGS_FILE"
  local rc=0

  b_header "Settings vs system defaults"
  if [[ -f "$user_file" ]]; then
    diff -u "$default_file" "$user_file" || rc=$?
    if [[ $rc -eq 0 ]]; then
      b_ok "settings match system defaults"
    fi
  else
    b_info "no user settings file yet ($user_file)"
  fi

  b_header "Managed files"
  local target rel
  while read -r _tmpl rel; do
    [[ -n "${rel:-}" ]] || continue
    target="$xdg/${rel#.config/}"
    if [[ -f "$target" ]]; then
      if ! grep -q "Managed by Banchy OS" "$target" 2>/dev/null; then
        b_warn "modified by user (will not be overwritten): $target"
      fi
    else
      b_info "not generated yet: $target (run 'banchy apply')"
    fi
  done < <(awk 'NF >= 2 && $1 !~ /^#/ { print $1, $2 }' "$BANCHY_SHARE/templates/manifest" 2>/dev/null)
  return 0
}

b_config_check() {
  local rc=0

  # 1. Settings must validate against the specification.
  b_settings_load || return 1
  local k
  for k in "${B_SETTINGS_KEYS[@]}"; do
    if ! b_settings_validate "$k" "${B_SET[$k]:-}"; then
      rc=1
    fi
  done
  if ((rc)); then
    b_fail "settings validation"
  else
    b_ok "settings validation"
  fi

  # 2. The theme must be intact.
  if b_theme_validate "${B_SET[theme]:-}" 2>/dev/null; then
    b_ok "theme integrity"
  else
    b_fail "theme integrity (${B_SET[theme]:-?})"
    rc=1
  fi

  # 3. A dry-run render must succeed.
  if b_apply --check >/dev/null 2>&1; then
    b_ok "render pipeline"
  else
    b_fail "render pipeline"
    rc=1
  fi

  # 4. Generated files must exist and contain no unresolved placeholders.
  local generated="$BANCHY_GENERATED_DIR/hypr-dynamic.conf"
  if [[ -f "$generated" ]]; then
    if grep -q '{{' "$generated" 2>/dev/null; then
      b_fail "generated configuration has unresolved placeholders"
      rc=1
    else
      b_ok "generated configuration"
    fi
  else
    b_warn "generated configuration missing (run 'banchy apply')"
  fi

  # 5. Hyprland config brace balance (structural sanity).
  local xdg="${XDG_CONFIG_HOME:-$HOME/.config}"
  local hc="$xdg/hypr/hyprland.conf"
  if [[ -f "$hc" ]]; then
    local opens closes
    opens="$(grep -o '{' "$hc" | wc -l)"
    closes="$(grep -o '}' "$hc" | wc -l)"
    if [[ "$opens" == "$closes" ]]; then
      b_ok "hyprland configuration structure"
    else
      b_fail "hyprland configuration: unbalanced braces ($opens vs $closes)"
      rc=1
    fi
  else
    b_warn "hyprland.conf not found at $hc"
  fi

  return $rc
}

banchy_cmd_config() {
  local sub="${1:-check}"
  shift || true
  case "$sub" in
    backup) b_config_backup "$@" ;;
    restore)
      if [[ "${1:-}" == "--list" ]]; then b_config_list_backups; else b_config_restore "$@"; fi ;;
    list) b_config_list_backups "$@" ;;
    diff) b_config_diff "$@" ;;
    check|validate) b_config_check "$@" ;;
    *) b_err "usage: banchy config [backup|restore|diff|check]"; return 2 ;;
  esac
}

b_config_reset_hyprland() {
  local xdg="${XDG_CONFIG_HOME:-$HOME/.config}"
  local defaults="$BANCHY_SHARE/defaults/hypr"
  [[ -d "$defaults" ]] || { b_err "system hyprland defaults missing ($defaults)"; return 1; }
  if [[ -t 0 ]]; then
    if ! b_confirm "Reset Hyprland configuration to stock defaults (current files are backed up)?"; then
      b_info "cancelled"
      return 0
    fi
  fi
  b_config_backup reset || b_warn "no existing configuration to back up"
  local p
  for p in "$xdg/hypr" "$BANCHY_GENERATED_DIR"; do
    [[ -e "$p" ]] && rm -rf "$p"
  done
  mkdir -p "$xdg/hypr"
  cp -a "$defaults"/. "$xdg/hypr/"
  b_ok "hyprland configuration reset to defaults"
  b_apply
}

banchy_cmd_reset() {
  local what="${1:-}"
  shift || true
  case "$what" in
    hyprland|hypr) b_config_reset_hyprland "$@" ;;
    *) b_err "usage: banchy reset hyprland"; return 2 ;;
  esac
}
