#!/bin/bash
# Checks the profile -> icon/text map, and the whole pipeline with fake
# gdbus/busctl/qdbus/notify-send (no desktop, no daemon, no root needed).
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/../power-profile-osd.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

expect() {  # description expected actual
    if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1 (expected '$2', got '$3')"; fail=1; fi
}

# --- the map ---
expect "performance"  "battery-profile-performance|Performance Mode" "$(bash "$SCRIPT" --map performance)"
expect "power-saver"  "battery-profile-powersave|Power Saver Mode"    "$(bash "$SCRIPT" --map power-saver)"
expect "balanced"     "battery-profile-balanced|Balanced Mode"        "$(bash "$SCRIPT" --map balanced)"
expect "unknown profile shows its name" "battery-profile-balanced|turbo" "$(bash "$SCRIPT" --map turbo)"

# --- the pipeline, with fakes ---
mkdir "$TMP/bin"
# gdbus: one property-change line for ActiveProfile, then the monitor ends
printf '#!/bin/sh\necho "PropertiesChanged ({'"'"'ActiveProfile'"'"': <'"'"'performance'"'"'>}, [])"\n' > "$TMP/bin/gdbus"
# busctl: what `busctl get-property ... ActiveProfile` prints
printf '#!/bin/sh\necho '"'"'s "performance"'"'"'\n' > "$TMP/bin/busctl"
# every qdbus flavour records its arguments (the script tries all three names)
for q in qdbus-qt6 qdbus6 qdbus; do
    printf '#!/bin/sh\necho "$@" >> "%s/qdbus.calls"\n' "$TMP" > "$TMP/bin/$q"
done
printf '#!/bin/sh\necho "$@" >> "%s/notify.calls"\n' "$TMP" > "$TMP/bin/notify-send"
chmod +x "$TMP"/bin/*

PATH="$TMP/bin:$PATH" bash "$SCRIPT"
expect "exits non-zero when the monitor ends (so systemd restarts it)" "1" "$?"
expect "OSD called once with icon and text" \
    "org.kde.plasmashell /org/kde/osdService org.kde.osdService.showText battery-profile-performance Performance Mode" \
    "$(cat "$TMP/qdbus.calls" 2>/dev/null)"
expect "no fallback notice when the OSD works" "" "$(cat "$TMP/notify.calls" 2>/dev/null)"

# --- fallback: the OSD call fails -> a regular notification ---
rm -f "$TMP/qdbus.calls"
for q in qdbus-qt6 qdbus6 qdbus; do printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/$q"; done
PATH="$TMP/bin:$PATH" bash "$SCRIPT" >/dev/null
expect "falls back to notify-send when the OSD fails" \
    "--icon=battery-profile-performance Power Profile Performance Mode" \
    "$(cat "$TMP/notify.calls" 2>/dev/null)"

exit "$fail"
