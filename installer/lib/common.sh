# shellcheck shell=bash
# Banchy installer — UI helpers, logging and answers-file loading.
# Standalone: must work without the CLI libraries (small local equivalents of
# the b_ok/b_warn/b_err output helpers). Requires bash >= 4.4.
set -euo pipefail

B_INSTALL_LOG="${B_INSTALL_LOG:-/var/log/banchy-install.log}"
MNT="${B_INSTALL_MNT:-/mnt}"
B_UNATTENDED="${B_UNATTENDED:-0}"
declare -gA B_ANS=()

# --- output (mirrors cli/lib/common.sh style) --------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
else
  C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW=""
fi

b_ok() {
  printf '%s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$1"
}

b_warn() {
  printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$1"
}

b_fail() {
  printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$1"
}

b_info() {
  printf '%s·%s %s\n' "$C_DIM" "$C_RESET" "$1"
}

b_err() {
  printf '%sbanchy-install:%s %s\n' "$C_RED" "$C_RESET" "$1" >&2
}

b_header() {
  printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"
}

# --- logging -----------------------------------------------------------------
log() {
  # Direct append (stdout is teed to the same file; stderr is not).
  # 2>/dev/null must come first so a failing open cannot print a shell error.
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" 2>/dev/null >>"$B_INSTALL_LOG" || true
}

die() {
  b_err "$1"
  log "FATAL: $1"
  exit "${2:-1}"
}

i_cmd() {
  # Echo the exact command to the log first, then show it on screen.
  log "RUN: $*"
  printf '%srun:%s %s\n' "$C_DIM" "$C_RESET" "$*"
}

run_chroot() {
  # run_chroot <cmd...> — run a command inside the target system at $MNT.
  log "RUN: arch-chroot $MNT $*"
  arch-chroot "$MNT" "$@"
}

# --- whiptail UI (with plain-read fallback) -----------------------------------
# whiptail draws its widgets on fd1 and writes the submitted answer on fd2;
# the 3>&1 1>&2 2>&3 swap inside $(...) captures the answer and keeps the
# widgets on the terminal. Every wrapper returns 1 on cancel/ESC.

ui_has_whiptail() {
  command -v whiptail >/dev/null 2>&1 && [[ -t 0 && -t 2 ]]
}

ui_msgbox() {
  # ui_msgbox <title> <text>
  local title="$1" text="$2" rc=0
  log "UI msgbox ($title): $text"
  if ui_has_whiptail; then
    whiptail --title "$title" --msgbox "$text" 0 72 || rc=$?
  else
    printf '%s\n\n' "$text"
    read -rp "[Enter] " _ || rc=1
  fi
  return "$rc"
}

