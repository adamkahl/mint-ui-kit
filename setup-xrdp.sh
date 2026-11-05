#!/bin/bash
# setup-xrdp.sh - remote desktop for Guacamole (Linux Mint XFCE)
#
# Sets up xrdp so that:
#   * connecting remotely logs out the local session and takes over
#   * logging in at the machine closes any remote session
#   * the remote session loads Mint's settings (no stock-XFCE reset)
#   * disconnected sessions end on their own after DISCONNECT_LIMIT seconds
#   * an "End Session" launcher and a dialog-free Log Out avoid the logout
#     dialog that freezes over RDP
#   * SSH is enabled as a rescue route
#
# Run as your normal user (it uses sudo). Reboot afterwards.
# Running it again is safe.

set -euo pipefail

DISCONNECT_LIMIT="${DISCONNECT_LIMIT:-3600}"

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user, not with sudo." >&2
  exit 1
fi

echo "==> Installing xrdp and SSH"
sudo apt-get install -y xrdp openssh-server
sudo adduser xrdp ssl-cert >/dev/null
rm -f "$HOME/.xsession"

echo "==> Writing /etc/xrdp/startwm.sh"
[ -f /etc/xrdp/startwm.sh.orig ] || sudo cp /etc/xrdp/startwm.sh /etc/xrdp/startwm.sh.orig
sudo tee /etc/xrdp/startwm.sh >/dev/null <<'EOF'
#!/bin/sh
# xrdp session start (mint-ui-kit): log out any local console session, then
# start XFCE the same way LightDM does locally (including Mint's defaults)

if test -r /etc/profile; then . /etc/profile; fi
if test -r ~/.profile; then . ~/.profile; fi

for s in $(loginctl show-user "$USER" -p Sessions --value 2>/dev/null); do
  if [ "$(loginctl show-session "$s" -p Seat --value 2>/dev/null)" = "seat0" ]; then
    loginctl terminate-session "$s"
  fi
done
sleep 2

export DESKTOP_SESSION=xfce
export XDG_SESSION_DESKTOP=xfce
export XDG_CURRENT_DESKTOP=XFCE
export XDG_CONFIG_DIRS=/etc/xdg/xdg-xfce:/etc/xdg
unset DBUS_SESSION_BUS_ADDRESS

exec /etc/X11/Xsession startxfce4
EOF
sudo chmod +x /etc/xrdp/startwm.sh

echo "==> Making a local login close any remote session"
sudo tee /usr/local/bin/kill-xrdp-sessions >/dev/null <<'EOF'
#!/bin/sh
# Ends the user's xrdp sessions. Run by LightDM (as root) before a local
# session starts; also usable by hand or as a Guacamole "initial program".
[ -n "$USER" ] || exit 0
for s in $(loginctl show-user "$USER" -p Sessions --value 2>/dev/null); do
  if [ "$(loginctl show-session "$s" -p Service --value 2>/dev/null)" = "xrdp-sesman" ]; then
    loginctl terminate-session "$s"
  fi
done
sleep 2
exit 0
EOF
sudo chmod +x /usr/local/bin/kill-xrdp-sessions
sudo mkdir -p /etc/lightdm/lightdm.conf.d
printf '[Seat:*]\nsession-setup-script=/usr/local/bin/kill-xrdp-sessions\n' \
  | sudo tee /etc/lightdm/lightdm.conf.d/50-kill-xrdp.conf >/dev/null

echo "==> Ending disconnected sessions after $DISCONNECT_LIMIT seconds"
set_sesman() {
  # set_sesman KEY VALUE: set KEY under [Sessions] in sesman.ini
  local key="$1" val="$2" ini=/etc/xrdp/sesman.ini
  if sudo grep -qE "^[#;]?\s*$key=" "$ini"; then
    sudo sed -i -E "s|^[#;]?\s*$key=.*|$key=$val|" "$ini"
  else
    sudo sed -i "/^\[Sessions\]/a $key=$val" "$ini"
  fi
}
set_sesman KillDisconnected true
set_sesman DisconnectedTimeLimit "$DISCONNECT_LIMIT"

echo "==> Adding the End Session launcher"
sudo tee /usr/local/bin/end-session >/dev/null <<'EOF'
#!/bin/sh
# End the current session immediately (no logout dialog)
loginctl terminate-session "${XDG_SESSION_ID:-self}"
EOF
sudo chmod +x /usr/local/bin/end-session
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/end-session.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=End Session
Comment=End this session right away (closes apps without asking)
Exec=/usr/local/bin/end-session
Icon=system-log-out
EOF

echo "==> Making the menu's Log Out skip the dialog"
shopt -s nullglob
for rc in "$HOME"/.config/xfce4/panel/whiskermenu-*.rc; do
  sed -i -E 's|^command-logout=xfce4-session-logout$|command-logout=xfce4-session-logout --logout|' "$rc"
done
shopt -u nullglob

echo "==> Turning off 'save session on logout'"
xfconf-query -c xfce4-session -p /general/SaveOnExit -n -t bool -s false 2>/dev/null \
  || echo "    (couldn't set it now; turn off Settings -> Session and Startup -> 'Automatically save session on logout')"

echo "==> Enabling services"
sudo systemctl enable --now xrdp >/dev/null
sudo systemctl enable --now ssh.socket >/dev/null 2>&1 || sudo systemctl enable --now ssh >/dev/null

ip="$(hostname -I | awk '{print $1}')"
cat <<EOF

Done. Reboot to apply everything:  sudo reboot

Guacamole connections for this machine ($ip):
  Bench PC          RDP  $ip:3389  your Mint login, security "TLS",
                    ignore certificate, 24-bit color, fixed width/height,
                    resize method blank, no concurrency limits
  Bench PC - Reset  clone of the above with color depth 16-bit and
                    initial program /usr/local/bin/kill-xrdp-sessions
  Bench PC - SSH    SSH  $ip:22  your Mint login
EOF
