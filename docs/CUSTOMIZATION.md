# Customization

Everything in Banchy OS is customizable through the `banchy` CLI, the
`banchy-settings` GUI, or both — the GUI simply calls the same commands, so
validation is always enforced.

## Settings keys

Set with `banchy set <key> <value>`, read with `banchy get <key>`. Every value
is validated; invalid values are rejected with `[FAIL]`.

| Key | Allowed values | Notes |
| --- | --- | --- |
| `theme` | theme name | e.g. `midnight`, `black`, `frost`, `neon`, `minimal` |
| `mode` | `dark` \| `light` | Theme engine mode |
| `accent` | `#RRGGBB` | Accent color override |
| `transparency` | `0` – `0.6` | Window transparency |
| `blur` | `on` \| `off` | Background blur |
| `border_size` | `0` – `8` | Window border width |
| `border_radius` | `0` – `20` | Corner radius |
| `gaps_in` | `0` – `30` | Inner gaps |
| `gaps_out` | `0` – `40` | Outer gaps |
| `animations` | `on` \| `off` | Enable animations |
| `anim_speed` | `0.1` – `3.0` | Animation speed multiplier |
| `font` | font name | UI font |
| `font_size` | `8` – `32` | UI font size |
| `terminal_font` | font name | kitty font |
| `cursor_size` | `16` – `48` | Cursor size in pixels |
| `waybar_position` | `top` \| `bottom` | Bar position |
| `waybar_height` | `24` – `64` | Bar height in pixels |
| `wallpaper` | existing image path | Must point to an existing file |
| `night_location` | location string | Night light / night mode location |

Apply changes:

```bash
banchy set accent '#88C0D0'
banchy set gaps_out 12
banchy apply
```

`banchy apply` re-runs the render pipeline (below). Settings live in
`settings.conf` and are merged with the active theme.

## Theme Engine

### Bundled themes

| Theme | Display name | Accent |
| --- | --- | --- |
| `midnight` | Banchy Midnight | `#6C8CFF` (default) |
| `black` | Banchy Black | `#E2E8F0` |
| `frost` | Banchy Frost | `#88C0D0` |
| `neon` | Banchy Neon | `#3DFF9E` |
| `minimal` | Banchy Minimal | `#A3A3A3` |

```bash
banchy theme list
banchy theme set frost
banchy theme validate frost
banchy apply
```

### Theme definition

System themes live in `/usr/share/banchy/themes/<name>/theme.conf`
(user-created themes in `~/.config/banchy/themes/<name>/`). `theme.conf` is
plain `KEY=VALUE`. Format example — the keys below are the defined set; palette
values shown are illustrative (the shipped values live in
`themes/<name>/theme.conf`):

```
NAME=midnight
DISPLAY_NAME=Banchy Midnight
MODE=dark
BG=#0B0D12
SURFACE=#141822
SURFACE_ALT=#1B2130
TEXT=#E6E9F2
TEXT_DIM=#8B93A7
ACCENT=#6C8CFF
ACCENT_ALT=#9AAEFF
BORDER_ACTIVE=#6C8CFF
BORDER_INACTIVE=#2A3142
DANGER=#FF5C77
WARNING=#E5C07B
SUCCESS=#3DFF9E
WALLPAPER=/usr/share/banchy/wallpapers/midnight.png
```

Light-mode variants of the same keys are supported when `MODE=light`.
Create your own:

```bash
banchy theme create mytheme
```

### Render pipeline

```
settings.conf + theme.conf  →  merge  →  templates/*.tmpl  →  staged output
   →  validate  →  atomic swap  →  verify (hyprctl)  →  or rollback
```

1. **Merge** `settings.conf` and the active `theme.conf` into one context.
2. **Render** `themes/templates/*.tmpl` files (`{{KEY}}` placeholders) into:
   - Hyprland `dynamic.conf`
   - Waybar `style.css`
   - kitty colors include
   - fuzzel ini
   - mako config
   - hyprlock config
   - hyprpaper config
   - GTK CSS
   - `theme.env`
3. **Stage** — output goes to a staging location first, never over live files.
4. **Validate** — fail on any unresolved `{{...}}` placeholder or invalid hex
   color.
5. **Atomic swap** — staged files replace the live ones in one step.
6. **Verify** — if Hyprland is running, confirm via `hyprctl getoption`.
7. **Rollback** — on failure, restore the last good state and show the error.

Generated files are never edited by hand — change the template or the theme
instead.

### Managed file markers

Files produced by the pipeline carry a **marker comment**. The engine refreshes
untouched managed files automatically; a file you edited yourself is **never
overwritten unless you pass `--force`**.

## banchy-settings (GUI)

`banchy-settings` is a Python + GTK4 (PyGObject) application:

| Page | Controls |
| --- | --- |
| Appearance | Theme, mode, accent, transparency, blur, borders, gaps, animations |
| Wallpapers | Pick a wallpaper from the shipped set |
| Waybar | Position, height |
| Fonts | Font, font size, terminal font, cursor size |
| Monitors | Display configuration |
| About | Version and project information |

Every change goes through `banchy set` and then `banchy apply`, so the CLI
validation rules above always apply.

## Config management

System defaults: `/usr/share/banchy/defaults/`. User configs: `~/.config/`
(never overwritten needlessly).

```bash
banchy config backup     # tar → ~/.local/share/banchy/backups/<timestamp>.tar
banchy config restore    # list backups, restore one
banchy config diff       # show drift from defaults
banchy config check      # quick health check
banchy config validate   # deep validation
banchy reset hyprland    # reset the Hyprland configuration
```

## Keybindings

| Keys | Action |
| --- | --- |
| `SUPER+Return` | Terminal (kitty) |
| `SUPER+Space` | Launcher (fuzzel) |
| `SUPER+E` | Files (thunar) |
| `SUPER+B` | Chromium |
| `SUPER+C` | Visual Studio Code |
| `SUPER+O` | Obsidian |
| `SUPER+Q` | Close window |
| `SUPER+1..9` | Switch workspace |
| `SUPER+Shift+1..9` | Move window to workspace |
| `SUPER+Shift+S` | Screenshot region |
| `SUPER+Ctrl+R` | Reload Hyprland |
| `SUPER+L` | Lock |
| `SUPER+N` | Control center (banchy-cc) |
| `SUPER+P` | Settings |
| `SUPER+K` | Show keybindings |
| `SUPER+V` | Toggle floating |
| `SUPER+F` | Fullscreen |
| `SUPER+Shift+X` | Power menu |

Mouse bindings are configured too. Print the full list on a live system:

```bash
banchy keys
```

## Control center

`banchy-cc` (`SUPER+N`) provides quick toggles: Wi-Fi, Bluetooth, volume, mic,
brightness, power profile, night mode, screenshot, screen recording
(wf-recorder), VPN, and logout/reboot/shutdown.

## Profiles

Change the installed package set at any time:

```bash
banchy profile developer
```

Profiles: `minimal`, `default`, `developer`, `creator`, `gaming`, `full` —
see [INSTALLATION.md](INSTALLATION.md).
