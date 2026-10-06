#!/bin/bash
# One Fn+Esc press is a burst of 3 ACPI events within ~20 ms (measured on the
# NP960XGL). The action must run once for the burst, and again for a later press.
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/../userspace/gb-fnesc.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Fake `logger`: one line per call, so we can count how many times the action ran.
mkdir "$TMP/bin"
printf '#!/bin/sh\necho "$@" >> "%s/calls"\n' "$TMP" > "$TMP/bin/logger"
chmod +x "$TMP/bin/logger"
: > "$TMP/conf"   # empty FNESC_COMMAND -> the action is a single logger call
: > "$TMP/calls"

press() {  # three instances started a few ms apart, like acpid does
    for _ in 1 2 3; do
        PATH="$TMP/bin:$PATH" FNESC_CONF="$TMP/conf" FNESC_LOCK="$TMP/lock" bash "$SCRIPT" &
        sleep 0.005
    done
    wait
}

fail=0
check() {  # description expected
    got=$(wc -l < "$TMP/calls")
    if [ "$got" -eq "$2" ]; then echo "ok   - $1 ($got call)"; else echo "FAIL - $1 (expected $2, got $got)"; fail=1; fi
}

press
check "burst of 3 events runs the action once" 1
press
check "a second press after the burst runs it again" 2

exit "$fail"
