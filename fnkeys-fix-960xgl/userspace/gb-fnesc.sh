#!/bin/bash
# Run by acpid on Fn+Esc. Executes FNESC_COMMAND (from fnesc.conf) as the user
# logged in on seat0, because acpid itself runs as root.
CONF="${FNESC_CONF:-/etc/samsung-galaxybook-960xgl/fnesc.conf}"
LOCK="${FNESC_LOCK:-/run/samsung-galaxybook-fnesc.lock}"
TAG="samsung-galaxybook-fnesc"

# One physical press arrives as a burst of 3 events within ~20 ms. The first
# instance takes the lock and keeps it for 0.5 s; the others exit immediately.
exec 9>"$LOCK"
flock -n 9 || exit 0

FNESC_COMMAND=""
# shellcheck disable=SC1090
[ -r "$CONF" ] && . "$CONF"

run_action() {
    if [ -z "$FNESC_COMMAND" ]; then
        logger -t "$TAG" "Fn+Esc pressed (FNESC_COMMAND is empty in $CONF)"
        return 0
    fi

    local user uid
    user=$(loginctl list-sessions --no-legend | awk '$4 == "seat0" {print $3}' | head -1)
    if [ -z "$user" ]; then
        logger -t "$TAG" "Fn+Esc pressed but no session on seat0; nothing run"
        return 0
    fi
    uid=$(id -u "$user")

    runuser -u "$user" -- env \
        XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        sh -c "$FNESC_COMMAND" \
        || logger -t "$TAG" "FNESC_COMMAND failed for user $user"
}

run_action
sleep 0.5
