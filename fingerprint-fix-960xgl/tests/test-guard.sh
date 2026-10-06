#!/bin/bash
# The installer must accept only the NP960XGL with sensor 1c7a:05a1, using
# fake lsusb and DMI (no root, no packages, nothing is installed).
DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL="$DIR/../install.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

fake_lsusb() {  # name, "USB ID" lines to print
    printf '#!/bin/sh\nprintf "%%s\\n" %s\n' "$2" > "$TMP/$1"
    chmod +x "$TMP/$1"
}
fake_lsusb with-05a1 '"Bus 003 Device 004: ID 1c7a:05a1 LighTuning Technology Inc. ETU905A80-E" "Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub"'
fake_lsusb with-05a5 '"Bus 003 Device 004: ID 1c7a:05a5 LighTuning Technology Inc."'
fake_lsusb without   '"Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub"'

check() {  # description expected-exit model lsusb
    FPFIX_DMI_PRODUCT="$3" FPFIX_LSUSB="$TMP/$4" bash "$INSTALL" --check-only >/dev/null 2>&1
    got=$?
    if [ "$got" -eq "$2" ]; then echo "ok   - $1"; else echo "FAIL - $1 (expected exit $2, got $got)"; fail=1; fi
}

check "NP960XGL with sensor 05a1 is accepted"        0 960XGL with-05a1
check "NP960XGL with only 05a5 (Book5) is refused"   1 960XGL with-05a5
check "NP960XGL without the sensor is refused"       1 960XGL without
check "another model with 05a1 is refused"           1 940XGL with-05a1

exit "$fail"
