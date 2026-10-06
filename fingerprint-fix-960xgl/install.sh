#!/bin/bash
# Fingerprint fix for the Galaxy Book4 Ultra (NP960XGL, EgisTec sensor 1c7a:05a1).
#
# Why: with the stock libfprint 1.94.100 the enrollment "completes" but the chip
# keeps no fingerprint (measured on this model). The SDCP v2 branch of libfprint
# (MR !547) handles that step, so this builds it at a pinned commit.
#
# It goes under /usr/local and ONLY fprintd is pointed at it, through a systemd
# drop-in: the libfprint package files are not touched. Fingerprints (on the chip
# or in /var/lib/fprint) are never deleted.
#
#   --commit SHA   build this commit instead of the pinned one
#   --system       install into /usr (overwrites the libfprint package files)
#   --check-only   only check that this machine is supported, then exit
set -e

REPO_URL="https://gitlab.freedesktop.org/libfprint/libfprint.git"
PINNED_COMMIT="2d7c5277de08c6b29b3fac7447f17a516fbc4d1c"
MODEL="960XGL"
SENSOR_ID="1c7a:05a1"
STATE_DIR="/var/lib/fingerprint-fix-960xgl"
STATE_FILE="${STATE_DIR}/state"
DROPIN_DIR="/etc/systemd/system/fprintd.service.d"
DROPIN="${DROPIN_DIR}/libfprint-sdcp.conf"
LSUSB="${FPFIX_LSUSB:-lsusb}"

usage() {
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

COMMIT="$PINNED_COMMIT"
SYSTEM=false
CHECK_ONLY=false
while [ $# -gt 0 ]; do
    case "$1" in
        --commit)
            [ $# -ge 2 ] || { echo "ERROR: --commit needs a SHA" >&2; exit 1; }
            COMMIT="$2"; shift ;;
        --system) SYSTEM=true ;;
        --check-only) CHECK_ONLY=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

# Only the model and sensor this was tested on.
check_hardware() {
    local product
    product="${FPFIX_DMI_PRODUCT:-$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)}"
    if [ "$product" != "$MODEL" ]; then
        echo "ERROR: only for the Galaxy Book4 Ultra (DMI product_name ${MODEL}); found '${product}'" >&2
        return 1
    fi
    if ! "$LSUSB" 2>/dev/null | grep -qi "ID ${SENSOR_ID}"; then
        echo "ERROR: fingerprint sensor ${SENSOR_ID} not found on the USB bus" >&2
        return 1
    fi
}

echo "=== Fingerprint fix (Galaxy Book4 Ultra) ==="
check_hardware || exit 1
if $CHECK_ONLY; then
    echo "OK: supported machine (${MODEL}, sensor ${SENSOR_ID})"
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run with sudo" >&2
    exit 1
fi

# Arch-based only: it is what this was tested on.
if ! command -v pacman >/dev/null 2>&1; then
    echo "ERROR: only tested on Arch-based distros (pacman not found)" >&2
    exit 1
fi

if $SYSTEM; then PREFIX="/usr"; else PREFIX="/usr/local"; fi

echo "Installing build dependencies..."
pacman -S --noconfirm --needed meson ninja gcc pkgconf git systemd glib2 libgusb libgudev openssl pixman

BUILD_DIR="$(mktemp -d /tmp/libfprint-sdcp.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "Fetching libfprint ${COMMIT}..."
git init -q "${BUILD_DIR}/src"
git -C "${BUILD_DIR}/src" remote add origin "$REPO_URL"
git -C "${BUILD_DIR}/src" fetch -q --depth 1 origin "$COMMIT"
git -C "${BUILD_DIR}/src" checkout -q FETCH_HEAD
GOT="$(git -C "${BUILD_DIR}/src" rev-parse HEAD)"
case "$GOT" in
    "$COMMIT"*) ;;
    *) echo "ERROR: fetched ${GOT}, expected ${COMMIT}" >&2; exit 1 ;;
esac

# Outside /usr, meson would still write udev rules/hwdb into the absolute
# /usr/lib/udev (the udevdir of pkg-config), over the package's files: turn them off.
MESON_OPTS=(--prefix="$PREFIX" --libdir=lib --buildtype=release
    -Dintrospection=false -Ddoc=false -Dgtk-examples=false -Dinstalled-tests=false)
$SYSTEM || MESON_OPTS+=(-Dudev_rules=disabled -Dudev_hwdb=disabled)

echo "Building (prefix ${PREFIX})..."
meson setup "${BUILD_DIR}/build" "${BUILD_DIR}/src" "${MESON_OPTS[@]}"
meson compile -C "${BUILD_DIR}/build"
meson install -C "${BUILD_DIR}/build"

if $SYSTEM; then
    ldconfig
else
    mkdir -p "$DROPIN_DIR"
    cat > "$DROPIN" <<EOF
# Installed by fingerprint-fix-960xgl: make fprintd load the SDCP-capable libfprint.
[Service]
Environment=LD_LIBRARY_PATH=${PREFIX}/lib
EOF
    systemctl daemon-reload
fi

# Prove it: start fprintd and look at which libfprint it really loaded, and that
# it has SDCP support. A /usr/local copy can lose to /usr/lib, so do not assume.
undo_dropin() {
    $SYSTEM && return 0
    rm -f "$DROPIN"
    rmdir "$DROPIN_DIR" 2>/dev/null || true
    systemctl daemon-reload
}

systemctl stop fprintd 2>/dev/null || true
systemctl reset-failed fprintd 2>/dev/null || true
systemctl start fprintd
sleep 1
PID="$(systemctl show -p MainPID --value fprintd)"
LOADED="$(awk '/libfprint-2\.so/ {print $6; exit}' "/proc/${PID}/maps" 2>/dev/null || true)"
systemctl stop fprintd 2>/dev/null || true

if [ -z "$LOADED" ] || ! nm -D --defined-only "$LOADED" 2>/dev/null | grep -qi sdcp; then
    echo "ERROR: fprintd loaded '${LOADED:-nothing}', which has no SDCP support." >&2
    echo "       Undoing the drop-in. Nothing else was changed." >&2
    undo_dropin
    exit 1
fi
echo "OK: fprintd loads ${LOADED} (SDCP-capable)"

mkdir -p "$STATE_DIR"
{
    echo "STATE_MODE=$($SYSTEM && echo system || echo local)"
    echo "STATE_PREFIX=${PREFIX}"
    echo "STATE_COMMIT=${GOT}"
} > "$STATE_FILE"

cat <<EOF

Done. Nothing was deleted from /var/lib/fprint or from the sensor.

Next, enroll your finger (a fingerprint made with another libfprint is not usable):
    fprintd-enroll -f right-index-finger
    fprintd-verify

If fprintd crashes ("g_object_set: assertion ... failed") when listing or enrolling,
an old print file from another libfprint is in /var/lib/fprint/<user>/egismoc/<id>/.
Move it aside instead of deleting it:
    sudo mv /var/lib/fprint/<user>/egismoc/<id>/<finger-number> /var/lib/fprint/<user>/old-print
EOF
