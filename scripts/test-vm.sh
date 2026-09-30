#!/usr/bin/env bash
# Banchy OS — headless QEMU smoke boot of a built ISO.
#
#   scripts/test-vm.sh [--bios] <iso> [timeout-seconds]   # timeout defaults to 480
#
#   (default)  boot with OVMF (UEFI firmware), the systemd-boot path
#   --bios     boot with SeaBIOS (legacy BIOS), the El Torito/SYSLINUX path;
#              no OVMF firmware is needed for this mode
#
# --- serial/expect design ----------------------------------------------------
# QEMU runs with `-display none -serial stdio -monitor none`, so the guest
# serial console *is* QEMU's stdio, and the QEMU process is started by
# `expect` via `spawn`: scripts/vm-smoke.exp is handed this script's full qemu
# command line (timeout first, then the command as separate argv entries;
# the .exp launches it with `spawn {*}$qcmd` so arguments containing spaces
# survive verbatim).  spawn wires QEMU's stdin/stdout directly to the expect
# process, so expect reads every byte the guest writes to the serial port and
# `send` writes keystrokes straight to the serial getty.  This is the design
# that reliably works with getty autologin — no fifos, no log scraping.
# `-monitor none` keeps the QEMU monitor from ever multiplexing itself onto
# the same stdio channel as the serial console.
#
# --- acceleration ------------------------------------------------------------
# `-enable-kvm` is used only when /dev/kvm is writable (bare metal, or CI
# runners with KVM passed through to the privileged container); otherwise the
# VM falls back to TCG (`-accel tcg`) so the test still runs without KVM —
# just slower.
#
# Exit status is expect's status.  Output is also teed to
# test-results/vm-smoke.log (UEFI) or test-results/vm-smoke-bios.log (BIOS)
# when the checkout is writable.  A trap on EXIT kills any leftover QEMU
# (identified by the unique per-run `-name`) and removes the temporary
# directory.
set -euo pipefail

usage() {
  echo "usage: $(basename "$0") [--bios] <iso> [timeout-seconds]   # timeout defaults to 480" >&2
  exit 2
}

die() {
  echo "test-vm: $*" >&2
  exit 1
}

BIOS=0
if [[ "${1:-}" == "--bios" ]]; then
  BIOS=1
  shift
fi

