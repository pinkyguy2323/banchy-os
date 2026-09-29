# shellcheck shell=bash
# Banchy installer — disk listing, partitioning, filesystems, mounts, swap.
# Swap is created as a SWAP FILE on the root filesystem (size chosen in the
# disk step); sfdisk writes GPT + 512MiB EFI + the rest Linux.
set -euo pipefail

DISK_ESP_SIZE="${DISK_ESP_SIZE:-512MiB}"
DISK_GPT_ESP_TYPE="C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
DISK_GPT_LINUX_TYPE="0FC63DAF-8483-4772-8E79-3D69D8477DE4"

disk_list() {
  # Print "dev<TAB>size model" for every whole disk.
  local name type size model
  while read -r name type; do
    [[ "$type" == "disk" ]] || continue
    size="$(lsblk -dn -o SIZE "/dev/$name" 2>/dev/null | xargs || true)"
    model="$(lsblk -dn -o MODEL "/dev/$name" 2>/dev/null | xargs || true)"
    printf '%s\t%s %s\n' "/dev/$name" "${size:-?}" "${model:-unknown model}"
  done < <(lsblk -dn -o NAME,TYPE)
}

disk_select() {
  # Interactive disk menu; echoes the chosen /dev/... device, rc 1 on cancel.
  local dev desc
  local -a entries=()
  while IFS=$'\t' read -r dev desc; do
    [[ -n "$dev" ]] || continue
    entries+=("$dev" "$desc")
  done < <(disk_list)
  if [[ ${#entries[@]} -eq 0 ]]; then
    b_err "no disks found (lsblk reported no devices of type 'disk')"
    return 1
  fi
  ui_menu "Target disk" "${entries[@]}"
}

disk_validate() {
  # disk_validate <dev> — whole block device of type 'disk'.
  local dev="$1" type
  [[ -b "$dev" ]] || { b_err "not a block device: $dev"; return 1; }
  type="$(lsblk -dn -o TYPE "$dev" 2>/dev/null | xargs || true)"
  [[ "$type" == "disk" ]] || { b_err "$dev is not a whole disk (type: ${type:-unknown})"; return 1; }
  return 0
}

disk_mounted_summary() {
  # disk_mounted_summary <dev> — "mounted: / ..." for the confirm dialog.
  local dev="$1" mp
  mp="$(lsblk -nr -o MOUNTPOINT "$dev" 2>/dev/null | sed '/^[[:space:]]*$/d' | xargs || true)"
  if [[ -n "$mp" ]]; then
    printf 'Currently mounted: %s' "$mp"
  fi
  return 0
}

disk_part_path() {
  # disk_part_path <dev> <num> — /dev/sda 2 -> /dev/sda2, nvme -> ...p2
  local d="$1" n="$2"
  if [[ "$d" =~ [0-9]$ ]]; then
    printf '%sp%s\n' "$d" "$n"
  else
    printf '%s%s\n' "$d" "$n"
  fi
}

disk_partition() {
  # disk_partition <dev> — GPT: 512MiB EFI System + rest Linux (swap file
  # is created later on the root filesystem).
  local dev="$1" script
  script="label: gpt
name=ESP, size=$DISK_ESP_SIZE, type=$DISK_GPT_ESP_TYPE
name=root, type=$DISK_GPT_LINUX_TYPE"
  b_header "Partitioning $dev (GPT)"
  i_cmd sfdisk --wipe always "$dev"
  log "sfdisk script for $dev:"
  log "$script"
  printf '%s\n' "$script" | sfdisk --wipe always "$dev"
  disk_settle "$dev"
}

disk_settle() {
  # Wait for the kernel/udev to expose the new partition nodes.
  local dev="$1"
  if command -v partprobe >/dev/null 2>&1; then
    partprobe "$dev" 2>/dev/null || true
  fi
  if command -v udevadm >/dev/null 2>&1; then
    udevadm settle 2>/dev/null || true
  fi
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if [[ -b "$(disk_part_path "$dev" 1)" && -b "$(disk_part_path "$dev" 2)" ]]; then
      return 0
    fi
    sleep 0.5
  done
  b_warn "partition nodes for $dev did not all appear — continuing anyway"
  return 0
}

disk_mkfs_esp() {
  # disk_mkfs_esp <part>
  local part="$1"
  i_cmd mkfs.fat -F32 "$part"
  mkfs.fat -F32 "$part"
  b_ok "EFI System Partition formatted (FAT32): $part"
}

disk_mkfs_root() {
  # disk_mkfs_root <part> <ext4|btrfs>
  local part="$1" fs="$2"
  case "$fs" in
    ext4)
      i_cmd mkfs.ext4 -F "$part"
      mkfs.ext4 -F "$part"
      ;;
    btrfs)
      i_cmd mkfs.btrfs -f "$part"
      mkfs.btrfs -f "$part"
      ;;
    *)
      b_err "unsupported filesystem: $fs"
      return 1
      ;;
  esac
  b_ok "root filesystem created ($fs): $part"
}

