#!/usr/bin/env bash
# Generate iso/profile/packages.x86_64 from the repository package lists.
#
#   iso/gen-packages.sh
#
# Concatenates packages/base.list, packages/desktop.list and packages/iso.list,
# strips comments and blank lines, de-duplicates while preserving order,
# validates every remaining line as a plausible package (or group) name and
# refuses to write an empty result. Run this before mkarchiso.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/.." && pwd)"
out_file="${script_dir}/profile/packages.x86_64"

inputs=(
  "${repo_dir}/packages/base.list"
  "${repo_dir}/packages/desktop.list"
  "${repo_dir}/packages/iso.list"
)

for f in "${inputs[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "gen-packages: missing input: $f" >&2
    exit 1
  fi
done

tmp="$(mktemp)"
out_tmp="${out_file}.tmp"
cleanup() { rm -f "$tmp" "$out_tmp"; }
trap cleanup EXIT

for f in "${inputs[@]}"; do
  # Drop CR, comments and surrounding whitespace.
  sed -e 's/\r$//' -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$f"
done >"$tmp"

mkdir -p "$(dirname -- "$out_file")"

if ! awk '
  NF == 0 { next }
  !/^[a-z0-9@._+-]+$/ {
    printf "gen-packages: invalid package name: %s\n", $0 > "/dev/stderr"
    bad = 1
    next
  }
  !seen[$0]++ { print }
  END { if (bad) exit 1 }
' "$tmp" >"$out_tmp"; then
  echo "gen-packages: validation failed, nothing written" >&2
  exit 1
fi

count="$(wc -l <"$out_tmp")"
count="${count//[[:space:]]/}"

if [[ -z "$count" || "$count" -eq 0 ]]; then
  echo "gen-packages: refusing to write an empty package list" >&2
  exit 1
fi

mv -f "$out_tmp" "$out_file"
echo "gen-packages: wrote ${count} packages to iso/profile/packages.x86_64"
