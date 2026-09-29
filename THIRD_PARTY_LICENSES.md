# Third-party licenses

Banchy OS (this repository) is MIT licensed — see [LICENSE](LICENSE). It
nonetheless ships with, depends on, or is built on numerous third-party
components. Their licenses are reproduced by their respective upstream
projects and package maintainers.

**The table below is a summary. Licenses are as provided upstream; consult the
package (or its source) for the authoritative text.** On an installed system,
package licenses are available under `/usr/share/licenses/<package>/`.

| Component | Project | License | Usage |
| --- | --- | --- | --- |
| Omarchy | https://github.com/omacom/omarchy | MIT (© David Heinemeier Hansson) | Architectural inspiration only (installer-based Hyprland desktop concept, theme-driven configuration). No Omarchy code copied — see [NOTICE](NOTICE). |
| Arch Linux, pacman | https://archlinux.org | Various (GPL, GPL-compatible, public domain) | Base distribution, package manager, package metadata, userland. |
| archiso | https://gitlab.archlinux.org/archlinux/archiso | GPLv2 | ISO profile format (`profiledef.sh`, `airootfs`, `efiboot`) and mkinitcpio archiso hooks used by `iso/`. |
| Hyprland | https://hyprland.org | MIT | Default compositor / window manager. |
| Waybar | https://Alexays/Waybar | MIT | Status bar. |
| fuzzel | fuzzel (see package) | MIT | Application launcher. |
| kitty | https://kitty.codes | MPL-2.0 | Default terminal emulator. |
| mako | https://github.com/emersion/mako | MIT | Notification daemon. |
| hyprpaper, hyprlock, hypridle, hyprpicker | https://github.com/hyprwm | MIT | Wallpaper, lock screen, idle daemon, color picker. |
| Thunar | https://gitlab.xfce.org/xfce/thunar | GPL-2.0 | File manager. |
| GTK | https://www.gtk.org | LGPL-2.1+ | UI toolkit for banchy-settings and banchy-cc. |
| Python | https://www.python.org | PSF-2.0 | Runtime for banchy-settings and other tooling. |
| Neovim | https://neovim.io | Apache-2.0 | CLI text editor. |
| Visual Studio Code | https://code.visualstudio.com | MIT (application); proprietary marketplace | Default code editor. The Open VSX/marketplace terms are proprietary and separate from the MIT application license. |
| Chromium | https://www.chromium.org | BSD-3-Clause style (BSD) | Default web browser. |
| Obsidian | https://obsidian.md | Proprietary (free-of-charge app) | Default note-taking app; not open source. |
| wl-clipboard | https://github.com/bugaevc/wl-clipboard | MIT | Clipboard utilities (`wl-copy`/`wl-paste`). |
| cliphist | cliphist (see package) | MIT — see upstream | Clipboard history. |
| grim, slurp | https://emersion.github.io/grim, https://emersion.github.io/slurp | MIT | Screenshot region and output capture. |
| zathura | https://pwmt.org/projects/zathura | Zlib | PDF/document viewer. |
| imv | imv (see package) | MIT/ISC — see upstream | Image viewer. |
| fastfetch | https://github.com/fastfetch-cli/fastfetch | MIT | System info shown on terminal open. |
| btop | https://github.com/aristocratos/btop | Apache-2.0 | System monitor. |
| PipeWire | https://pipewire.org | MIT | Audio (and video) stack. |
| systemd, systemd-boot | https://systemd.io | LGPL-2.1+ | Init system, service manager, and the Banchy Boot bootloader. |
| NetworkManager | https://networkmanager.dev | GPL-2.0+ | Network management (used by installer, first-run, and recovery flows). |
| wf-recorder | wf-recorder (see package) | GPL-3.0 | Screen recording from banchy-cc; consult the package for the authoritative license. |

Notes:

- **Omarchy** is used for ideas only. Banchy OS is an independent distribution,
  not a fork, reskin, or derivative work of Omarchy. See
  [NOTICE](NOTICE) and [docs/DIFFERENCES_FROM_OMARCHY.md](docs/DIFFERENCES_FROM_OMARCHY.md).
- **Arch Linux** trademarks belong to their owners; Banchy OS is not endorsed
  by the Arch Linux project.
- Packages pulled in by profiles (`packages/profiles/*.list`) remain under the
  licenses declared by their upstream packages, including optional software
  such as Docker, OBS Studio, Blender, GIMP, Kdenlive, Steam, gamescope,
  mangohud, and gamemode.
- Where a component is used "as-is" from the distribution repositories, this
  project does not redistribute its source; the installed package and
  `/usr/share/licenses/` are authoritative.
