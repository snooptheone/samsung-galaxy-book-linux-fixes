# Galaxy Book4 Ultra (NP960XGL) — Fingerprint fix

Makes the fingerprint reader of the **Galaxy Book4 Ultra NP960XGL** (EgisTec
`1c7a:05a1`, driver `egismoc`) keep the fingerprints you enroll.

Only for that model and sensor: the installer refuses anything else. It was
written and tested on CachyOS (kernel 7.2.9). Arch-based distros only.

## The problem

With the stock `libfprint` 1.94.100 the sensor is recognised, opens, and
`fprintd-enroll` goes through all stages and reports `enroll-completed`, but the
sensor **keeps no fingerprint**: reading its storage right after an enrollment
returns 0 prints (measured twice), so `fprintd-verify` answers `verify-no-match`
("Print was not found on the devices storage") and fprintd then deletes its own
now-orphan record.

The libfprint log of an enrollment shows the driver sending its last commands and
declaring success without checking the answers. The SDCP v2 branch of libfprint
([MR !547](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/547),
open when this was written) rewrites that step (`egismoc_enroll_commit`, an
enrollment nonce, an application secret). The most likely reason is that this
firmware (`9050.1.2.33`) needs the SDCP enrollment; that is an inference, not
something the log proves.

## Quick Install

```bash
cd fingerprint-fix-960xgl
sudo ./install.sh                # builds, installs under /usr/local, checks it loaded
fprintd-enroll -f right-index-finger
fprintd-verify
```

To uninstall: `sudo ./uninstall.sh`.

Options: `--commit SHA` (another commit instead of the pinned `2d7c5277`),
`--system` (install into `/usr`, overwriting the package files), `--check-only`
(just check that this machine is supported).

## What it does

1. Checks DMI `product_name` = `960XGL` **and** the USB sensor `1c7a:05a1`.
2. Installs the build dependencies with `pacman`.
3. Fetches libfprint at the **pinned commit** `2d7c5277` (the head of
   `feature/sdcp-v2` when this was written), not "the branch".
4. Builds it with meson and installs it under `/usr/local`. The libfprint package
   files are **not touched**. For this prefix the udev rules/hwdb are disabled:
   meson would otherwise write them into the absolute `/usr/lib/udev`, over the
   package's files.
5. Adds a systemd drop-in, `fprintd.service.d/libfprint-sdcp.conf`, that sets
   `LD_LIBRARY_PATH` for **fprintd only**. Nothing else uses this library
   (`pam_fprintd` and `fprintd-enroll` talk to fprintd over D-Bus).
6. **Checks the result**: starts fprintd and reads `/proc/<pid>/maps` to see which
   libfprint it loaded, and that it exports SDCP symbols. If not, it removes the
   drop-in and stops.

Why a drop-in and not an `ld.so.conf.d` entry: on the test machine a copy in
`/usr/local/lib` **lost** to the one in `/usr/lib` for the same soname (checked
with `ldd` on another library installed that way), so a plain `ld.so` entry would
be ignored.

## What it never does

It never deletes anything from `/var/lib/fprint` nor from the sensor. The older
`fingerprint-fix` of other Galaxy Book repos runs `rm -rf /var/lib/fprint/*` to
work around a crash; here you get the safe recipe instead (see below).

## Known problem: fprintd crashes on an old print file

A print file written by one libfprint can crash fprintd when another one reads it:
`g_object_set: assertion 'G_IS_OBJECT (object)' failed`, right after
`file_storage_discover_prints() ... /var/lib/fprint/<user>/egismoc/<id>`, with
`ListEnrolledFingers failed: ... Remote peer disconnected`. **Move** the file
aside, do not delete it:

```bash
sudo mv /var/lib/fprint/<user>/egismoc/<id>/<finger-number> /var/lib/fprint/<user>/old-print
```

## Is it time to drop it?

```bash
./check-upstream.sh
```

It counts SDCP symbols in the libfprint of the package. Today it prints `NO`.
When MR !547 is merged and your distro ships it, it prints `YES`: run
`./uninstall.sh`, enroll again and test with `fprintd-verify`.

## PAM

Out of scope here. On the test machine `pam_fprintd` was already enabled in
`system-auth`, `system-local-login` and `kde-fingerprint` (`plasmalogin` has it
commented out), so `sudo` asks for the finger first and falls back to the
password. A wrong PAM edit can lock you out; check it before changing anything.

## What was verified, and what was not

Verified: `tests/test-guard.sh` (the model/sensor check, with fake `lsusb` and DMI);
the stock libfprint recognises the sensor and opens it; the stock enrollment
leaves 0 prints on the sensor; the meson option names and the udev behaviour at
the pinned commit.

**Not verified yet:** running `install.sh` end to end; that the drop-in makes
fprintd load the new library on this machine (the installer checks this itself);
and that this build, installed under `/usr/local`, stores the fingerprint again.
The same commit did work when installed over `/usr` in August.

## Tested on

- Samsung Galaxy Book4 Ultra NP960XGL, BIOS P10ALX.470.260413.05, CachyOS,
  kernel 7.2.9-1-cachyos, libfprint package 1.94.100-1.1, fprintd 1.94.5.