ui_yesno() {
  # ui_yesno <title> <text> — 0 yes, 1 no/cancel
  local title="$1" text="$2" reply
  log "UI yesno ($title): $text"
  if ui_has_whiptail; then
    whiptail --title "$title" --yesno "$text" 0 72
  else
    printf '%s\n' "$text"
    read -r -p "[y/N] " reply || return 1
    [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
  fi
}

ui_input() {
  # ui_input <title> <text> [default] — echoes the answer, rc 1 on cancel
  local title="$1" text="$2" def="${3:-}" out="" rc=0
  log "UI input ($title): $text"
  if ui_has_whiptail; then
    out="$(whiptail --title "$title" --inputbox "$text" 0 72 "$def" 3>&1 1>&2 2>&3)" || rc=$?
  else
    printf '%s\n' "$text" >&2
    read -r -p "${def:+[$def] }: " out || rc=1
    [[ -n "$out" ]] || out="$def"
  fi
  ((rc)) && return 1
  printf '%s\n' "$out"
}

ui_password() {
  # ui_password <title> <text> [default] — echoes the answer, rc 1 on cancel
  local title="$1" text="$2" def="${3:-}" out="" rc=0
  log "UI password ($title): prompt shown"
  if ui_has_whiptail; then
    out="$(whiptail --title "$title" --passwordbox "$text" 0 72 "$def" 3>&1 1>&2 2>&3)" || rc=$?
  else
    printf '%s\n' "$text" >&2
    read -r -s -p "${def:+[$def] }: " out || rc=1
    printf '\n' >&2
    [[ -n "$out" ]] || out="$def"
  fi
  ((rc)) && return 1
  printf '%s\n' "$out"
}

ui_menu() {
  # ui_menu <title> <tag> <item> [<tag> <item>...] — echoes the chosen tag
  local title="$1" out="" rc=0
  shift
  log "UI menu ($title)"
  if ui_has_whiptail; then
    out="$(whiptail --title "$title" --menu "$title" 0 72 0 "$@" 3>&1 1>&2 2>&3)" || rc=$?
  else
    local -a tags=() items=()
    while [[ $# -ge 2 ]]; do
      tags+=("$1")
      items+=("$2")
      shift 2
    done
    local i
    printf '%s\n' "$title" >&2
    for i in "${!tags[@]}"; do
      printf '  %d) %-14s %s\n' "$((i + 1))" "${tags[$i]}" "${items[$i]}" >&2
    done
    while true; do
      read -r -p "> " out || { rc=1; break; }
      if [[ "$out" =~ ^[0-9]+$ ]] && ((out >= 1 && out <= ${#tags[@]})); then
        out="${tags[$((out - 1))]}"
        break
      fi
      printf 'invalid choice — enter 1..%s\n' "${#tags[@]}" >&2
    done
  fi
  ((rc)) && return 1
  printf '%s\n' "$out"
}

confirm_yes() {
  # confirm_yes <text> — destructive confirm: the user must type YES.
  local prompt="$1" input="" try
  log "UI destructive confirm: $prompt"
  for try in 1 2 3; do
    if ui_has_whiptail; then
      input="$(whiptail --title "CONFIRM DESTRUCTIVE ACTION" --inputbox "$prompt" 0 72 "" 3>&1 1>&2 2>&3)" || return 1
    else
      printf '%s\n' "$prompt" >&2
      read -r -p "type YES to continue: " input || return 1
    fi
    if [[ "$input" == "YES" ]]; then
      return 0
    fi
    b_warn "you did not type YES (attempt $try of 3)"
  done
  return 1
}

# --- passwords ----------------------------------------------------------------
i_gen_password() {
  # 16 alphanumeric characters; caller prints it exactly once (never logged).
  dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 | tr -dc 'A-Za-z0-9' | cut -c1-16
}

# --- answers file -------------------------------------------------------------
answers_load() {
  # answers_load <file> — KEY=VALUE lines into B_ANS, no shell evaluation.
  local file="$1" line key value
  [[ -f "$file" ]] || die "answers file not found: $file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" != *"="* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    key="${key#"${key%%[![:space:]]*}"}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    B_ANS["$key"]="$value"
  done <"$file"

  # Documented aliases (docs/INSTALLATION.md uses DISK/FS/USERNAME/PASSWORD).
  [[ -n "${B_ANS[TARGET_DISK]:-}" ]] || B_ANS[TARGET_DISK]="${B_ANS[DISK]:-}"
  [[ -n "${B_ANS[FILESYSTEM]:-}" ]] || B_ANS[FILESYSTEM]="${B_ANS[FS]:-}"
  [[ -n "${B_ANS[USER_NAME]:-}" ]] || B_ANS[USER_NAME]="${B_ANS[USERNAME]:-}"
  [[ -n "${B_ANS[USER_PASSWORD]:-}" ]] || B_ANS[USER_PASSWORD]="${B_ANS[PASSWORD]:-}"
  log "answers loaded from $file"
  return 0
}

answers_defaults() {
  : "${B_ANS[FILESYSTEM]:=ext4}"
  : "${B_ANS[SWAP]:=none}"
  : "${B_ANS[HOSTNAME]:=banchy}"
  : "${B_ANS[LOCALE]:=en_US.UTF-8}"
  : "${B_ANS[KEYMAP]:=us}"
  : "${B_ANS[TIMEZONE]:=UTC}"
  : "${B_ANS[PROFILE]:=default}"
  : "${B_ANS[AUTO_REBOOT]:=no}"
  return 0
}

# --- misc ---------------------------------------------------------------------
i_repo_dir() {
  # Repository containing scripts/ — live-ISO source tree first, then the
  # checkout this installer was started from.
  local c
  for c in "/usr/local/src/banchy-os" "${B_INSTALL_REPO:-}"; do
    [[ -n "$c" && -f "$c/scripts/install-files.sh" ]] || continue
    printf '%s\n' "$c"
    return 0
  done
  return 1
}

i_require_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    return 0
  fi
  command -v sudo >/dev/null 2>&1 ||
    die "this installer requires root privileges and sudo is not available"
  b_info "elevating privileges with sudo"
  exec sudo -- "$B_INSTALL_SELF" "$@"
}
