#!/usr/bin/env bash
# Build the Banchy OS ISO locally (Arch Linux + archiso, or a privileged
# archlinux container). Mirrors the CI build in .github/workflows/iso.yml:
#   gen-packages -> stage live system -> stage repo copy -> mkarchiso ->
#   normalize name -> sha256 -> optional QEMU smoke test.
#
# Usage: scripts/build-iso.sh [--out DIR] [--no-vm]
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO/out"
VM=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="${2:?--out needs a directory}"; shift ;;
    --no-vm) VM=0 ;;
    *) echo "build-iso: unknown option '$1'" >&2; exit 2 ;;
  esac
  shift
done

cd "$REPO"

command -v mkarchiso >/dev/null 2>&1 || {
  echo "build-iso: mkarchiso not found — install archiso (pacman -S archiso)" >&2
  exit 1
}

echo "build-iso: generating package list"
./iso/gen-packages.sh

echo "build-iso: staging live system into airootfs"
./scripts/install-files.sh --root iso/profile/airootfs

echo "build-iso: staging repository source for the installer"
SRC="iso/profile/airootfs/usr/local/src/banchy-os"
rm -rf "$SRC"
mkdir -p "$SRC"
tar --exclude-vcs --exclude=iso/profile/airootfs -cf - . | tar -C "$SRC" -xf -

mkdir -p "$OUT"
echo "build-iso: running mkarchiso (output: $OUT)"
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  mkarchiso -v -w "$REPO/work" -o "$OUT" iso/profile
else
  sudo mkarchiso -v -w "$REPO/work" -o "$OUT" iso/profile
fi

echo "build-iso: normalizing artifact name"
iso_src="$(find "$OUT" -maxdepth 1 -name '*.iso' -print -quit)"
[[ -n "$iso_src" ]] || { echo "build-iso: no ISO produced in $OUT" >&2; exit 1; }
mv "$iso_src" "$OUT/banchy-os-x86_64.iso"
(cd "$OUT" && sha256sum banchy-os-x86_64.iso > banchy-os-x86_64.iso.sha256)

size_mib="$(du -m "$OUT/banchy-os-x86_64.iso" | cut -f1)"
echo "build-iso: banchy-os-x86_64.iso (${size_mib} MiB)"
if ((size_mib > 2048)); then
  echo "build-iso: ERROR ISO is larger than 2048 MiB — trim packages/iso.list" >&2
  exit 1
fi

if ((VM)); then
  echo "build-iso: running QEMU smoke test"
  "$REPO/scripts/test-vm.sh" "$OUT/banchy-os-x86_64.iso"
fi

echo "build-iso: done — $OUT/banchy-os-x86_64.iso"
