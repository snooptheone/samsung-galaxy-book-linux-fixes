#!/bin/bash
# Remove power-profile-osd. Run as your normal user, not with sudo.
set -e

NAME="power-profile-osd"
BIN="${HOME}/.local/bin/${NAME}"
UNIT="${HOME}/.config/systemd/user/${NAME}.service"

echo "=== power-profile-osd uninstaller ==="

if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: run as your normal user, not as root/sudo" >&2
    exit 1
fi

systemctl --user disable --now "${NAME}.service" 2>/dev/null || true
rm -f "$UNIT" "$BIN"
systemctl --user daemon-reload
echo "✓ ${NAME} removed"
