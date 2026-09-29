#!/usr/bin/env bash
# shellcheck disable=SC2034
#
# Banchy OS archiso profile definition.
# Key set mirrors the official archiso releng profile:
# https://raw.githubusercontent.com/archlinux/archiso/master/configs/releng/profiledef.sh

# --- iso_version: read the repository version file, fall back to 0.1.0 -------
# mkarchiso sources this file after cd'ing into the profile directory, so both
# the path derived from BASH_SOURCE and the cwd-relative path are tried.
_banchy_version=""
_banchy_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  _banchy_dir="$(dirname -- "${BASH_SOURCE[0]}")"
fi
for _banchy_version_file in "${_banchy_dir:+${_banchy_dir}/../../version}" "../../version"; do
  [[ -n "${_banchy_version_file}" && -r "${_banchy_version_file}" ]] || continue
  _banchy_version="$(tr -d '[:space:]' <"${_banchy_version_file}")" || _banchy_version=""
  break
done
[[ "${_banchy_version}" =~ ^[0-9A-Za-z.+-]+$ ]] || _banchy_version="0.1.0"
unset _banchy_dir _banchy_version_file

# --- profile (releng key set) ------------------------------------------------
iso_name="banchy-os"
iso_label="BANCHY_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Banchy OS"
iso_application="Banchy OS Live/Install DVD"
iso_version="${_banchy_version}"
unset _banchy_version

install_dir="banchy"
arch="x86_64"
bootmodes=('uefi.systemd-boot')
pacman_conf="pacman.conf"

airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86,arm64' '-b' '1M' '-Xdict-size' '1M')

# Declared -g so the file is valid both when sourced at top level and when
# mkarchiso sources it from inside _read_profile() (releng relies on mkarchiso's
# own `declare -A file_permissions=()`; -g keeps the global binding either way).
declare -gA file_permissions=(
  ["/etc/sudoers.d/wheel"]="0:0:440"
  ["/usr/local/bin/banchy-live-setup.sh"]="0:0:755"
  ["/usr/local/bin/banchy-smoke.sh"]="0:0:755"
)
