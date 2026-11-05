#!/bin/bash
# export-ui.sh - capture this machine's XFCE look into ./bundle
#
# Run on the machine that already looks the way you want.
# Safe to run inside a desktop session (it only reads your settings).
#
# Captures: XFCE settings (panel layout, shortcuts, Whisker menu, session,
# appearance), GTK settings, autostart entries, and any wallpaper or other
# file in your home folder that the settings point to.
# Skips per-machine settings (monitor layout, power management). Themes and
# icons come from packages (see kit.conf), so the repo stays small.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE="$KIT_DIR/bundle"
STAGE="$BUNDLE/home"

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user, not with sudo." >&2
  exit 1
fi

# Paths (relative to $HOME) to capture, if they exist
PATHS=(
  .config/xfce4
  .config/autostart
  .config/gtk-3.0
  .config/gtk-4.0
  .gtkrc-2.0
)

# Settings files that describe this specific machine, not the look
EXCLUDE=(
  .config/xfce4/xfconf/xfce-perchannel-xml/displays.xml
  .config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml
)

echo "==> Exporting UI from $HOME"
rm -rf "$BUNDLE"
mkdir -p "$STAGE"

copy_rel() {
  # copy a path relative to $HOME into the bundle, keeping its location
  local rel="$1"
  [ -e "$HOME/$rel" ] || return 0
  mkdir -p "$STAGE/$(dirname "$rel")"
  cp -a "$HOME/$rel" "$STAGE/$rel"
  echo "    + ~/$rel"
}

for p in "${PATHS[@]}"; do
  copy_rel "$p"
done

for e in "${EXCLUDE[@]}"; do
  rm -f "$STAGE/$e"
done

# Files in your home folder that the XFCE settings point to (wallpaper etc.)
XML_DIR="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
if [ -d "$XML_DIR" ]; then
  grep -rhoE "value=\"$HOME/[^\"]+\"" "$XML_DIR" 2>/dev/null \
    | sed -E 's/^value="//; s/"$//' | sort -u \
    | while IFS= read -r f; do
        if [ -f "$f" ]; then
          rel="${f#"$HOME"/}"
          [ -e "$STAGE/$rel" ] || copy_rel "$rel"
        fi
      done || true
fi

# Replace your home path with a placeholder so the bundle works for any user
grep -rIl --null -- "$HOME" "$BUNDLE" 2>/dev/null \
  | xargs -0 -r sed -i "s|$HOME|@@HOME@@|g" || true

{
  echo "exported_from=$(hostname)"
  echo "exported_by=$USER"
  echo "exported_at=$(date -Iseconds)"
  [ -r /etc/os-release ] && grep -E '^PRETTY_NAME=' /etc/os-release
} > "$BUNDLE/info.txt"

size="$(du -sh "$BUNDLE" | cut -f1)"
echo
echo "Done. Bundle saved to: $BUNDLE ($size)"
echo "Next: commit and push it so other machines can pull it:"
echo "    cd $KIT_DIR && git add bundle && git commit -m 'Update UI bundle' && git push"
