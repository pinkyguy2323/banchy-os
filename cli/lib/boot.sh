# shellcheck shell=bash
# Banchy Boot — systemd-boot management with safety, backup and rollback.
#
# Design priorities: reliability > recovery > convenience > design.
# Never deletes the last known good boot entry; every modification is
# preceded by a backup and followed by verification.

B_BOOT_LOADER_CONF='timeout 3
default 01-banchy.conf
editor no
console-mode max'

b_boot_is_installed_system() {
  local root="${1:-/}"
  [[ "$root" == "/" ]] && ((BANCHY_LIVE == 0))
}

# Resolve ESP mountpoint for a root ("live" systems keep ESP at /boot too).
b_boot_esp() {
  local root="${1:-/}"
  if [[ "$root" == "/" ]]; then
    findmnt -rn -o TARGET -T /boot 2>/dev/null | tail -1
  else
    findmnt -rn -o TARGET -T "$root/boot" 2>/dev/null | tail -1
  fi
}

# Build "root=UUID=... [rootflags=...]" for entries of the given root.
b_boot_root_params() {
  local root="${1:-/}"
  local src uuid opts rootflags="" params

  if [[ "$root" == "/" ]]; then
    src="$(findmnt -rn -o SOURCE / 2>/dev/null | head -1)"
  else
    src="$(findmnt -rn -o SOURCE --target "$root" 2>/dev/null | head -1)"
  fi
  [[ -n "$src" ]] || return 1

  # Resolve mapper devices to their underlying block device when possible.
  if [[ -b "$src" ]]; then
    uuid="$(blkid -s UUID -o value "$src" 2>/dev/null || true)"
  fi
  if [[ -z "$uuid" ]]; then
    uuid="$(lsblk -no UUID "$src" 2>/dev/null | head -1 | xargs || true)"
  fi
  [[ -n "$uuid" ]] || return 1

  if [[ "$root" == "/" ]]; then
    opts="$(findmnt -rn -o OPTIONS / 2>/dev/null | head -1)"
  else
    opts="$(findmnt -rn -o OPTIONS --target "$root" 2>/dev/null | head -1)"
  fi
  if [[ ",$opts," == *",subvol="* ]]; then
    local subvol
    subvol="$(echo "$opts" | tr ',' '\n' | grep '^subvol=' | head -1)"
    rootflags="$subvol"
    local comp
    comp="$(echo "$opts" | tr ',' '\n' | grep '^compress=' | head -1)"
    [[ -n "$comp" ]] && rootflags+=",$comp"
  fi

  params="root=UUID=$uuid"
  [[ -n "$rootflags" ]] && params+=" rootflags=$rootflags"
  echo "$params"
}

# Write loader.conf and all boot entries. NEVER wipes the entries directory.
b_boot_write_entries() {
  local root="${1:-/}"
  local serial="${2:-0}"
  local boot="$root/boot"
  local entries="$boot/loader/entries"

  # When the ESP is mounted at a path other than /boot we still generate
  # entries relative to the ESP root; systemd-boot resolves paths from ESP root.
  local esp
  esp="$(b_boot_esp "$root")"
  [[ -n "$esp" ]] || { b_err "cannot locate ESP for $root"; return 1; }
  if [[ "$esp" != "$root" && "$esp" != "$root/boot" ]]; then
    # Kernels live on the ESP itself (standard Banchy layout uses /boot).
    b_warn "ESP at $esp differs from expected $root/boot — entries may need adjustment"
  fi
  mkdir -p "$entries"

  local root_params
  if ! root_params="$(b_boot_root_params "$root")"; then
    b_err "cannot determine root filesystem UUID for $root"
    return 1
  fi

  local console=""
  [[ "$serial" == "1" ]] && console=" console=ttyS0,115200"

  # 1. Main entry.
  if [[ -f "$boot/vmlinuz-linux" && -f "$boot/initramfs-linux.img" ]]; then
    cat >"$entries/01-banchy.conf" <<EOF
title   Banchy OS
sort-key banchy
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options $root_params quiet rw$console
EOF
  else
    b_err "main kernel files missing under $boot"
    return 1
  fi

  # 2. Previous working kernel (linux-lts fallback — always installed).
  if [[ -f "$boot/vmlinuz-linux-lts" && -f "$boot/initramfs-linux-lts.img" ]]; then
    cat >"$entries/02-banchy-previous.conf" <<EOF
title   Banchy OS - Previous Kernel
sort-key banchy
linux   /vmlinuz-linux-lts
initrd  /initramfs-linux-lts.img
options $root_params quiet rw$console
EOF
  else
    b_warn "linux-lts fallback kernel not present — previous-kernel entry not written"
  fi

  # 3. Recovery entry (root shell, no quiet).
  cat >"$entries/03-banchy-recovery.conf" <<EOF
title   Banchy OS - Recovery
sort-key banchy
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options $root_params rw systemd.unit=rescue.target$console
EOF

  # 4. Verbose entry (full boot messages for diagnosis).
  cat >"$entries/04-banchy-verbose.conf" <<EOF
title   Banchy OS - Verbose
sort-key banchy
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options $root_params rw$console
EOF

  mkdir -p "$boot/loader"
  printf '%s\n' "$B_BOOT_LOADER_CONF" >"$boot/loader/loader.conf"
  b_ok "boot entries written to $entries"
  return 0
}

