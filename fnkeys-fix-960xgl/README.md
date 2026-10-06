# Galaxy Book4 Ultra (NP960XGL) — Fn+Esc fix

Makes the **Fn+Esc** key (the one with the headset icon, the Samsung support key)
do something on Linux. Without a fix the key is dead and the kernel logs
`samsung-galaxybook SAM0430:00: unknown ACPI notification event: 0x41`.

Only for the **Galaxy Book4 Ultra NP960XGL** (DMI `product_name` = `960XGL`).
The installer refuses to run on anything else. It was written and tested on
CachyOS, kernel 7.2.9, Secure Boot on.

## Quick Install

```bash
cd fnkeys-fix-960xgl
sudo ./install.sh                       # variant A (default), no reboot
sudo ./install.sh --action 'wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle'
sudo ./install.sh --dkms --remove-fork  # variant B, then reboot
```

To uninstall: `sudo ./uninstall.sh` (removes whichever variant is installed).

## Pick a variant

| | **A: userspace** (default) | **B: DKMS** |
|---|---|---|
| What changes | nothing in the kernel | one `case` in the driver |
| How Fn+Esc acts | an `acpid` rule runs a command of your choice | the driver reports `KEY_PROG2`; bind it in your desktop |
| Needs | `acpid` | `dkms` + kernel headers |
| Newer kernels | never breaks | only built on the `7.2.x` series; elsewhere DKMS skips the build and the in-tree driver stays (you only lose Fn+Esc) |
| Secure Boot | not involved | DKMS signs the module with its own key |
| Reboot | no | yes |

Installing one variant removes the other. This matters: the driver forwards the
ACPI event to userspace even when it handles it, so with both active the action
would run twice.

### Variant A: the action

`/etc/samsung-galaxybook-960xgl/fnesc.conf` holds `FNESC_COMMAND`. It runs as the
user logged in on seat0, with `XDG_RUNTIME_DIR` and `DBUS_SESSION_BUS_ADDRESS`
set (so D-Bus and `systemctl --user` work). `WAYLAND_DISPLAY`/`DISPLAY` are **not**
set: to start a graphical app, start a user service instead. Empty = only a line
in the journal:

```bash
journalctl -t samsung-galaxybook-fnesc -n 3
```

### Variant B: `--remove-fork`

The module has the same name as the in-tree driver, so the
`samsung-galaxybook-book5pro` DKMS fork (from the `fnkeys-fix` of other
Galaxy Book repos) cannot coexist. `--dkms` stops with an error if it is
installed; `--remove-fork` removes it (DKMS package, source, monitor service,
`modules-load.d`). The fork is never touched unless you pass that flag.

After installing or uninstalling B, **reboot** instead of `rmmod`/`modprobe`:
reloading the module detaches `power-profiles-daemon` from the platform profile
and the KDE power-profile notification stops until the next boot.

## What was verified

- Fn+Esc reaches userspace as `samsung-galaxybook SAM0430:00 00000041 00000001`
  (`acpi_listen`).
- `tests/test-rule-match.sh` checks the rule against that line and against other
  events (`0x42`, `0x73`, `0x7d`, another device).
- The patched driver builds against `7.2.9-1-cachyos`.

**Not verified yet:** running the `acpid` action end to end, and loading the
patched driver. Fix them here when tested.

## Other keys on this model

With the in-tree driver F4 (display switch), F9 (keyboard backlight) and Fn+F11
(power profile) work; the camera block is Fn+F10 (`block_recording`). None of
them needs a patched driver.

## How the driver change was made

`dkms/samsung-galaxybook.c` is `drivers/platform/x86/samsung-galaxybook.c` from
Linux v7.2.9 plus: a `#define` for notify `0x41`, `KEY_PROG2` declared on the
existing input device, and a `case` that reports it. A header comment in the
file says so. Compare symbols and strings with the running module, not
`srcversion`: an in-tree and an out-of-tree build hash differently.

## Tested on

- Samsung Galaxy Book4 Ultra NP960XGL, BIOS P10ALX.470.260413.05, CachyOS,
  kernel 7.2.9-1-cachyos, Secure Boot enabled.
