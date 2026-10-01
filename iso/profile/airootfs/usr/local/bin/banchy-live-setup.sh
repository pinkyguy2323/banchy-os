#!/usr/bin/env bash
# Banchy OS live session setup — run once by banchy-live-setup.service,
# before getty@tty1 / serial-getty@ttyS0 start (no static passwd/shadow
# files in the airootfs: the live user is created here at first boot).
set -euo pipefail

# Live user (idempotent).
if ! id -u banchy >/dev/null 2>&1; then
  useradd -m -G wheel -s /bin/bash banchy
  echo 'banchy:banchy' | chpasswd
fi

# Live root password (kept in sync every boot — documented in docs/BOOT.md
# style "predictable live credentials" and required by the recovery flow).
echo 'root:banchy' | chpasswd

# Make sure the locale listed in /etc/locale.gen actually exists.
if command -v locale-gen >/dev/null 2>&1; then
  locale-gen >/dev/null 2>&1 || true
fi

# Graphical login: SDDM autologins the live user straight into Hyprland
# (written before display-manager.service starts - see the unit ordering).
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/autologin.conf <<'EOF'
[Autologin]
User=banchy
Session=hyprland.desktop
EOF

echo BANCHY_LIVE_SETUP_OK > /dev/console 2>/dev/null || true
