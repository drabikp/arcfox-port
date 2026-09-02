#!/usr/bin/env bash
# build-loop.sh — drive the arcfox build to completion, auto-fixing the two
# error classes that recur mechanically:
#
#   1. "depends on undefined module X"  -> add X's prebuilt from the firmware
#                                          (resolve-build-blobs.sh logic)
#   2. check_elf_file "Unresolved symbol" -> annotate the blob ;DISABLE_CHECKELF
#                                          (fix-checkelf.sh logic)
#
# Anything else stops the loop and prints the error for a human. That boundary
# matters: those two classes are known-safe mechanical fixes, everything else
# (partition config, missing headers, VINTF) needs a real decision.
#
#   ./build-loop.sh [max_rounds]

set -o pipefail
unset -f grep 2>/dev/null || true

MAX="${1:-25}"
TOP=$HOME/android/arcfox
WS=$HOME/workspace/motorola-lineageos
DEV="$TOP/device/motorola/arcfox"
COM="$TOP/device/motorola/sm8635-common"
DUMP=$HOME/android/firmware/W1UXS36H/extracted
INV="$WS/blobs/device-inventory.txt"
LOG=/tmp/arcfox-build.log

round=0
while [ "$round" -lt "$MAX" ]; do
    round=$((round + 1))
    echo "########## build round $round ##########"

    (cd "$TOP" && source build/envsetup.sh >/dev/null 2>&1 \
       && breakfast arcfox >/dev/null 2>&1 \
       && LC_ALL=C USE_CCACHE=1 mka bacon) > "$LOG" 2>&1
    rc=$?

    ZIP=$(ls "$TOP"/out/target/product/arcfox/lineage-*.zip 2>/dev/null | head -1)
    if [ -n "$ZIP" ]; then
        echo "=========================================="
        echo "ROM BUILT: $ZIP"
        ls -la "$ZIP"
        echo "=========================================="
        exit 0
    fi

    changed=0

    # --- class 2: check_elf_file unresolved symbols -------------------------
    out=$("$WS/fix-checkelf.sh" "$LOG" 2>&1)
    echo "$out"
    if echo "$out" | /usr/bin/grep -q "^  + DISABLE_CHECKELF"; then
        changed=1
    fi

    # --- class 1: undefined module -----------------------------------------
    if [[ "$(cat "$LOG")" == *"undefined module"* ]]; then
        while IFS=$'\t' read -r mod consumer; do
            [ -n "$mod" ] || continue
            path=$(/usr/bin/grep -m1 -E "/${mod}\.so$" "$INV" || /usr/bin/grep -m1 -E "/${mod}$" "$INV")
            [ -n "$path" ] || { echo "  UNRESOLVED $mod"; continue; }
            case "$consumer" in
                *sm8635-common*) tgt="$COM/proprietary-files.txt"; lbl=common ;;
                *)               tgt="$DEV/proprietary-files.txt"; lbl=device ;;
            esac
            /usr/bin/grep -qE "^-?${path//./\\.}(;|$)" "$tgt" && continue
            if [ "$lbl" = common ] && /usr/bin/grep -qE "^-?${path//./\\.}(;|$)" "$DEV/proprietary-files.txt"; then
                /usr/bin/sed -i "\\|^-\\?${path//./\\.}\$|d" "$DEV/proprietary-files.txt"
                printf '%s\n' "$path" >> "$tgt"
                echo "  ~ MOVED device->common $path"
            else
                printf '%s\n' "$path" >> "$tgt"
                echo "  + $lbl $path (for $mod)"
            fi
            changed=1
        done < <(/usr/bin/grep "depends on undefined module" "$LOG" | awk '
                /depends on undefined module/ {
                    match($0, /undefined module "[^"]+"/); mod = substr($0, RSTART+18, RLENGTH-19)
                    match($0, /error: [^:]+:/);            src = substr($0, RSTART+7, RLENGTH-8)
                    print mod "\t" src }' | sort -u)
    fi

    if [ "$changed" -eq 0 ]; then
        echo "=========================================="
        echo "STOPPED: error is not one of the mechanical classes. Needs a human."
        /usr/bin/grep -E "fatal error|^FAILED:|error:" "$LOG" | head -12
        echo "=========================================="
        exit 1
    fi

    echo "  regenerating vendor makefiles"
    (cd "$DEV" && ./extract-files.py "$DUMP" >/dev/null 2>&1) || { echo "extract-files failed"; exit 1; }
done
echo "hit max rounds ($MAX) without producing a zip"
exit 1
