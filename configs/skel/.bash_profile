# Banchy OS login shell.
# Starts Hyprland on tty1; every other tty stays a plain shell.

if [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi

if [ "$(tty)" = "/dev/tty1" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
  if command -v Hyprland >/dev/null 2>&1; then
    exec Hyprland
  fi
fi
