#!/bin/bash
# Install power-profile-osd as a systemd *user* service. Run as your normal
# user, NOT with sudo: everything goes under your home directory.
set -e

NAME="power-profile-osd"
BIN="${HOME}/.local/bin/${NAME}"
UNIT_DIR="${HOME}/.config/systemd/user"
UNIT="${UNIT_DIR}/${NAME}.service"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "=== power-profile-osd installer ==="

if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: run as your normal user, not as root/sudo (it installs under \$HOME)" >&2
    exit 1
fi

for tool in gdbus busctl systemctl; do
    command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool not found" >&2; exit 1; }
done

if ! command -v qdbus-qt6 >/dev/null 2>&1 && ! command -v qdbus6 >/dev/null 2>&1 \
    && ! command -v qdbus >/dev/null 2>&1 && ! command -v notify-send >/dev/null 2>&1; then
    echo "ERROR: need qdbus (KDE OSD) or notify-send to show the notice" >&2
    exit 1
fi

if ! busctl status net.hadess.PowerProfiles >/dev/null 2>&1; then
    echo "WARNING: net.hadess.PowerProfiles is not on the system bus."
    echo "         power-profiles-daemon (or tuned-ppd) is not running; the service"
    echo "         will keep retrying until it is."
fi

install -Dm755 "${HERE}/power-profile-osd.sh" "$BIN"
install -Dm644 "${HERE}/power-profile-osd.service" "$UNIT"

systemctl --user daemon-reload
systemctl --user enable "${NAME}.service"
systemctl --user restart "${NAME}.service"
echo "✓ ${NAME} installed and running (user service)"

# The old system-wide service (kdeosd-fix) would show a second notice for the
# same change. Removing it needs root, so only print the commands.
if systemctl list-unit-files kde-power-osd.service --no-legend 2>/dev/null | grep -q kde-power-osd; then
    echo
    echo "The old system service kde-power-osd is still installed. To remove it:"
    echo "  sudo systemctl disable --now kde-power-osd.service"
    echo "  sudo rm -f /etc/systemd/system/kde-power-osd.service /usr/local/sbin/kde-power-osd.sh \\"
    echo "             /var/lib/samsung-galaxybook/kde-power-osd.installed"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo rmdir --ignore-fail-on-non-empty /var/lib/samsung-galaxybook"
fi
