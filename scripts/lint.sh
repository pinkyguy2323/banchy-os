#!/usr/bin/env bash
# Banchy OS — pre-CI lint gate (CI runs exactly: bash scripts/lint.sh).
#
#   (a) bash -n   every *.sh plus the extensionless bash executables
#   (b) shellcheck over the same set (hard failure in CI when missing)
#   (c) python3 -m py_compile for the GTK apps
#   (d) warn-only executable-bit check for the key scripts
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

failures=0
warnings=0

ok() { printf '[OK]   %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; warnings=$((warnings + 1)); }
fail() { printf '[FAIL] %s\n' "$1"; failures=$((failures + 1)); }

# --- collect the lint surface ----------------------------------------------
sh_files=()
while IFS= read -r -d '' f; do
  sh_files+=("$f")
done < <(find . -type f -name '*.sh' \
  -not -path './.git/*' -not -path './out/*' -not -path './work/*' -print0 |
  sort -z)

exec_files=()
for candidate in cli/banchy cli/bin/* first-run/* boot/recovery/banchy-recovery \
  installer/banchy-install; do
  if [[ -f "$candidate" ]]; then
    exec_files+=("$candidate")
  fi
done

all_files=("${sh_files[@]}" ${exec_files[@]+"${exec_files[@]}"})

# --- (a) bash -n ------------------------------------------------------------
bashn_errors="$(mktemp)"
for file in "${all_files[@]}"; do
  if ! bash -n "$file" 2>"$bashn_errors"; then
    fail "bash -n: $file"
    sed 's/^/       /' "$bashn_errors"
  fi
done
rm -f "$bashn_errors"
if ((failures == 0)); then
  ok "bash -n: ${#sh_files[@]} .sh files, ${#exec_files[@]} extensionless executables"
fi

# --- (b) shellcheck ---------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
  # -x/-P let the entry points follow their `# shellcheck source=` annotations
  # (SCRIPTDIR resolves them next to each entry point); every library is also
  # linted as an input of its own.
  if shellcheck -s bash -x -P SCRIPTDIR "${all_files[@]}"; then
    ok "shellcheck: ${#all_files[@]} files clean"
  else
    fail "shellcheck reported findings (see above)"
  fi
elif [[ -n "${CI:-}" ]]; then
  fail "shellcheck is not on PATH (required when CI is set)"
else
  warn "shellcheck is not on PATH — skipped (install shellcheck or shellcheck-py)"
fi

# --- (c) python compile -----------------------------------------------------
python_bin=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1; then
    python_bin="$candidate"
    break
  fi
done
if [[ -z "$python_bin" ]]; then
  fail "python3 not found (needed for apps/banchy-settings and apps/banchy-cc)"
elif "$python_bin" -m py_compile apps/banchy-settings apps/banchy-cc; then
  ok "py_compile: apps/banchy-settings apps/banchy-cc ($python_bin)"
else
  fail "py_compile failed for the GTK apps"
fi

# --- (d) executable bits (warn only) ---------------------------------------
key_scripts=()
for candidate in cli/banchy cli/bin/* first-run/* boot/recovery/banchy-recovery \
  installer/banchy-install scripts/*.sh tests/run.sh tests/test_*.sh \
  apps/banchy-settings apps/banchy-cc; do
  if [[ -f "$candidate" ]]; then
    key_scripts+=("$candidate")
  fi
done
exec_warnings=0
for file in "${key_scripts[@]}"; do
  if [[ ! -x "$file" ]]; then
    warn "not executable (chmod +x): $file"
    exec_warnings=$((exec_warnings + 1))
  fi
done
if ((exec_warnings == 0)); then
  ok "executable bits: ${#key_scripts[@]} key scripts"
fi

# --- summary ----------------------------------------------------------------
printf '\nlint: %d failure(s), %d warning(s)\n' "$failures" "$warnings"
if ((failures > 0)); then
  exit 1
fi
exit 0
