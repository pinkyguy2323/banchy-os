# shellcheck shell=bash
# banchy doctor — system health checks.

declare -i B_DOC_OK=0 B_DOC_WARN=0 B_DOC_FAIL=0

b_doc_result() {
  # b_doc_result <ok|warn|fail> <label> [detail]
  local level="$1" label="$2" detail="${3:-}"
  case "$level" in
    ok)   b_ok "$label${detail:+ — $detail}"; B_DOC_OK=$((B_DOC_OK + 1)) ;;
    warn) b_warn "$label${detail:+ — $detail}"; B_DOC_WARN=$((B_DOC_WARN + 1)) ;;
    fail) b_fail "$label${detail:+ — $detail}"; B_DOC_FAIL=$((B_DOC_FAIL + 1)) ;;
  esac
}

b_doc_kernel() {
  local kv
  kv="$(uname -r)"
  if [[ ! -d "/lib/modules/$kv" ]]; then
    b_doc_result fail "Kernel" "modules for $kv are missing"
    return
  fi
  if ((BANCHY_LIVE)); then
    b_doc_result ok "Kernel" "$kv (live)"
    return
  fi
  local vmlinuz
  if [[ "$kv" == *lts* ]]; then
    vmlinuz="/boot/vmlinuz-linux-lts"
  else
    vmlinuz="/boot/vmlinuz-linux"
  fi
  if [[ -f "$vmlinuz" ]]; then
    b_doc_result ok "Kernel" "$kv"
  else
    b_doc_result fail "Kernel" "$vmlinuz not found"
  fi
}

b_doc_initramfs() {
  if ((BANCHY_LIVE)); then
    b_doc_result ok "Initramfs" "provided by live image"
    return
  fi
  local kv img
  kv="$(uname -r)"
  if [[ "$kv" == *lts* ]]; then
    img="/boot/initramfs-linux-lts.img"
  else
    img="/boot/initramfs-linux.img"
  fi
  if [[ -f "$img" ]]; then
    b_doc_result ok "Initramfs" "$(basename "$img")"
  else
    b_doc_result fail "Initramfs" "$(basename "$img") missing"
  fi
}

b_doc_efi() {
  if [[ -d /sys/firmware/efi ]]; then
    b_doc_result ok "EFI" "UEFI firmware detected"
  else
    b_doc_result warn "EFI" "system booted in legacy BIOS mode"
  fi
}

b_doc_boot() {
  if ((BANCHY_LIVE)); then
    b_doc_result ok "Banchy Boot" "live image (bootloader provided by ISO)"
    return
  fi
  local out rc
  set +e
  out="$(b_boot_check 2>&1)"
  rc=$?
  set -e
  if ((rc == 0)); then
    b_doc_result ok "Banchy Boot"
  else
    b_doc_result fail "Banchy Boot" "$rc problem(s)"
    while IFS= read -r line; do
      printf '       %s\n' "$line"
    done <<<"$out"
  fi
}

b_doc_network() {
  if ! b_have nmcli; then
    b_doc_result warn "Network" "nmcli not available"
    return
  fi
  local state
  state="$(nmcli -t -g STATE general 2>/dev/null || echo unknown)"
  case "$state" in
    connected) b_doc_result ok "Network" "connected" ;;
    connecting) b_doc_result warn "Network" "connecting" ;;
    *) b_doc_result warn "Network" "not connected ($state)" ;;
  esac
}

b_doc_services() {
  if ! b_have systemctl; then
    b_doc_result warn "Services" "systemctl not available"
    return
  fi
  local failed
  failed="$(systemctl --failed --no-legend --no-pager 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
  if [[ -z "${failed// /}" ]]; then
    b_doc_result ok "Services" "no failed units"
    return
  fi
  if echo "$failed" | grep -Eq 'systemd-logind|dbus|network|getty'; then
    b_doc_result fail "Services" "critical units failed: $failed"
  else
    b_doc_result warn "Services" "failed units: $failed"
  fi
}

b_doc_disk() {
  local root_pct
  root_pct="$(df -P / | awk 'NR==2 { gsub("%","",$5); print $5 }')"
  if [[ -n "$root_pct" ]]; then
    if ((root_pct >= 95)); then
      b_doc_result fail "Disk space" "/ is ${root_pct}% full"
    elif ((root_pct >= 90)); then
      b_doc_result warn "Disk space" "/ is ${root_pct}% full"
    else
      b_doc_result ok "Disk space" "/ at ${root_pct}%"
    fi
  fi
  if ((BANCHY_LIVE)); then
    return
  fi
  if findmnt -rn -T /boot >/dev/null 2>&1; then
    local esp_mb
    esp_mb="$(df -Pm /boot | awk 'NR==2 {print $4}')"
    if [[ -n "$esp_mb" ]]; then
      if ((esp_mb < 20)); then
        b_doc_result fail "ESP space" "/boot has only ${esp_mb} MB free"
      elif ((esp_mb < 50)); then
        b_doc_result warn "ESP space" "/boot has ${esp_mb} MB free"
      else
        b_doc_result ok "ESP space" "${esp_mb} MB free"
      fi
    fi
  fi
}

