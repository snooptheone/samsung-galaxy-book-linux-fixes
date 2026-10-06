#!/bin/bash
# Is it time to drop this fix? Looks for SDCP support in the libfprint of the
# distro package (SDCP v2 is MR !547, not merged when this was written).
#   exit 0: the installed /usr/lib libfprint has SDCP
#   exit 1: it does not
#   exit 2: libfprint not found
LIB="/usr/lib/libfprint-2.so.2"

[ -e "$LIB" ] || { echo "libfprint not found at $LIB"; exit 2; }

echo "libfprint package: $(pacman -Q libfprint 2>/dev/null || echo unknown)"

# --system mode overwrites the package files, so the answer would describe our own build.
if pacman -Qkk libfprint 2>&1 | grep -q "SHA256 checksum mismatch"; then
    echo "WARNING: files of the libfprint package were altered (fix installed with --system?)."
    echo "         The result below describes the installed copy, not the package."
fi

n="$(nm -D --defined-only "$LIB" 2>/dev/null | grep -ci sdcp || true)"
if [ "${n:-0}" -gt 0 ]; then
    echo "YES: ${LIB} exports ${n} SDCP symbols. The fix may no longer be needed:"
    echo "     run ./uninstall.sh, then re-enroll and test with fprintd-verify."
    exit 0
fi
echo "NO: ${LIB} has no SDCP support yet. Keep the fix."
exit 1
