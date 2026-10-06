#!/bin/bash
# The acpid rule must match the real Fn+Esc event line and nothing else.
# Real line captured with `acpi_listen` on the NP960XGL.
RULE="$(dirname "$0")/../userspace/gb-fnesc.rules"
REGEX="$(sed -n 's/^event=//p' "$RULE")"
fail=0

check() {  # expected(0=match,1=no match) description line
    echo "$3" | grep -Eq "$REGEX"
    got=$?
    if [ "$got" -eq "$1" ]; then echo "ok   - $2"; else echo "FAIL - $2"; fail=1; fi
}

check 0 "Fn+Esc (0x41) matches"            "samsung-galaxybook SAM0430:00 00000041 00000001"
check 1 "0x42 does not match"              "samsung-galaxybook SAM0430:00 00000042 00000001"
check 1 "0x73 does not match"              "samsung-galaxybook SAM0430:00 00000073 00000001"
check 1 "0x7d (kbd backlight) not matched" "samsung-galaxybook SAM0430:00 0000007d 00000001"
check 1 "other device with 0x41 not matched" "button/lid LID0 00000041 00000000"

exit "$fail"