disk_mount_root() {
  # disk_mount_root <part> <ext4|btrfs> — mount root at $MNT (btrfs: create
  # and mount the @ / @home subvolumes with compress=zstd).
  local part="$1" fs="$2"
  mkdir -p "$MNT"
  i_cmd mount "$part" "$MNT"
  mount "$part" "$MNT"
  if [[ "$fs" == "btrfs" ]]; then
    i_cmd btrfs subvolume create "$MNT/@"
    btrfs subvolume create "$MNT/@"
    i_cmd btrfs subvolume create "$MNT/@home"
    btrfs subvolume create "$MNT/@home"
    i_cmd umount "$MNT"
    umount "$MNT"
    i_cmd mount -o subvol=@,compress=zstd "$part" "$MNT"
    mount -o subvol=@,compress=zstd "$part" "$MNT"
    mkdir -p "$MNT/home"
    i_cmd mount -o subvol=@home,compress=zstd "$part" "$MNT/home"
    mount -o subvol=@home,compress=zstd "$part" "$MNT/home"
    b_ok "root mounted with subvolumes @ and @home (compress=zstd)"
  else
    b_ok "root mounted at $MNT"
  fi
}

disk_mount_esp() {
  # disk_mount_esp <part> — ESP at $MNT/boot (kernels live on the ESP).
  local part="$1"
  mkdir -p "$MNT/boot"
  i_cmd mount "$part" "$MNT/boot"
  mount "$part" "$MNT/boot"
  b_ok "EFI System Partition mounted at $MNT/boot"
}

disk_swapfile_create() {
  # disk_swapfile_create <ext4|btrfs> <size|none> — swap file + fstab entry.
  local fs="$1" size="$2" f="$MNT/swapfile"
  case "$size" in
    "" | none | off | 0)
      b_info "swap: none"
      return 0
      ;;
  esac
  if [[ "$fs" == "btrfs" ]]; then
    i_cmd btrfs filesystem mkswapfile "$f"
    btrfs filesystem mkswapfile "$f"
  else
    i_cmd fallocate -l "$size" "$f"
    fallocate -l "$size" "$f"
  fi
  i_cmd chmod 600 "$f"
  chmod 600 "$f"
  i_cmd mkswap "$f"
  mkswap "$f"
  i_cmd swapon "$f"
  swapon "$f"
  printf '/swapfile none swap defaults 0 0\n' >>"$MNT/etc/fstab"
  log "fstab: appended '/swapfile none swap defaults 0 0'"
  b_ok "swap file created and enabled: $size ($f)"
}

disk_unmount_all() {
  # Best-effort teardown; returns non-zero if $MNT could not be unmounted.
  i_cmd swapoff -a
  swapoff -a 2>/dev/null || true
  i_cmd umount -R "$MNT"
  umount -R "$MNT" 2>/dev/null || return 1
  return 0
}
