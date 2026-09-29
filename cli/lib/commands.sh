# shellcheck shell=bash
# Top-level command implementations: set / get / apply / autostart / welcome.

banchy_cmd_set() {
  local no_apply=0
  if [[ "${1:-}" == "--no-apply" ]]; then
    no_apply=1
    shift
  fi
  local key="${1:-}" value="${2:-}"
  [[ -n "$key" && $# -ge 2 ]] || {
    b_err "usage: banchy set <key> <value> [--no-apply]"
    return 2
  }

  local prev had_prev=0
  if b_settings_load 2>/dev/null && [[ -n "${B_SET[$key]+x}" ]]; then
    prev="${B_SET[$key]}"
    had_prev=1
  fi

  b_settings_set "$key" "$value" || return 1

  if ((no_apply)); then
    b_ok "set $key=$value (not applied yet)"
    return 0
  fi

  if b_apply; then
    b_ok "set $key=$value"
    return 0
  fi

  # Applying failed — revert the setting to its previous value.
  b_err "could not apply '$key=$value' — reverting"
  if ((had_prev)); then
    b_settings_set "$key" "$prev" || true
    b_apply --no-reload >/dev/null 2>&1 || true
    b_info "previous value restored: $key=$prev"
  fi
  return 1
}

banchy_cmd_get() {
  local key="${1:-}"
  [[ -n "$key" ]] || { b_err "usage: banchy get <key>"; return 2; }
  b_settings_get "$key"
}

banchy_cmd_apply() {
  b_apply "$@"
}

banchy_cmd_welcome() {
  local script
  for script in "/usr/bin/banchy-welcome" \
    "$BANCHY_LIB/../../first-run/banchy-welcome" \
    "$BANCHY_LIB/../first-run/banchy-welcome"; do
    if [[ -x "$script" ]]; then
      exec "$script" "$@"
    fi
    if [[ -f "$script" ]]; then
      exec bash "$script" "$@"
    fi
  done
  b_err "first-run wizard not installed (banchy-welcome)"
  return 1
}

banchy_cmd_autostart() {
  # Session bootstrap, executed once per graphical session (exec-once).
  [[ -z "${BANCHY_NO_AUTOSTART:-}" ]] || return 0

  b_seed_defaults || true

  # Generate derived configuration if it does not exist yet.
  if [[ ! -f "$BANCHY_GENERATED_DIR/hypr-dynamic.conf" ]]; then
    b_apply >/dev/null 2>&1 || b_warn "initial configuration render failed — run 'banchy config check'"
  fi

  # First-run wizard.
  if [[ ! -f "$BANCHY_USER_DIR/first-run-done" ]]; then
    if [[ -n "${WAYLAND_DISPLAY:-}" && -z "${BANCHY_NO_WELCOME:-}" ]]; then
      if b_have kitty && b_have banchy-welcome; then
        setsid -f kitty -e banchy-welcome >/dev/null 2>&1 || true
      fi
    fi
  fi
  return 0
}
