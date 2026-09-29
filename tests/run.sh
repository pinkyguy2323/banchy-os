#!/usr/bin/env bash
# Banchy OS — test runner (CI runs exactly: bash tests/run.sh).
# Runs every tests/test_*.sh in order and prints PASS/FAIL per test.
set -euo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

tests=()
for test_file in "$TESTS_DIR"/test_*.sh; do
  if [[ -f "$test_file" ]]; then
    tests+=("$test_file")
  fi
done

if ((${#tests[@]} == 0)); then
  printf 'run.sh: no tests/test_*.sh files found in %s\n' "$TESTS_DIR" >&2
  exit 1
fi

total=0
passed=0
failed=0

for test_file in "${tests[@]}"; do
  name="$(basename "$test_file" .sh)"
  total=$((total + 1))
  printf '=== %s ===\n' "$name"
  if bash "$test_file"; then
    printf 'PASS %s\n' "$name"
    passed=$((passed + 1))
  else
    printf 'FAIL %s\n' "$name"
    failed=$((failed + 1))
  fi
  printf '\n'
done

printf 'total %d passed %d failed %d\n' "$total" "$passed" "$failed"

if ((failed > 0)); then
  exit 1
fi
exit 0
