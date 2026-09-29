# shellcheck shell=bash
# Shared helpers for the Banchy CLI and Banchy shell tools.
# Sourced by cli/banchy; requires bash >= 4.4.

# --- paths -------------------------------------------------------------------
b_paths_init() {
  local _root=""
  # Repo detection: BANCHY_LIB ends with /cli/lib in a source checkout.
  case "${BANCHY_LIB:-}" in
    */cli/lib) _root="$(cd "$BANCHY_LIB/../.." && pwd)" ;;
  esac

  if [[ -z "${BANCHY_SHARE:-}" ]]; then
    local _c
    for _c in "/usr/share/banchy" "${_root:+$_root/.devroot/usr/share/banchy}"; do
      if [[ -n "$_c" && -f "$_c/defaults/banchy/settings.conf" ]]; then
        BANCHY_SHARE="$_c"
        break
      fi
    done
    : "${BANCHY_SHARE:=/usr/share/banchy}"
  fi
  export BANCHY_SHARE

  local xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
  local xdg_state="${XDG_STATE_HOME:-$HOME/.local/state}"
  local xdg_data="${XDG_DATA_HOME:-$HOME/.local/share}"
  BANCHY_USER_DIR="$xdg_config/banchy"
  BANCHY_STATE_DIR="$xdg_state/banchy"
  BANCHY_BACKUP_DIR="$xdg_data/banchy/backups"
  BANCHY_LOG="$BANCHY_STATE_DIR/banchy.log"
  BANCHY_SETTINGS_FILE="${BANCHY_SETTINGS:-$BANCHY_USER_DIR/settings.conf}"
  BANCHY_GENERATED_DIR="$BANCHY_USER_DIR/generated"
  export BANCHY_USER_DIR BANCHY_STATE_DIR BANCHY_BACKUP_DIR BANCHY_LOG
  export BANCHY_SETTINGS_FILE BANCHY_GENERATED_DIR

  # Where do we run? (live ISO or installed system)
  BANCHY_LIVE=0
  [[ -d /run/archiso ]] && BANCHY_LIVE=1
  export BANCHY_LIVE
}

# --- output ------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_CYAN=$'\033[36m'
else
  # shellcheck disable=SC2034 # whole palette stays defined; C_CYAN is read in
  #                            # cli/lib/info.sh, C_BLUE kept for colour parity.
  C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN=""
fi

b_log() {
  # b_log LEVEL MESSAGE — append to the session log file.
  mkdir -p "$BANCHY_STATE_DIR" 2>/dev/null || return 0
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >>"$BANCHY_LOG" 2>/dev/null || true
}

b_ok() {
  printf '%s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$1"
  b_log OK "$1"
}

b_warn() {
  printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$1"
  b_log WARN "$1"
}

b_fail() {
  printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$1"
  b_log FAIL "$1"
}

b_info() {
  printf '%s·%s %s\n' "$C_DIM" "$C_RESET" "$1"
  b_log INFO "$1"
}

b_err() {
  # Message on stderr, no [FAIL] marker (for usage/validation errors).
  printf '%sbanchy:%s %s\n' "$C_RED" "$C_RESET" "$1" >&2
  b_log ERROR "$1"
}

b_die() {
  b_err "$1"
  exit "${2:-1}"
}

b_header() {
  printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"
}

# --- utilities ---------------------------------------------------------------
b_have() {
  command -v "$1" >/dev/null 2>&1
}

b_confirm() {
  # b_confirm "question" — returns 0 on yes.
  local _reply
  printf '%s [y/N] ' "$1" >&2
  read -r _reply || return 1
  [[ "$_reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

b_ensure_root() {
  # Re-exec the whole command under sudo, preserving Banchy env.
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    return 0
  fi
  if ! b_have sudo; then
    b_die "this command requires root privileges and sudo is not available"
  fi
  b_info "elevating privileges with sudo"
  # shellcheck disable=SC2086
  exec sudo --preserve-env=BANCHY_SHARE,BANCHY_LIB,BANCHY_SETTINGS,BANCHY_TEST_ROOT \
    "$BANCHY_SELF" "${BANCHY_ORIG_ARGS[@]}"
}

b_sudo() {
  # Run a command as root without re-execing banchy.
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

b_is_int() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

b_is_float() {
  [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]
}

b_is_hex() {
  [[ "$1" =~ ^#[0-9a-fA-F]{6}$ ]]
}

b_math() {
  # b_math 'expr' — safe float arithmetic via awk (expr must match whitelist).
  local expr="$1"
  if [[ ! "$expr" =~ ^[-0-9.+*/()\ ]+$ ]]; then
    b_err "b_math: rejected expression: $expr"
    return 1
  fi
  awk "BEGIN { printf \"%.3f\", ($expr) }"
}

b_math_int() {
  local expr="$1"
  if [[ ! "$expr" =~ ^[-0-9.+*/()\ ]+$ ]]; then
    b_err "b_math_int: rejected expression: $expr"
    return 1
  fi
  awk "BEGIN { printf \"%d\", int(($expr) + 0.5) }"
}

b_hex_to_rgb() {
  # b_hex_to_rgb '#RRGGBB' -> 'R,G,B'
  local h="${1#\#}"
  printf '%d,%d,%d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}

b_alpha_hex() {
  # b_alpha_hex 0.85 -> 'D9' (2-digit alpha for RRGGBBAA colors)
  b_math_int "($1 * 255)" | awk '{ printf "%02X", $1 }'
}

# --- generic KEY=VALUE loading ----------------------------------------------
b_kv_load() {
  # b_kv_load <file> <assoc-name> — load KEY=VALUE lines, no shell evaluation.
  local file="$1"
  local -n _kv_out="$2"
  [[ -f "$file" ]] || return 1
  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" != *"="* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    key="${key#"${key%%[![:space:]]*}"}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    _kv_out["$key"]="$value"
  done <"$file"
  return 0
}

# --- user seeding ------------------------------------------------------------
b_seed_defaults() {
  # Copy system defaults into $HOME/.config for any file the user does not have.
  # Never overwrites existing user files.
  local defaults="$BANCHY_SHARE/defaults"
  [[ -d "$defaults" ]] || return 0
  local xdg="${XDG_CONFIG_HOME:-$HOME/.config}"
  local rel src dst
  while IFS= read -r -d '' src; do
    rel="${src#"$defaults"/}"
    dst="$xdg/$rel"
    if [[ ! -e "$dst" ]]; then
      mkdir -p "$(dirname "$dst")"
      cp -a "$src" "$dst"
    fi
  done < <(find "$defaults" -type f -print0 2>/dev/null)
  mkdir -p "$BANCHY_USER_DIR" "$BANCHY_STATE_DIR" "$BANCHY_BACKUP_DIR"
  return 0
}

b_paths_init