[[ $# -ge 1 && $# -le 2 ]] || usage

ISO="$1"
TIMEOUT="${2:-480}"

[[ -f "$ISO" ]] || die "ISO not found: $ISO"
[[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die "timeout must be a positive integer, got: $TIMEOUT"

command -v qemu-system-x86_64 >/dev/null 2>&1 || die "qemu-system-x86_64 not found (install qemu-system-x86)"
command -v expect >/dev/null 2>&1 || die "expect not found (install expect)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
EXP="$SCRIPT_DIR/vm-smoke.exp"
[[ -f "$EXP" ]] || die "missing expect driver: $EXP"

# --- OVMF firmware (UEFI mode only) ------------------------------------------
OVMF_CODE=""
VARS_SRC=""
if [[ "$BIOS" -eq 1 ]]; then
  : # SeaBIOS is built into QEMU; no firmware lookup needed.
else
  # Common distro layouts first, then a find over /usr/share.  Note: current
  # Arch (edk2-ovmf) ships /usr/share/edk2/x64/OVMF_CODE.4m.fd, not the plain
  # OVMF_CODE.fd, which is why the find fallback exists.
  SEARCHED=()
  for cand in \
    /usr/share/edk2/x64/OVMF_CODE.fd \
    /usr/share/ovmf/edk2-x86_64/OVMF_CODE.fd \
    /usr/share/ovmf/x64/OVMF_CODE.fd \
    /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
    /usr/share/edk2/x64/OVMF_CODE.4m.fd
  do
    SEARCHED+=("$cand")
    if [[ -f "$cand" ]]; then
      OVMF_CODE="$cand"
      break
    fi
  done

  if [[ -z "$OVMF_CODE" ]]; then
    # Sorted so a plain OVMF_CODE*.fd wins over OVMF_CODE.secboot*.fd.
    mapfile -t found < <(find /usr/share -maxdepth 5 -type f \
      \( -name 'OVMF_CODE*.fd' -o -name 'ovmf-x86_64-code.bin' \) \
      ! -name '*secboot*' 2>/dev/null | sort)
    for cand in ${found[@]+"${found[@]}"}; do
      SEARCHED+=("$cand")
    done
    if [[ ${#found[@]} -gt 0 ]]; then
      OVMF_CODE="${found[0]}"
    fi
  fi

  if [[ -z "$OVMF_CODE" ]]; then
    {
      echo "test-vm: OVMF firmware (OVMF_CODE*.fd) not found.  Searched:"
      printf '  %s\n' "${SEARCHED[@]}"
      echo "  plus: find /usr/share -name 'OVMF_CODE*.fd'"
      echo "  Install edk2-ovmf (Arch) / ovmf (Debian) to provide it."
    } >&2
    exit 1
  fi

  # Matching writable VARS template (OVMF_CODE -> OVMF_VARS rename, else glob).
  CODE_DIR="$(dirname "$OVMF_CODE")"
  CODE_BASE="$(basename "$OVMF_CODE")"
  VARS_BASE="${CODE_BASE/CODE/VARS}"
  if [[ -f "$CODE_DIR/$VARS_BASE" ]]; then
    VARS_SRC="$CODE_DIR/$VARS_BASE"
  else
    mapfile -t vfound < <(find "$CODE_DIR" -maxdepth 1 -type f -name 'OVMF_VARS*.fd' 2>/dev/null | sort)
    if [[ ${#vfound[@]} -gt 0 ]]; then
      VARS_SRC="${vfound[0]}"
    fi
  fi
  [[ -n "$VARS_SRC" ]] || die "no OVMF_VARS template found next to $OVMF_CODE (looked for $CODE_DIR/$VARS_BASE and $CODE_DIR/OVMF_VARS*.fd)"
fi

# --- work dir + cleanup ------------------------------------------------------
WORK="$(mktemp -d)"
VMNAME="banchy-smoke-$$-$(date +%s)"
# shellcheck disable=SC2317,SC2329  # invoked indirectly via: trap cleanup EXIT
cleanup() {
  local rc=$?
  # expect's spawned QEMU survives the driver; identify it by the unique
  # -name passed on its command line so we never kill an unrelated VM.
  if command -v pkill >/dev/null 2>&1; then
    pkill -f "$VMNAME" 2>/dev/null || true
  fi
  rm -rf "$WORK"
  exit "$rc"
}
trap cleanup EXIT
if [[ "$BIOS" -eq 0 ]]; then
  cp "$VARS_SRC" "$WORK/OVMF_VARS.fd"
fi

# --- build the QEMU command line --------------------------------------------
if [[ -w /dev/kvm ]]; then
  ACCEL=(-enable-kvm)
else
  ACCEL=(-accel tcg)
fi

QEMU_ARGS=(
  qemu-system-x86_64
  -M q35
  -m 4096
  -smp 2
  "${ACCEL[@]}"
  -name "$VMNAME"
  -cdrom "$ISO"
  -display none
  -serial stdio
  -monitor none
  -no-reboot
)

if [[ "$BIOS" -eq 0 ]]; then
  # UEFI: OVMF pflash firmware; -boot order=c keeps the previous behaviour.
  QEMU_ARGS+=(
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
    -drive "if=pflash,format=raw,file=$WORK/OVMF_VARS.fd"
    -boot
    "order=c"
  )
fi
# BIOS: no -boot and no pflash — SeaBIOS takes QEMU's default device order,
# which reaches the El Torito CD just like a plain `qemu -cdrom iso`.

echo "test-vm: iso=$ISO"
if [[ "$BIOS" -eq 1 ]]; then
  echo "test-vm: mode=bios timeout=${TIMEOUT}s accel=${ACCEL[*]} firmware=seabios"
else
  echo "test-vm: mode=uefi timeout=${TIMEOUT}s accel=${ACCEL[*]} firmware=$OVMF_CODE vars=$VARS_SRC"
fi

# --- run the expect driver ---------------------------------------------------
LOG_DIR="$REPO/test-results"
LOG=""
if mkdir -p "$LOG_DIR" 2>/dev/null && [[ -w "$LOG_DIR" ]]; then
  if [[ "$BIOS" -eq 1 ]]; then
    LOG="$LOG_DIR/vm-smoke-bios.log"
  else
    LOG="$LOG_DIR/vm-smoke.log"
  fi
fi

set +e
if [[ -n "$LOG" ]]; then
  expect "$EXP" "$TIMEOUT" "${QEMU_ARGS[@]}" 2>&1 | tee "$LOG"
  rc="${PIPESTATUS[0]}"
else
  expect "$EXP" "$TIMEOUT" "${QEMU_ARGS[@]}" 2>&1
  rc=$?
fi
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "test-vm: PASS — smoke checks succeeded${LOG:+ (log: $LOG)}"
else
  echo "test-vm: FAIL — expect exited with status $rc${LOG:+ (log: $LOG)}" >&2
fi
exit "$rc"
