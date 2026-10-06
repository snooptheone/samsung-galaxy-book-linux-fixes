#!/bin/bash
# Shows an on-screen notification when the power profile changes.
#
# Runs as a systemd *user* service: it listens to power-profiles-daemon on the
# system bus (readable by any user) and shows the notice in the user's own
# session, so it needs no root.
#
#   power-profile-osd --map PROFILE   print "icon|text" for PROFILE (used by tests)

map_profile() {
    case "$1" in
        performance) echo "battery-profile-performance|Performance Mode" ;;
        power-saver) echo "battery-profile-powersave|Power Saver Mode" ;;
        balanced)    echo "battery-profile-balanced|Balanced Mode" ;;
        *)           echo "battery-profile-balanced|$1" ;;
    esac
}

if [ "${1:-}" = "--map" ]; then
    map_profile "${2:-}"
    exit 0
fi

# KDE's OSD when available; a regular notification otherwise (or if it fails).
show_osd() {  # icon text
    local qdbus="" c
    for c in qdbus-qt6 qdbus6 qdbus; do
        if command -v "$c" >/dev/null 2>&1; then qdbus="$c"; break; fi
    done
    if [ -n "$qdbus" ] \
        && "$qdbus" org.kde.plasmashell /org/kde/osdService \
            org.kde.osdService.showText "$1" "$2" >/dev/null 2>&1; then
        return 0
    fi
    notify-send --icon="$1" "Power Profile" "$2" 2>/dev/null || true
}

gdbus monitor --system --dest net.hadess.PowerProfiles \
    --object-path /net/hadess/PowerProfiles |
grep --line-buffered "ActiveProfile" |
while read -r _; do
    sleep 0.1
    profile=$(busctl get-property net.hadess.PowerProfiles \
        /net/hadess/PowerProfiles net.hadess.PowerProfiles ActiveProfile \
        2>/dev/null | awk -F'"' '{print $2}')
    [ -n "$profile" ] || continue
    IFS='|' read -r icon text <<< "$(map_profile "$profile")"
    show_osd "$icon" "$text"
done

# The monitor ended (daemon gone, bus error): exit non-zero so systemd restarts us.
exit 1
