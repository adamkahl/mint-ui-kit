# mint-ui-kit

A nicer, consistent Linux Mint XFCE desktop on every machine, built only from
maintained, packaged pieces, plus an optional remote desktop setup for
Guacamole.

**The look**
- **Themes:** Orchis (`orchis-gtk-theme` from the Ubuntu repos), switching
  light ↔ dark automatically at sunrise/sunset.
- **Icons:** Papirus (`papirus-icon-theme` from the Ubuntu repos).
- **Top bar:** a slim XFCE panel with the menu, tray, sound, notifications and
  clock, all icons the same size.
- **Dock:** Plank (`plank` from the Ubuntu repos), centered at the bottom with
  pinned apps and open windows, on a solid light/dark background. Right-click
  an open app → **Keep in Dock** to pin it; drag an icon off the dock to unpin
  it. (`DOCK_STYLE=panel` in `kit.conf` uses an XFCE panel dock instead.)
- **Every monitor:** with `DOCK_MONITORS=all` each monitor gets its own dock,
  added and removed automatically as you connect or disconnect screens. Pins
  are shared, so pinning on one screen pins everywhere. Every dock shows all
  open apps (Plank can't split them by screen).
- **Remote desktop:** the dock never auto-hides over xrdp
  (`DOCK_AUTOHIDE_REMOTE`), since the screen edge is hard to reach there.

| File | What it does |
|---|---|
| `kit.conf` | The settings: themes, light/dark mode, dock apps, sizes |
| `install-ui.sh` | Applies the look to a machine |
| `export-ui.sh` | Saves a machine's exact XFCE settings into `bundle/` (optional) |
| `setup-xrdp.sh` | xrdp + Guacamole remote desktop setup (optional) |
| `extras/desktop-style` | Applies the themes and dock settings at login and switches light/dark |
| `extras/panel-layout` | Builds the top bar + dock |
| `extras/plank-themes/` | The solid light/dark dock themes |
| `extras/dock-monitors` | Keeps a dock on every monitor as monitors come and go |

## Set up a machine

Log out of the desktop (and any Guacamole session). At the login screen press
**Ctrl+Alt+F2** and log in, or connect over SSH. Then:

```bash
sudo apt install -y git
git clone https://github.com/adamkahl/mint-ui-kit.git ~/mint-ui-kit
cd ~/mint-ui-kit
./install-ui.sh
```

Reboot when it asks, and log in at the machine first. Your previous
settings are kept in `~/.config/xfce4.before-ui-kit-<date>`.

Once it looks right, make a recovery copy:

```bash
rm -rf ~/.config/xfce4.good && cp -r ~/.config/xfce4 ~/.config/xfce4.good
```

## Change the look

Edit `kit.conf`, commit and push. Then on each machine:

```bash
cd ~/mint-ui-kit && git pull
./install-ui.sh --themes-only   # themes / light-dark only, works inside the desktop
./install-ui.sh --layout        # also rebuild the top bar + dock (from Ctrl+Alt+F2)
```

Themes are re-applied at every login, so pick themes in `kit.conf` rather than
in Settings → Appearance. Panel changes you make by hand stay until you
rebuild the layout.

## Copy one machine's exact setup (optional)

If you've customized a machine by hand (panel, shortcuts, wallpaper) and want
other machines to match it exactly:

```bash
cd ~/mint-ui-kit
./export-ui.sh
git add bundle && git commit -m "Update UI bundle" && git push
```

`install-ui.sh` then restores that bundle on other machines, including its
panel. The bundle's panel wins over the kit's layout unless you pass
`--layout`. Monitor layout and power settings always stay per-machine.

## Remote desktop through Guacamole (optional)

```bash
./setup-xrdp.sh
sudo reboot
```

Run it **before** the first Guacamole connection to a new machine, because a
remote session started without it resets XFCE to stock. At the end it prints
the Guacamole connection settings: the main RDP connection, a **Reset**
connection that clears a stuck session, and an **SSH** rescue connection.

Day to day:
- **Coming back soon:** close the tab. The session waits for up to an hour.
- **Done:** Log Out from the menu, or the **End Session** launcher.

## If the desktop resets to stock XFCE

1. Log out everywhere, press **Ctrl+Alt+F2**, log in.
2. Run:
   ```bash
   pkill -u "$USER" xfconfd; sleep 2
   mv ~/.config/xfce4 ~/.config/xfce4.broken
   cp -r ~/.config/xfce4.good ~/.config/xfce4
   sudo reboot
   ```

Or simply re-run `./install-ui.sh`.

## Notes

- Target: Linux Mint 22.x XFCE.
- Light/dark switching uses `python3-astral` (sun position); the coordinates are in `kit.conf`.
- `bundle/` holds your XFCE settings and any wallpaper they point to, so keep
  the repo private.