# Verify ESP, loader configuration, entries, kernels and initramfs.
# Prints [OK]/[WARN]/[FAIL] lines. Returns the number of failures.
b_boot_check() {
  local root="/"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --root) root="${2:?}"; shift ;;
      *) b_err "boot check: unknown option '$1'"; return 2 ;;
    esac
    shift
  done

  local fails=0
  local boot="$root/boot"

  # --- ESP ---
  local esp
  esp="$(b_boot_esp "$root")"
  if [[ -z "$esp" ]]; then
    if ((BANCHY_LIVE)) && [[ "$root" == "/" ]]; then
      b_warn "ESP: not mounted (live image)"
    else
      b_fail "ESP: no filesystem mounted at $boot"
      fails=$((fails + 1))
    fi
  else
    local fstype
    fstype="$(findmnt -rn -o FSTYPE -T "$boot" 2>/dev/null | head -1)"
    if [[ "$fstype" != "vfat" ]]; then
      b_warn "ESP: $esp has filesystem '$fstype' (expected vfat)"
    else
      b_ok "ESP: $esp ($fstype)"
    fi
    if [[ -w "$boot" ]] || [[ -w "$root/boot" ]]; then
      if touch "$root/boot/.banchy-write-test" 2>/dev/null; then
        rm -f "$root/boot/.banchy-write-test"
        b_ok "ESP: writable"
      else
        b_fail "ESP: not writable"
        fails=$((fails + 1))
      fi
    fi
  fi

  # --- loader.conf ---
  if [[ -f "$boot/loader/loader.conf" ]]; then
    if grep -q "editor no" "$boot/loader/loader.conf"; then
      b_ok "loader.conf present (editor disabled)"
    else
      b_warn "loader.conf: editor not disabled"
    fi
  else
    b_fail "loader.conf missing at $boot/loader/loader.conf"
    fails=$((fails + 1))
  fi

  # --- entries ---
  local entries_dir="$boot/loader/entries"
  local count=0
  if [[ -d "$entries_dir" ]]; then
    count="$(find "$entries_dir" -maxdepth 1 -name '*.conf' | wc -l)"
  fi
  if ((count == 0)); then
    b_fail "no boot entries found"
    fails=$((fails + 1))
  else
    b_ok "boot entries: $count"
    local entry line target name
    while IFS= read -r entry; do
      local entry_fail=0
      name="$(basename "$entry")"
      while IFS= read -r line; do
        case "$line" in
          linux*|LINUX*)
            target="$boot$(echo "$line" | awk '{print $2}')"
            if [[ ! -f "$target" ]]; then
              entry_fail=1
              b_fail "$name: kernel missing: ${target#"$root"}"
            fi
            ;;
          initrd*|INITRD*)
            target="$boot$(echo "$line" | awk '{print $2}')"
            if [[ ! -f "$target" ]]; then
              entry_fail=1
              b_fail "$name: initramfs missing: ${target#"$root"}"
            fi
            ;;
        esac
      done <"$entry"
      if ((entry_fail == 0)); then
        b_ok "$name"
      else
        fails=$((fails + 1))
      fi
    done < <(find "$entries_dir" -maxdepth 1 -name '*.conf' | sort)
  fi

  # --- fallback entry exists? ---
  if [[ -d "$entries_dir" && ! -f "$entries_dir/02-banchy-previous.conf" ]]; then
    b_warn "previous-kernel entry missing (fallback unavailable)"
  fi

  # --- root UUID consistency (installed system only) ---
  if ((BANCHY_LIVE == 0)) && [[ "$root" == "/" ]]; then
    local actual expected uuid_fails=0
    actual="$(findmnt -rn -o UUID / 2>/dev/null | head -1)"
    if [[ -n "$actual" && -d "$entries_dir" ]]; then
      while IFS= read -r entry; do
        expected="$(grep -o 'root=UUID=[0-9a-f-]*' "$entry" | head -1 | cut -d= -f3)"
        if [[ -n "$expected" && "$expected" != "$actual" ]]; then
          b_fail "$(basename "$entry"): root UUID $expected != actual $actual"
          uuid_fails=$((uuid_fails + 1))
        fi
      done < <(find "$entries_dir" -maxdepth 1 -name '*.conf' | sort)
      if ((uuid_fails == 0)); then
        b_ok "root UUID matches all entries"
      else
        fails=$((fails + uuid_fails))
      fi
    fi
  fi

  # --- bootctl ---
  if ((BANCHY_LIVE == 0)) && [[ "$root" == "/" ]] && [[ -d /sys/firmware/efi ]]; then
    if b_have bootctl && bootctl status >/dev/null 2>&1; then
      b_ok "bootctl: systemd-boot installed"
    else
      b_fail "bootctl: systemd-boot not installed (run 'banchy boot repair')"
      fails=$((fails + 1))
    fi
  fi

  return "$fails"
}

