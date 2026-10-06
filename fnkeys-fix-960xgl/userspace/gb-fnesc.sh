#!/bin/bash
# Run by acpid on Fn+Esc. Executes FNESC_COMMAND (from fnesc.conf) as the user
# logged in on seat0, because acpid itself runs as root.
CONF="/etc/samsung-galaxybook-960xgl/fnesc.conf"
TAG="samsung-galaxybook-fnesc"

FNESC_COMMAND=""
# shellcheck disable=SC1090
[ -r "$CONF" ] && . "$CONF"

if [ -z "$FNESC_COMMAND" ]; then
    logger -t "$TAG" "Fn+Esc pressed (FNESC_COMMAND is empty in $CONF)"
    exit 0
fi

user=$(loginctl list-sessions --no-legend | awk '$4 == "seat0" {print $3}' | head -1)
if [ -z "$user" ]; then
    logger -t "$TAG" "Fn+Esc pressed but no session on seat0; nothing run"
    exit 0
fi
uid=$(id -u "$user")

runuser -u "$user" -- env \
    XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    sh -c "$FNESC_COMMAND" \
    || logger -t "$TAG" "FNESC_COMMAND failed for user $user"
