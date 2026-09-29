# shellcheck shell=bash
# Banchy installer — package list merging, multilib detection and pacstrap.
#
# List format (same as packages/profiles/*.list used by 'banchy profile'):
#   # comment        blank lines ignored
#   @name            include packages/<profiles>/name.list
#   '!' flag        directive line (e.g. !multilib)
#   <package>        package name
#
# Profile resolution: minimal = base only; default = base + desktop;
# everything else = base + desktop + profiles/<name>.list.
set -euo pipefail

B_PKG_PACMAN_CONF=""
declare -ga B_PKG_PKGS=()
declare -ga B_PKG_FLAGS=()
declare -gA B_PKG_VISITING=()

pkg_share_dir() {
  # Package lists: live-ISO source tree first, then the staged share, then
  # the checkout this installer was started from.
  local c
  for c in "/usr/local/src/banchy-os/packages" \
    "${BANCHY_SHARE:-/usr/share/banchy}/packages" \
    "${B_INSTALL_REPO:-}/packages"; do
    [[ -n "$c" && -d "$c" ]] || continue
    printf '%s\n' "$c"
    return 0
  done
  return 1
}

pkg_profile_dir() {
  # pkg_profile_dir <share-dir> — profiles/<name>.list (with the legacy
  # $BANCHY_SHARE/profiles location as fallback).
  local share="$1"
  if [[ -d "$share/profiles" ]]; then
    printf '%s\n' "$share/profiles"
  elif [[ -d "${BANCHY_SHARE:-/usr/share/banchy}/profiles" ]]; then
    printf '%s\n' "${BANCHY_SHARE:-/usr/share/banchy}/profiles"
  else
    printf '%s\n' "$share/profiles"
  fi
}

pkg_walk_list() {
  # pkg_walk_list <file> <profiles-dir> — fills B_PKG_PKGS / B_PKG_FLAGS.
  local file="$1" pdir="$2" line
  [[ -f "$file" ]] || die "package list not found: $file"
  local key
  key="$(printf '%s' "$file" | cksum | cut -d' ' -f1)"
  if [[ -n "${B_PKG_VISITING[$key]:-}" ]]; then
    die "package list include cycle at: $file"
  fi
  B_PKG_VISITING["$key"]=1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" == @* ]]; then
      pkg_walk_list "$pdir/${line#@}.list" "$pdir"
    elif [[ "$line" == !* ]]; then
      B_PKG_FLAGS+=("${line#!}")
    else
      B_PKG_PKGS+=("$line")
    fi
  done <"$file"
  unset "B_PKG_VISITING[$key]"
  return 0
}

pkg_needs_multilib() {
  local f
  for f in ${B_PKG_FLAGS[@]+"${B_PKG_FLAGS[@]}"}; do
    [[ "$f" == "multilib" ]] && return 0
  done
  return 1
}

pkg_resolve() {
  # pkg_resolve <profile> — merged, deduplicated list in B_PKG_PKGS.
  local profile="$1" share pdir
  if ! share="$(pkg_share_dir)"; then
    die "no package lists found (expected /usr/local/src/banchy-os/packages or \$BANCHY_SHARE/packages)"
  fi
  pdir="$(pkg_profile_dir "$share")"
  b_info "package lists: $share"

  B_PKG_PKGS=()
  B_PKG_FLAGS=()
  B_PKG_VISITING=()

  [[ -f "$share/base.list" ]] || die "package list not found: $share/base.list"
  pkg_walk_list "$share/base.list" "$pdir"

  case "$profile" in
    minimal)
      ;;
    default)
      if [[ -f "$share/desktop.list" ]]; then
        pkg_walk_list "$share/desktop.list" "$pdir"
      else
        b_warn "packages/desktop.list missing — profile 'default' installs base only"
      fi
      ;;
    *)
      if [[ -f "$share/desktop.list" ]]; then
        pkg_walk_list "$share/desktop.list" "$pdir"
      else
        b_warn "packages/desktop.list missing — continuing without it"
      fi
      [[ -f "$pdir/$profile.list" ]] ||
        die "profile list not found: $pdir/$profile.list"
      pkg_walk_list "$pdir/$profile.list" "$pdir"
      ;;
  esac

  # Dedupe, preserving order.
  local -A seen=()
  local -a uniq=() p
  for p in ${B_PKG_PKGS[@]+"${B_PKG_PKGS[@]}"}; do
    [[ -n "${seen[$p]:-}" ]] && continue
    seen["$p"]=1
    uniq+=("$p")
  done
  B_PKG_PKGS=("${uniq[@]+"${uniq[@]}"}")

  b_ok "package list: ${#B_PKG_PKGS[@]} unique package(s) (profile: $profile)"
  return 0
}

pkg_enable_multilib_conf() {
  # pkg_enable_multilib_conf <file> — uncomment/append [multilib] in place.
  local f="$1"
  grep -Eq '^[[:space:]]*\[multilib\]' "$f" && return 0
  if grep -Eq '^[[:space:]]*#\[multilib\]' "$f"; then
    awk '
      state == 1 && /^#?Include/ { print "Include = /etc/pacman.d/mirrorlist"; state = 0; next }
      state == 1 { state = 0 }
      /^[[:space:]]*#\[multilib\]/ { print "[multilib]"; state = 1; next }
      { print }
    ' "$f" >"$f.banchy"
    mv "$f.banchy" "$f"
  else
    printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >>"$f"
  fi
  grep -Eq '^[[:space:]]*\[multilib\]' "$f" ||
    die "failed to enable [multilib] in $f"
  return 0
}

pkg_make_pacman_conf() {
  # pkg_make_pacman_conf <0|1 — enable multilib> — echoes a temp conf path.
  local need_ml="$1" tmp
  [[ -f /etc/pacman.conf ]] || die "live system has no /etc/pacman.conf"
  tmp="$(mktemp "${TMPDIR:-/tmp}/banchy-pacman.XXXXXX.conf")"
  cp /etc/pacman.conf "$tmp"
  if ((need_ml)); then
    pkg_enable_multilib_conf "$tmp"
    b_ok "temp pacman.conf enables [multilib]"
  fi
  printf '%s\n' "$tmp"
}

pkg_pacstrap() {
  # pkg_pacstrap <profile> <ext4|btrfs> — merged list + pacstrap -K -C.
  local profile="$1" fs="$2" need_ml=0 conf
  local -a extra=()

  pkg_resolve "$profile"
  if [[ "$fs" == "btrfs" ]]; then
    extra+=(btrfs-progs)
  fi
  pkg_needs_multilib && need_ml=1

  conf="$(pkg_make_pacman_conf "$need_ml")"
  # shellcheck disable=SC2034 # read by installer/banchy-install (pacman.conf to restore)
  B_PKG_PACMAN_CONF="$conf"

  if [[ ${#B_PKG_PKGS[@]} -eq 0 ]]; then
    die "package list for profile '$profile' is empty"
  fi

  i_cmd pacstrap -K -C "$conf" "$MNT" "${B_PKG_PKGS[@]}"
  pacstrap -K -C "$conf" "$MNT" "${B_PKG_PKGS[@]}"
  b_ok "pacstrap finished (${#B_PKG_PKGS[@]} packages)"

  # Keep the target's pacman.conf in sync when multilib was required.
  if ((need_ml)) && [[ -f "$MNT/etc/pacman.conf" ]]; then
    i_cmd cp "$conf" "$MNT/etc/pacman.conf"
    cp "$conf" "$MNT/etc/pacman.conf"
    b_ok "target /etc/pacman.conf keeps [multilib] enabled"
  fi
  return 0
}