# Internal: full install/repair flow with pre-checks, backup and verification.
b_boot__install() {
  local root="/" serial=0 mkinit=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --root) root="${2:?}"; shift ;;
      --serial) serial=1 ;;
      --auto) ;; # accepted for non-interactive callers (boot hook, update);
                 # this flow never prompts, so there is nothing to suppress.
      --mkinitcpio) mkinit=1 ;;
      *) b_err "boot install: unknown option '$1'"; return 2 ;;
    esac
    shift
  done

  b_ensure_root

  # ---- PRE-CHECKS (before touching anything) ----
  b_header "Banchy Boot — pre-flight checks"
  local pre_fail=0

  if [[ ! -d "$root/boot" ]]; then
    b_fail "EFI System Partition not mounted at ${root%/}/boot"
    pre_fail=1
  else
    b_ok "EFI System Partition mounted"
  fi

  if [[ -f "$root/boot/vmlinuz-linux" ]]; then
    b_ok "kernel present"
  else
    b_fail "kernel missing (vmlinuz-linux)"
    pre_fail=1
  fi

  if [[ -f "$root/boot/initramfs-linux.img" ]]; then
    b_ok "initramfs present"
  else
    if ((mkinit)) && b_have mkinitcpio; then
      b_warn "initramfs missing — regenerating"
      if [[ "$root" == "/" ]]; then
        b_sudo mkinitcpio -P || pre_fail=1
      else
        arch-chroot "$root" mkinitcpio -P || pre_fail=1
      fi
      [[ -f "$root/boot/initramfs-linux.img" ]] || pre_fail=1
    else
      b_fail "initramfs missing (initramfs-linux.img)"
      pre_fail=1
    fi
  fi

  if ((pre_fail)); then
    b_err "pre-flight failed — boot configuration was NOT modified"
    return 1
  fi

  # ---- BACKUP ----
  local backup_root="$root/var/lib/banchy/boot-backup"
  local backup
  backup="$backup_root/$(date +%Y%m%d-%H%M%S)"
  if [[ -d "$root/boot/loader" ]]; then
    mkdir -p "$backup"
    cp -a "$root/boot/loader" "$backup/loader"
    echo "$backup" >"$backup_root/last-backup"
    # Keep only the newest 10 boot backups.
    # shellcheck disable=SC2012
    ls -1dt "$backup_root"/20* 2>/dev/null | tail -n +11 | xargs -r rm -rf
    b_ok "boot configuration backed up: $backup"
  fi

  # ---- APPLY ----
  b_header "Banchy Boot — applying"
  if b_have bootctl; then
    if [[ "$root" == "/" ]]; then
      b_sudo bootctl install >/dev/null 2>&1 || b_warn "bootctl install reported: already installed?"
    else
      arch-chroot "$root" bootctl install >/dev/null 2>&1 || \
        b_warn "bootctl install reported: already installed?"
    fi
    b_ok "bootctl: installed"
  else
    b_fail "bootctl not available"
    return 1
  fi

  if ! b_boot_write_entries "$root" "$serial"; then
    b_err "writing boot entries failed — restoring backup"
    if [[ -d "$backup/loader" ]]; then
      rm -rf "$root/boot/loader"
      cp -a "$backup/loader" "$root/boot/loader"
    fi
    return 1
  fi

  # ---- VERIFY ----
  b_header "Banchy Boot — verification"
  local rc=0
  if [[ "$root" == "/" ]]; then
    set +e
    b_boot_check
    rc=$?
    set -e
  else
    # In a chroot, run a reduced structural verification.
    local e e_name
    for e in "$root/boot/loader/entries"/*.conf; do
      [[ -f "$e" ]] || continue
      e_name="$(basename "$e")"
      local l
      while IFS= read -r l; do
        if [[ "$l" =~ ^linux[[:space:]]+(.*)$ ]]; then
          if [[ ! -f "$root/boot/${BASH_REMATCH[1]}" ]]; then
            b_fail "$e_name: kernel missing"
            rc=1
          fi
        fi
        if [[ "$l" =~ ^initrd[[:space:]]+(.*)$ ]]; then
          if [[ ! -f "$root/boot/${BASH_REMATCH[1]}" ]]; then
            b_fail "$e_name: initramfs missing"
            rc=1
          fi
        fi
      done <"$e"
    done
    [[ -f "$root/boot/loader/loader.conf" ]] || { b_fail "loader.conf missing"; rc=1; }
    ((rc == 0)) && b_ok "chroot verification passed"
  fi

  if ((rc != 0)); then
    b_err "verification FAILED — rolling back to previous boot configuration"
    if [[ -d "$backup/loader" ]]; then
      rm -rf "$root/boot/loader"
      cp -a "$backup/loader" "$root/boot/loader"
      b_warn "rollback complete: previous boot configuration restored"
    else
      b_warn "no backup available to restore"
    fi
    return 1
  fi

  b_ok "Banchy Boot verified successfully"
  echo "$backup" >"$backup_root/last-known-good"
  return 0
}

banchy_cmd_boot() {
  local sub="${1:-check}"
  shift || true
  case "$sub" in
    check)
      local rc=0
      b_boot_check "$@" || rc=$?
      if ((rc == 0)); then
        return 0
      fi
      return 1
      ;;
    install)
      local rc=0
      b_boot__install "$@" || rc=$?
      return "$rc"
      ;;
    repair)
      b_header "Banchy Boot — repair"
      if [[ -t 0 ]]; then
        b_confirm "Reinstall systemd-boot and regenerate all boot entries?" || {
          b_info "cancelled"
          return 0
        }
      fi
      b_boot__install --mkinitcpio "$@"
      ;;
    backup)
      b_ensure_root
      local br
      br="/var/lib/banchy/boot-backup/$(date +%Y%m%d-%H%M%S)"
      if [[ -d /boot/loader ]]; then
        mkdir -p "$br"
        cp -a /boot/loader "$br/loader"
        echo "$br" >/var/lib/banchy/boot-backup/last-backup
        b_ok "boot configuration backed up: $br"
      else
        b_err "no /boot/loader to back up"
        return 1
      fi
      ;;
    *) b_err "usage: banchy boot [check|install|repair|backup]"; return 2 ;;
  esac
}
