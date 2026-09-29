# shellcheck shell=bash
# Package profiles: packages/profiles/*.list with @include and !directive lines.

b_profile_dir() {
  echo "$BANCHY_SHARE/packages/profiles"
}

b_profile_names() {
  local f
  for f in "$(b_profile_dir)"/*.list; do
    [[ -f "$f" ]] || continue
    basename "$f" .list
  done
}

# Resolve a profile list into B_PROFILE_PKGS (array) and B_PROFILE_FLAGS.
b_profile_resolve() {
  local name="$1"
  local dir
  dir="$(b_profile_dir)"
  [[ -f "$dir/$name.list" ]] || { b_err "unknown profile: $name"; return 1; }

  B_PROFILE_PKGS=()
  B_PROFILE_FLAGS=()
  local -A visiting=()
  local -A seen=()

  _b_profile_walk() {
    local n="$1"
    local file="$dir/$n.list"
    if [[ ! -f "$file" ]]; then
      b_err "profile include not found: $n"
      return 1
    fi
    if [[ -n "${visiting[$n]:-}" ]]; then
      b_err "profile include cycle at: $n"
      return 1
    fi
    visiting["$n"]=1
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%"${line##*[![:space:]]}"}"
      [[ -z "$line" || "$line" == \#* ]] && continue
      if [[ "$line" == @* ]]; then
        _b_profile_walk "${line#@}" || return 1
      elif [[ "$line" == !* ]]; then
        B_PROFILE_FLAGS+=("${line#!}")
      else
        if [[ -z "${seen[$line]:-}" ]]; then
          seen["$line"]=1
          B_PROFILE_PKGS+=("$line")
        fi
      fi
    done <"$file"
    unset 'visiting[$n]'
    return 0
  }

  _b_profile_walk "$name"
}

b_profile_enable_multilib() {
  if grep -Eq '^\s*\[multilib\]' /etc/pacman.conf; then
    b_ok "multilib is already enabled"
    return 0
  fi
  b_warn "this profile needs the multilib repository"
  if ! b_confirm "Enable [multilib] in /etc/pacman.conf?"; then
    b_err "multilib is required for this profile"
    return 1
  fi
  local tmp
  tmp="$(mktemp)"
  awk '
    /^\[multilib\]/,/^Include/ { next }
    /^#\[multilib\]/ { print "[multilib]"; print "Include = /etc/pacman.d/mirrorlist"; skip=1; next }
    /^\[core\]/ && !done {
      print "[multilib]"; print "Include = /etc/pacman.d/mirrorlist"; print ""; done=1
    }
    { print }
  ' /etc/pacman.conf >"$tmp"
  if ! grep -Eq '^\s*\[multilib\]' "$tmp"; then
    printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >>"$tmp"
  fi
  b_sudo cp /etc/pacman.conf "/etc/pacman.conf.banchy-bak-$(date +%Y%m%d%H%M%S)"
  b_sudo cp "$tmp" /etc/pacman.conf
  rm -f "$tmp"
  b_sudo pacman -Sy --noconfirm >/dev/null || {
    b_err "pacman database sync failed after enabling multilib"
    return 1
  }
  b_ok "multilib enabled"
  return 0
}

b_profile_apply() {
  local name="$1"
  b_profile_resolve "$name" || return 1

  if [[ ${#B_PROFILE_PKGS[@]} -eq 0 ]]; then
    b_err "profile '$name' contains no packages"
    return 1
  fi

  b_header "Profile: $name"
  b_info "${#B_PROFILE_PKGS[@]} package(s) queued"
  printf '  %s\n' "${B_PROFILE_PKGS[@]}"

  local flag
  for flag in "${B_PROFILE_FLAGS[@]:-}"; do
    case "$flag" in
      multilib) b_profile_enable_multilib || return 1 ;;
      "") ;;
      *) b_warn "unknown profile flag: $flag" ;;
    esac
  done

  if ! b_confirm "Install these packages?"; then
    b_info "cancelled"
    return 0
  fi
  b_package_install_do "${B_PROFILE_PKGS[@]}"
}

banchy_cmd_profile() {
  local sub="${1:-list}"
  shift || true
  case "$sub" in
    list)
      printf '%-12s %s\n' "PROFILE" "DESCRIPTION"
      local n
      while read -r n; do
        [[ -n "$n" ]] || continue
        local desc
        desc="$(head -20 "$(b_profile_dir)/$n.list" | grep -E '^# desc:' | head -1 | sed 's/^# desc:[[:space:]]*//')"
        printf '%-12s %s\n' "$n" "${desc:-}"
      done < <(b_profile_names)
      ;;
    show)
      b_profile_resolve "${1:?usage: banchy profile show <name>}" || return 1
      printf '%s\n' "${B_PROFILE_PKGS[@]}"
      ;;
    *)
      b_profile_apply "$sub"
      ;;
  esac
}
