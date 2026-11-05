#!/bin/bash
# install-ui.sh - apply the kit's look to this machine
#
#   1. installs the packages in kit.conf (themes, icons, Plank, python3-astral)
#   2. restores the exported bundle/, if there is one
#   3. sets up the taskbar layout (top bar + dock) unless the bundle has one
#   4. installs desktop-style, which applies the themes at every login and
#      switches light/dark at sunrise/sunset
#
# Run it from a text console (Ctrl+Alt+F2 at the login screen) or SSH with
# no desktop logged in - XFCE would otherwise overwrite the new settings.
# (Exception: with --themes-only it can run inside the desktop.)
#
# Options:
#   --layout        apply the top bar + dock layout even if the bundle has a panel
#   --no-bundle     ignore bundle/ even if it exists
#   --themes-only   only packages + themes/light-dark; no bundle, no layout
#   --no-reboot     don't offer to reboot at the end

set -euo pipefail

KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE="$KIT_DIR/bundle"
XML_DIR="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
# shellcheck source=kit.conf
. "$KIT_DIR/kit.conf"

USE_BUNDLE=1
NO_REBOOT=0
FORCE_LAYOUT=0
THEMES_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --layout)      FORCE_LAYOUT=1 ;;
    --no-bundle)   USE_BUNDLE=0 ;;
    --themes-only) THEMES_ONLY=1; USE_BUNDLE=0 ;;
    --no-reboot)   NO_REBOOT=1 ;;
    -h|--help)     sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done
[ -d "$BUNDLE/home" ] || USE_BUNDLE=0

# Taskbar layout: the bundle's panel wins unless --layout is given
USE_LAYOUT=0
if [ $THEMES_ONLY -eq 0 ]; then
  if [ $FORCE_LAYOUT -eq 1 ]; then
    USE_LAYOUT=1
  elif [ "${PANEL_LAYOUT:-keep}" = topbar-dock ] && { [ $USE_BUNDLE -eq 0 ] ||
       [ ! -f "$BUNDLE/home/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" ]; }; then
    USE_LAYOUT=1
  fi
fi

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user, not with sudo." >&2
  exit 1
fi

IN_SESSION=0
pgrep -u "$USER" -x xfce4-session >/dev/null 2>&1 && IN_SESSION=1

if { [ $USE_BUNDLE -eq 1 ] || [ $USE_LAYOUT -eq 1 ]; } && [ $IN_SESSION -eq 1 ]; then
  cat >&2 <<'EOF'
A desktop session is running, and changing the panel/settings needs it closed.

  1. Log out of the desktop (and of any Guacamole/RDP session).
  2. At the login screen press Ctrl+Alt+F2 and log in (or connect over SSH).
  3. Run this script again.

(Or run with --themes-only to apply just the themes now.)
EOF
  exit 1
fi

echo "==> Installing packages"
pkgs="$PACKAGES"
[ "${THEME_MODE:-auto}" = auto ] && pkgs="$pkgs python3-astral"
[ "${DOCK_STYLE:-plank}" = plank ] && pkgs="$pkgs plank"
# shellcheck disable=SC2086
sudo apt-get install -y $pkgs

stamp="$(date +%Y%m%d-%H%M%S)"
if [ -d "$HOME/.config/xfce4" ]; then
  cp -a "$HOME/.config/xfce4" "$HOME/.config/xfce4.before-ui-kit-$stamp"
  echo "==> Current XFCE settings saved to ~/.config/xfce4.before-ui-kit-$stamp"
fi

if [ $USE_BUNDLE -eq 1 ] || [ $USE_LAYOUT -eq 1 ]; then
  pkill -u "$USER" -x xfconfd 2>/dev/null || true
  sleep 2
fi

