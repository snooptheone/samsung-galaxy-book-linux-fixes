#!/bin/bash
# Remove the fingerprint fix. Fingerprints (on the chip or in /var/lib/fprint) are
# never deleted.
set -e

STATE_DIR="/var/lib/fingerprint-fix-960xgl"
STATE_FILE="${STATE_DIR}/state"
DROPIN_DIR="/etc/systemd/system/fprintd.service.d"
DROPIN="${DROPIN_DIR}/libfprint-sdcp.conf"

echo "=== Fingerprint fix uninstaller ==="

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run with sudo" >&2
    exit 1
fi

if [ ! -f "$STATE_FILE" ]; then
    echo "Nothing to remove (no state file)."
    exit 0
fi

STATE_MODE=""
STATE_PREFIX=""
# shellcheck disable=SC1090
. "$STATE_FILE"
: "${STATE_PREFIX:?state file has no prefix}"

systemctl stop fprintd 2>/dev/null || true

if [ "$STATE_MODE" = "system" ]; then
    echo "Restoring the libfprint package files..."
    pacman -S --noconfirm libfprint
    ldconfig
else
    echo "Removing the fprintd drop-in and the files under ${STATE_PREFIX}..."
    rm -f "$DROPIN"
    rmdir "$DROPIN_DIR" 2>/dev/null || true
    systemctl daemon-reload
    rm -f "${STATE_PREFIX}"/lib/libfprint-2.so*
    rm -f "${STATE_PREFIX}/lib/pkgconfig/libfprint-2.pc"
    rm -rf "${STATE_PREFIX}/include/libfprint-2"
fi

rm -f "$STATE_FILE"
rmdir "$STATE_DIR" 2>/dev/null || true

cat <<EOF
Done. fprintd now uses the stock libfprint again.

A fingerprint enrolled with the SDCP library is not usable by the stock one, and
the stock libfprint does not store a new enrollment on this sensor. Nothing was
deleted: if fprintd crashes when listing fingers, move the old print aside
(/var/lib/fprint/<user>/egismoc/<id>/<finger-number>) instead of removing it.
EOF
