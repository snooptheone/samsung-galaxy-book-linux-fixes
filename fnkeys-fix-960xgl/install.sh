#!/bin/bash
# Fn+Esc (Samsung support key) handler for the Galaxy Book4 Ultra (NP960XGL).
#
# Two interchangeable variants, pick one (installing one removes the other):
#   --userspace   (default) acpid rule, no kernel module involved
#   --dkms        patched samsung-galaxybook driver; Fn+Esc becomes KEY_PROG2
#
# Options:
#   --action CMD  command to run on Fn+Esc (userspace variant), written to fnesc.conf
#   --remove-fork remove the samsung-galaxybook-book5pro DKMS fork first
#                 (required for --dkms when that fork is installed: same module name)
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
FORK_DKMS="samsung-galaxybook-book5pro"
FORK_VER="1.0"
HERE="$(cd "$(dirname "$0")" && pwd)"

usage() {
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
}

VARIANT="userspace"
ACTION=""
HAVE_ACTION=false
REMOVE_FORK=false
while [ $# -gt 0 ]; do
    case "$1" in
        --userspace) VARIANT="userspace" ;;
        --dkms) VARIANT="dkms" ;;
        --remove-fork) REMOVE_FORK=true ;;
        --action)
            [ $# -ge 2 ] || { echo "ERROR: --action needs a command" >&2; exit 1; }
            ACTION="$2"; HAVE_ACTION=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

echo "=== Galaxy Book4 Ultra Fn+Esc fix (${VARIANT}) ==="

# Must be root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run with sudo" >&2
    exit 1
fi

# Model guard: this was only tested on the NP960XGL
PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
if [ "$PRODUCT" != "960XGL" ]; then
    echo "ERROR: this fix is only for the Galaxy Book4 Ultra (DMI product_name 960XGL); found '${PRODUCT}'" >&2
    exit 1
fi

# Detect package manager
if command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
elif command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
elif command -v apt-get >/dev/null 2>&1; then
    PKG_MGR="apt"
else
    PKG_MGR="unknown"
fi

pkg_install() {
    case "$PKG_MGR" in
        dnf) dnf install -y "$@" ;;
        pacman) pacman -S --noconfirm --needed "$@" ;;
        apt) apt-get install -y "$@" ;;
        *) echo "ERROR: unknown package manager; install manually: $*" >&2; exit 1 ;;
    esac
}

STATE_VARIANT=""
STATE_ACPID_BY_US=0
# shellcheck disable=SC1090
[ -f "$STATE_FILE" ] && . "$STATE_FILE"

fork_present() {
    dkms status 2>/dev/null | grep -q "^${FORK_DKMS}/"
}

remove_fork() {
    echo "Removing the ${FORK_DKMS} fork..."
    systemctl disable --now samsung-galaxybook-fkeys-monitor.service 2>/dev/null || true
    rm -f /etc/systemd/system/samsung-galaxybook-fkeys-monitor.service
    rm -f /usr/local/bin/samsung-galaxybook-fkeys-monitor.sh
    rm -f /usr/local/bin/samsung-galaxybook-fkeys-cleanup.sh
    rm -f /etc/modules-load.d/samsung-galaxybook.conf
    rm -f /var/lib/samsung-galaxybook/fkeys-kernel.ver
    dkms remove "${FORK_DKMS}/${FORK_VER}" --all 2>/dev/null || true
    rm -rf "/usr/src/${FORK_DKMS}-${FORK_VER}"
    systemctl daemon-reload
}

# Switching variants: remove the other one first, so Fn+Esc never fires twice
# (the driver forwards the ACPI event to userspace even when it handles it).
if [ -n "$STATE_VARIANT" ] && [ "$STATE_VARIANT" != "$VARIANT" ]; then
    echo "Removing the previously installed '${STATE_VARIANT}' variant..."
    "${HERE}/uninstall.sh" --variant "$STATE_VARIANT" --keep-config
    STATE_ACPID_BY_US=0