if [ $USE_BUNDLE -eq 1 ]; then
  echo "==> Restoring settings from the bundle"
  OLD="$HOME/.config/xfce4.before-ui-kit-$stamp"
  rm -rf "$HOME/.config/xfce4"

  stage="$(mktemp -d)"
  trap 'rm -rf "$stage"' EXIT
  cp -a "$BUNDLE/home/." "$stage/"
  grep -rIl --null '@@HOME@@' "$stage" 2>/dev/null \
    | xargs -0 -r sed -i "s|@@HOME@@|$HOME|g" || true
  cp -a "$stage/." "$HOME/"

  # Keep this machine's own monitor layout and power settings
  for f in displays.xml xfce4-power-manager.xml; do
    if [ -f "$OLD/xfconf/xfce-perchannel-xml/$f" ]; then
      mkdir -p "$XML_DIR"
      cp -a "$OLD/xfconf/xfce-perchannel-xml/$f" "$XML_DIR/$f"
    fi
  done
  # Old saved sessions can bring back windows from before the restore
  rm -rf "$HOME/.cache/sessions"
fi

if [ $USE_LAYOUT -eq 1 ]; then
  echo "==> Setting up the taskbar: top bar + dock"
  TOPBAR_SIZE="${TOPBAR_SIZE:-}" TOPBAR_ICON_SIZE="${TOPBAR_ICON_SIZE:-}" DOCK_STYLE="${DOCK_STYLE:-}" DOCK_SIZE="${DOCK_SIZE:-}" DOCK_AUTOHIDE="${DOCK_AUTOHIDE:-}" \
  DOCK_APPS="${DOCK_APPS:-}" CLOCK_FORMAT="${CLOCK_FORMAT:-}" \
    "$KIT_DIR/extras/panel-layout"
  rm -rf "$HOME/.cache/sessions"
fi

echo "==> Installing desktop-style (themes, light/dark)"
mkdir -p "$HOME/.local/bin" "$HOME/.config/autostart"
install -m 755 "$KIT_DIR/extras/desktop-style" "$HOME/.local/bin/desktop-style"
# Solid light/dark Plank dock themes (desktop-style switches between them)
mkdir -p "$HOME/.local/share/plank/themes"
cp -r "$KIT_DIR/extras/plank-themes/." "$HOME/.local/share/plank/themes/"
{
  echo "# Written by mint-ui-kit install-ui.sh from kit.conf"
  for v in LIGHT_GTK DARK_GTK LIGHT_WM DARK_WM LIGHT_ICONS DARK_ICONS \
           THEME_MODE LATITUDE LONGITUDE DOCK_STYLE DOCK_SIZE DOCK_AUTOHIDE \
           DOCK_AUTOHIDE_REMOTE; do
    printf '%s="%s"\n' "$v" "${!v:-}"
  done
} > "$HOME/.config/desktop-style.conf"
cat > "$HOME/.config/autostart/desktop-style.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Desktop Style
Comment=Theme and light/dark switching (mint-ui-kit)
Exec=$HOME/.local/bin/desktop-style
X-GNOME-Autostart-enabled=true
EOF

if [ $IN_SESSION -eq 1 ]; then
  echo "==> Applying now"
  pkill -u "$USER" -f "$HOME/.local/bin/desktop-style" 2>/dev/null || true
  "$HOME/.local/bin/desktop-style" --once
  nohup "$HOME/.local/bin/desktop-style" >/dev/null 2>&1 &
fi

echo
if [ $USE_BUNDLE -eq 1 ] || [ $USE_LAYOUT -eq 1 ]; then
  echo "Done. Reboot, then log in at the machine first."
  echo "Once it looks right:  rm -rf ~/.config/xfce4.good && cp -r ~/.config/xfce4 ~/.config/xfce4.good"
  if [ $NO_REBOOT -eq 0 ]; then
    read -r -p "Reboot now? [y/N] " ans
    case "$ans" in [yY]*) sudo reboot ;; esac
  fi
elif [ $IN_SESSION -eq 1 ]; then
  echo "Done. The new look is applied."
else
  echo "Done. It applies at your next login."
fi
