#!/bin/bash
# Remove the Fn+Esc fix. By default removes whichever variant is recorded in the
# state file.
#   --variant userspace|dkms   remove this variant instead
#   --keep-config              keep /etc/samsung-galaxybook-960xgl/fnesc.conf
set -e

DKMS_NAME="samsung-galaxybook-960xgl"
DKMS_VER="1.0"
SRC_DIR="/usr/src/${DKMS_NAME}-${DKMS_VER}"
STATE_DIR="/var/lib/samsung-galaxybook-960xgl"
STATE_FILE="${STATE_DIR}/state"
CONF_DIR="/etc/samsung-galaxybook-960xgl"
CONF_FILE="${CONF_DIR}/fnesc.conf"
RULE_DEST="/etc/acpi/events/samsung-galaxybook-fnesc"
ACTION_DEST="/usr/local/sbin/samsung-galaxybook-fnesc.sh"

VARIANT=""
KEEP_CONFIG=false
while [ $# -gt 0 ]; do
    case "$1" in
        --variant)
            [ $# -ge 2 ] || { echo "ERROR: --variant needs userspace or dkms" >&2; exit 1; }
            VARIANT="$2"; shift ;;
        --keep-config) KEEP_CONFIG=true ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

echo "=== Galaxy Book4 Ultra Fn+Esc fix uninstaller ==="

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run with sudo" >&2
    exit 1
fi

STATE_VARIANT=""
STATE_ACPID_BY_US=0
# shellcheck disable=SC1090
[ -f "$STATE_FILE" ] && . "$STATE_FILE"

VARIANT="${VARIANT:-$STATE_VARIANT}"
if [ -z "$VARIANT" ]; then
    echo "Nothing to remove (no state file)."
    exit 0
fi

case "$VARIANT" in
    userspace)
        echo "Removing the acpid rule..."
        rm -f "$RULE_DEST" "$ACTION_DEST"
        if ! $KEEP_CONFIG; then
            rm -f "$CONF_FILE"
            rmdir "$CONF_DIR" 2>/dev/null || true
        fi
        if [ "$STATE_ACPID_BY_US" = "1" ]; then
            systemctl disable --now acpid 2>/dev/null || true
        else
            systemctl try-restart acpid 2>/dev/null || true
        fi
        ;;
    dkms)
        echo "Removing the DKMS module..."
        if dkms status "${DKMS_NAME}/${DKMS_VER}" 2>/dev/null | grep -q "${DKMS_NAME}"; then
            dkms remove "${DKMS_NAME}/${DKMS_VER}" --all
        fi
        rm -rf "$SRC_DIR"
        echo "Reboot to go back to the in-tree driver (avoid rmmod/modprobe)."
        ;;
    *)
        echo "ERROR: unknown variant '${VARIANT}' (use userspace or dkms)" >&2
        exit 1
        ;;
esac

rm -f "$STATE_FILE"
rmdir "$STATE_DIR" 2>/dev/null || true
echo "Done."