fi

if $REMOVE_FORK && fork_present; then
    remove_fork
fi

ACPID_BY_US="$STATE_ACPID_BY_US"

if [ "$VARIANT" = "userspace" ]; then
    echo "Installing acpid..."
    pkg_install acpid

    install -d /etc/acpi/events "$CONF_DIR"
    install -m 0644 "${HERE}/userspace/gb-fnesc.rules" "$RULE_DEST"
    install -m 0755 "${HERE}/userspace/gb-fnesc.sh" "$ACTION_DEST"
    [ -f "$CONF_FILE" ] || install -m 0644 "${HERE}/userspace/fnesc.conf" "$CONF_FILE"
    if $HAVE_ACTION; then
        {
            grep -v '^FNESC_COMMAND=' "${HERE}/userspace/fnesc.conf"
            printf 'FNESC_COMMAND=%q\n' "$ACTION"
        } > "$CONF_FILE"
        echo "Fn+Esc action set in ${CONF_FILE}"
    fi

    if systemctl is-enabled --quiet acpid 2>/dev/null; then
        :
    else
        systemctl enable acpid
        ACPID_BY_US=1
    fi
    systemctl restart acpid
    echo "✓ Fn+Esc rule active (no reboot needed). Press Fn+Esc and check:"
    echo "    journalctl -t samsung-galaxybook-fnesc -n 3"
else
    echo "Installing dkms and kernel headers..."
    case "$PKG_MGR" in
        pacman)
            PKGBASE="$(cat "/usr/lib/modules/$(uname -r)/pkgbase" 2>/dev/null || true)"
            [ -n "$PKGBASE" ] || { echo "ERROR: cannot find the kernel package name for $(uname -r)" >&2; exit 1; }
            pkg_install dkms "${PKGBASE}-headers" ;;
        dnf) pkg_install dkms "kernel-devel-$(uname -r)" ;;
        *) pkg_install dkms "linux-headers-$(uname -r)" ;;
    esac

    # Same module name as the in-tree driver: the book5pro fork cannot coexist.
    if fork_present; then
        echo "ERROR: ${FORK_DKMS} is installed and uses the same module name." >&2
        echo "       Re-run with --remove-fork to replace it." >&2
        exit 1
    fi

    PATTERN="$(sed -n 's/^BUILD_EXCLUSIVE_KERNEL="\(.*\)"/\1/p' "${HERE}/dkms/dkms.conf")"
    if ! uname -r | grep -Eq "$PATTERN"; then
        echo "ERROR: kernel $(uname -r) is outside the supported series ('${PATTERN}')." >&2
        echo "       Use the default --userspace variant instead." >&2
        exit 1
    fi

    if dkms status "${DKMS_NAME}/${DKMS_VER}" 2>/dev/null | grep -q "${DKMS_NAME}"; then
        echo "Removing previous ${DKMS_NAME}/${DKMS_VER}..."
        dkms remove "${DKMS_NAME}/${DKMS_VER}" --all 2>/dev/null || true
    fi
    rm -rf "$SRC_DIR"
    mkdir -p "$SRC_DIR"
    cp -a "${HERE}/dkms/dkms.conf" "${HERE}/dkms/Makefile" \
        "${HERE}/dkms/samsung-galaxybook.c" "${HERE}/dkms/firmware_attributes_class.h" "$SRC_DIR/"

    dkms add "${DKMS_NAME}/${DKMS_VER}"
    dkms build "${DKMS_NAME}/${DKMS_VER}"
    dkms install "${DKMS_NAME}/${DKMS_VER}"
    echo "✓ Patched driver installed. Reboot to load it (do not rmmod/modprobe:"
    echo "  that detaches power-profiles-daemon from the platform profile)."
fi

mkdir -p "$STATE_DIR"
{
    echo "STATE_VARIANT=${VARIANT}"
    echo "STATE_ACPID_BY_US=${ACPID_BY_US}"
} > "$STATE_FILE"
