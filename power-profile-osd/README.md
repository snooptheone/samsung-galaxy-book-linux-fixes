# Power profile OSD (systemd user service)

Shows an on-screen notice ("Performance Mode", "Power Saver Mode", "Balanced
Mode") whenever the power profile changes, including changes made by a hardware
key such as Fn+F11 on the Galaxy Book4 Ultra, which KDE does not announce by
itself.

Nothing in it is Samsung-specific: it works on any system running
`power-profiles-daemon` (or `tuned-ppd`). It replaces the older `kde-power-osd`
system service (the `kdeosd-fix` of other Galaxy Book repos) with a service
that runs as **your user**, with no root, no `sudo` and no `loginctl`.

## Quick Install

Run it as your normal user, **not** with `sudo` (everything goes under `$HOME`):

```bash
cd power-profile-osd
./install.sh
```

To uninstall: `./uninstall.sh`.

The installer puts the script in `~/.local/bin/power-profile-osd` and the unit in
`~/.config/systemd/user/power-profile-osd.service`, then enables and restarts it.

## How it works

1. `gdbus monitor --system --dest net.hadess.PowerProfiles` listens to the
   daemon. Any user can read those signals.
2. On each `ActiveProfile` change it reads the profile with `busctl`.
3. It shows the notice through KDE's OSD
   (`org.kde.plasmashell /org/kde/osdService showText`), using the first of
   `qdbus-qt6`, `qdbus6`, `qdbus`. If KDE or the call is not available it falls
   back to `notify-send`, so other desktops get a regular notification.
4. If the monitor ever ends (daemon gone, bus error) the script exits with an
   error and systemd restarts it after 5 s.

The unit starts with the graphical session, after `plasma-plasmashell.service`.

## Replacing the old `kde-power-osd`

If the old system service is installed, `install.sh` prints the commands to
remove it. It does not run them: that needs root. With both active you get the
same notice twice (KDE shows one at a time, so one replaces the other).

## What was verified

- `tests/test-osd.sh` checks the profile → icon/text map and the whole pipeline
  with fake `gdbus`, `busctl`, `qdbus` and `notify-send`, including the
  `notify-send` fallback and the non-zero exit when the monitor ends.
- On a Galaxy Book4 Ultra (CachyOS, Plasma 6.7, power-profiles-daemon 0.30), a
  throwaway user-level version of the same loop, run without root, received
  exactly one signal per Fn+F11 press and showed the notice, with the old
  system service stopped.

**Not verified yet:** starting by itself at login from the real unit,
restarting after a crash, and what happens when `power-profiles-daemon` itself
restarts (`gdbus monitor` may not follow the new bus owner).

## Requirements

`gdbus` (glib2), `busctl` (systemd), `systemctl --user`, and `qdbus6` or
`notify-send`. On Arch: `glib2` and `qt6-tools` are normally already present.
