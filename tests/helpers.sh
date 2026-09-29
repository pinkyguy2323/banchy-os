# shellcheck shell=bash
# Shared environment staging and assertions for the Banchy test suite.
# Sourced by tests/test_*.sh; each test is also runnable on its own:
#   bash tests/test_render.sh
set -euo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$TESTS_DIR/.." && pwd)"
# shellcheck disable=SC2034 # assigned here, read by the sibling test_*.sh files
BANCHY="$REPO/cli/banchy"
STAGE=""
WORK=""

t_fail() {
  printf 'ASSERTION FAILED: %s\n' "$*" >&2
  exit 1
}

t_ok() {
  printf '    ok  %s\n' "$1"
}

t_note() {
  printf '  note  %s\n' "$1"
}

# t_setup — isolated HOME/XDG_* plus one FHS staging run per test.
t_setup() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/banchy-test.XXXXXX")"
  trap 'rm -rf "$WORK"' EXIT
  STAGE="$WORK/stage"
  mkdir -p "$WORK/home"
  if ! bash "$REPO/scripts/install-files.sh" --root "$STAGE" >/dev/null; then
    t_fail "staging failed: scripts/install-files.sh --root $STAGE"
  fi
  export HOME="$WORK/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_STATE_HOME="$HOME/.local/state"
  export XDG_DATA_HOME="$HOME/.local/share"
  export BANCHY_LIB="$REPO/cli/lib"
  export BANCHY_SHARE="$STAGE/usr/share/banchy"
  unset BANCHY_SETTINGS BANCHY_BIN
  mkdir -p "$HOME"
}

# run_capture <cmd...> — capture combined output in $OUT and status in $RC.
RC=0
OUT=""
run_capture() {
  RC=0
  OUT="$("$@" 2>&1)" || RC=$?
}

assert_rc() {
  if [[ "$RC" -ne "$1" ]]; then
    t_fail "$2: expected rc=$1, got rc=$RC — output: $OUT"
  fi
}

assert_eq() {
  if [[ "$1" != "$2" ]]; then
    t_fail "$3: expected '$1', got '$2'"
  fi
}

assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) t_fail "$3: expected output to contain '$2' — output: $1" ;;
  esac
}

assert_not_contains() {
  case "$1" in
    *"$2"*) t_fail "$3: output must not contain '$2' — output: $1" ;;
  esac
}

assert_file() {
  if [[ ! -f "$1" ]]; then
    t_fail "missing file: $1"
  fi
}

assert_no_file() {
  if [[ -e "$1" ]]; then
    t_fail "file must not exist: $1"
  fi
}

assert_nonempty() {
  if [[ -z "${1//[[:space:]]/}" ]]; then
    t_fail "$2 is empty"
  fi
}

# digest_file <path> — stable fingerprint of a file, 'absent' when missing.
digest_file() {
  if [[ -f "$1" ]]; then
    cksum <"$1"
  else
    printf 'absent\n'
  fi
}

list_contains() {
  local needle="$1" item
  shift
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}