b_doc_pacman() {
  if ! b_have pacman; then
    b_doc_result warn "Package database" "pacman not available"
    return
  fi
  local out orphans
  out="$(pacman -Dk 2>&1 || true)"
  if [[ -n "$out" ]]; then
    b_doc_result warn "Package database" "$(echo "$out" | head -1)"
  else
    b_doc_result ok "Package database"
  fi
  orphans="$(pacman -Qtdq 2>/dev/null | wc -l)"
  if ((orphans > 0)); then
    b_doc_result warn "Orphan packages" "$orphans orphan(s) — run 'pacman -Rns \$(pacman -Qtdq)' to remove"
  fi
}

b_doc_banchy_config() {
  local rc=0
  set +e
  b_settings_load && \
    b_theme_validate "${B_SET[theme]:-}" 2>/dev/null && \
    b_apply --check >/dev/null 2>&1
  rc=$?
  set -e
  if ((rc == 0)); then
    b_doc_result ok "Banchy configuration"
  else
    b_doc_result fail "Banchy configuration" "run 'banchy config check' for details"
  fi
}

b_doc_hyprland() {
  local xdg="${XDG_CONFIG_HOME:-$HOME/.config}"
  local hc="$xdg/hypr/hyprland.conf"
  if [[ ! -f "$hc" ]]; then
    b_doc_result warn "Hyprland configuration" "not found at $hc"
    return
  fi
  local opens closes
  opens="$(grep -o '{' "$hc" 2>/dev/null | wc -l)"
  closes="$(grep -o '}' "$hc" 2>/dev/null | wc -l)"
  if [[ "$opens" != "$closes" ]]; then
    b_doc_result fail "Hyprland configuration" "unbalanced braces"
    return
  fi
  if b_have hyprctl && hyprctl version >/dev/null 2>&1; then
    b_doc_result ok "Hyprland" "$(hyprctl version 2>/dev/null | head -1)"
  else
    b_doc_result ok "Hyprland configuration" "static check (compositor not running)"
  fi
}

b_doc_time() {
  if ! b_have timedatectl; then
    b_doc_result warn "Time synchronisation" "timedatectl not available"
    return
  fi
  local sync
  sync="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)"
  if [[ "$sync" == "yes" ]]; then
    b_doc_result ok "Time synchronisation"
  else
    b_doc_result warn "Time synchronisation" "NTP not synchronised yet"
  fi
}

b_doc_components() {
  local missing=""
  local p
  for p in "$BANCHY_SHARE/templates/manifest" \
           "$BANCHY_SHARE/defaults/banchy/settings.conf" \
           "$BANCHY_SHARE/themes" \
           "$BANCHY_SHARE/packages/profiles"; do
    [[ -e "$p" ]] || missing+="$p "
  done
  if [[ -n "$missing" ]]; then
    b_doc_result fail "Banchy components" "missing: $missing"
  else
    b_doc_result ok "Banchy components" "v${BANCHY_VERSION:-0.2.0}"
  fi
}

b_doc_journal() {
  local count
  count="$(journalctl -b -p err -n 100 --no-pager 2>/dev/null | wc -l)"
  if ((count <= 1)); then
    b_doc_result ok "Journal" "no errors this boot"
  else
    b_doc_result warn "Journal" "$count error line(s) — journalctl -b -p err"
  fi
}

banchy_cmd_doctor() {
  local filter="${1:-all}"
  B_DOC_OK=0 B_DOC_WARN=0 B_DOC_FAIL=0

  b_header "Banchy OS health check"

  local -a checks=()
  case "$filter" in
    all) checks=(kernel initramfs efi boot network services disk pacman hyprland config components time journal) ;;
    quick) checks=(network services disk time) ;;
    *) b_err "usage: banchy doctor [all|quick]"; return 2 ;;
  esac

  local c
  for c in "${checks[@]}"; do
    "b_doc_$c" || true
  done

  b_header "Summary"
  printf '  %s%d ok%s  %s%d warnings%s  %s%d failed%s\n' \
    "$C_GREEN" "$B_DOC_OK" "$C_RESET" \
    "$C_YELLOW" "$B_DOC_WARN" "$C_RESET" \
    "$C_RED" "$B_DOC_FAIL" "$C_RESET"

  if ((B_DOC_FAIL > 0)); then
    return 1
  fi
  return 0
}
