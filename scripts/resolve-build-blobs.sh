#!/usr/bin/env bash
# resolve-build-blobs.sh — iteratively resolve soong "undefined module" errors
# by adding the corresponding blob from the extracted firmware.
#
#   ./resolve-build-blobs.sh [max_rounds]
#
# Why this exists: the blob manifest was deliberately seeded from zeekr's
# known-good lists plus arcfox-specific hardware, and ~2000 further vendor
# blobs were held back in blobs/split/tier2-vendor-ondemand.txt. Adding all of
# them up front would silence real errors. Instead the build names what it
# actually needs, one dependency at a time, and this loop feeds them in.
#
# Each round:
#   1. run soong far enough to produce the ninja file
#   2. scrape `depends on undefined module "X"` errors
#   3. map X -> a real path in the extracted firmware (X.so, or X verbatim)
#   4. append to the DEVICE or COMMON manifest depending on where soong says
#      the missing module lives
#   5. regenerate vendor makefiles, repeat
#
# Stops when soong bootstrap succeeds, when a round resolves nothing new (so a
# human is needed), or at max_rounds.
#
# NOTE for agent shells: Claude Code injects a `grep` shell function that routes
# to ugrep and breaks AOSP's lunch (it does `echo $1 | grep "-"`). This script
# unsets it. See FINDINGS.md.

# NOTE: deliberately NOT `set -u`. AOSP's build/envsetup.sh reads unset
# variables in several places, so sourcing it under `set -u` aborts the shell
# silently and every round reports "no undefined-module errors" with empty
# output. Cost me a debugging round.
set -o pipefail
unset -f grep 2>/dev/null || true

MAX="${1:-12}"
TOP=$HOME/android/arcfox
DEV="$TOP/device/motorola/arcfox"
COM="$TOP/device/motorola/sm8635-common"
DUMP=$HOME/android/firmware/W1UXS36H/extracted
INV=$HOME/workspace/motorola-lineageos/blobs/device-inventory.txt
LOG=$HOME/workspace/motorola-lineageos/blobs/resolve-log.txt

[ -f "$INV" ] || { echo "missing $INV" >&2; exit 1; }
: > "$LOG"

# Resolve a soong module name to a path present in the firmware.
# extract_utils names blob modules after the file basename minus .so.
resolve_path() {
    local mod="$1"
    /usr/bin/grep -m1 -E "/${mod}\.so$" "$INV" && return 0
    /usr/bin/grep -m1 -E "/${mod}$" "$INV" && return 0
    return 1
}

round=0
while [ "$round" -lt "$MAX" ]; do
    round=$((round + 1))
    echo "=========== round $round ===========" | tee -a "$LOG"

    out=$(cd "$TOP" && source build/envsetup.sh >/dev/null 2>&1 \
          && breakfast arcfox >/dev/null 2>&1 \
          && LC_ALL=C mka bacon 2>&1)
    rc=$?

    # Use bash pattern matching, NOT `echo "$out" | grep -q`. Under
    # `set -o pipefail`, grep -q exits as soon as it matches, echo dies of
    # SIGPIPE, and the pipeline reports FAILURE even though the match
    # succeeded. That inverted every round with real dependency errors into
    # "NON-dependency reason" and stopped the loop early.
    if [[ "$out" != *"undefined module"* ]]; then
        if [[ "$out" == *"soong bootstrap failed"* ]]; then
            echo "soong failed for a NON-dependency reason. Human needed:" | tee -a "$LOG"
            echo "$out" | /usr/bin/grep -E "^error:|error: " | head -10 | tee -a "$LOG"
        else
            echo "no undefined-module errors this round (rc=$rc)" | tee -a "$LOG"
            echo "$out" | tail -20 | tee -a "$LOG"
        fi
        break
    fi

    # "X" depends on undefined module "Y".  -> we need Y.
    # The following line tells us which namespace Y lives in.
    added=0
    while IFS=$'\t' read -r mod consumer_file; do
        [ -n "$mod" ] || continue
        path=$(resolve_path "$mod") || {
            echo "  UNRESOLVED $mod (not in firmware dump)" | tee -a "$LOG"
            continue
        }
        # Route by where the CONSUMER lives, not by where the missing module
        # happens to be found. A module in vendor/motorola/sm8635-common cannot
        # see vendor/motorola/arcfox (and must not — common must never depend on
        # a device). So a dependency of a common-tree blob has to land in the
        # common manifest. Getting this backwards makes the same error repeat
        # forever while the loop insists it "added" something.
        case "$consumer_file" in
            *sm8635-common*) target="$COM/proprietary-files.txt"; label=common ;;
            *)               target="$DEV/proprietary-files.txt"; label=device ;;
        esac
        # A blob must live in exactly ONE manifest (soong rejects a module found
        # in two namespaces), and it must live in a namespace the CONSUMER can
        # read. device can see common; common canNOT see device. So when the
        # consumer is in common but the blob currently sits in device, MOVE it
        # rather than skip — skipping loops forever, and duplicating trips
        # "found in multiple namespaces".
        if /usr/bin/grep -qxF "$path" "$target"; then
            continue
        fi
        if [ "$label" = common ] && /usr/bin/grep -qxF "$path" "$DEV/proprietary-files.txt"; then
            /usr/bin/sed -i "\\|^$(printf '%s' "$path" | /usr/bin/sed 's/[.[\*^$/]/\\&/g')$|d" "$DEV/proprietary-files.txt"
            printf '%s\n' "$path" >> "$COM/proprietary-files.txt"
            echo "  ~ MOVED device->common  $path   (consumer $mod is in common)" | tee -a "$LOG"
            added=$((added + 1))
            continue
        fi
        if [ "$label" = device ] && /usr/bin/grep -qxF "$path" "$COM/proprietary-files.txt"; then
            # Consumer is in device and blob is in common — device CAN read
            # common, so this is fine. Nothing to do.
            continue
        fi
        printf '%s\n' "$path" >> "$target"
        echo "  + $label  $path   (for module $mod)" | tee -a "$LOG"
        added=$((added + 1))
    done < <(echo "$out" | awk '
        # error: <consumer Android.bp>:LINE:COL: "X" depends on undefined module "Y".
        # Emit Y plus the FILE the error was reported against, which identifies
        # the consuming namespace.
        /depends on undefined module/ {
            match($0, /undefined module "[^"]+"/)
            mod = substr($0, RSTART+18, RLENGTH-19)
            match($0, /error: [^:]+:/)
            src = substr($0, RSTART+7, RLENGTH-8)
            print mod "\t" src
        }
    ' | sort -u)

    if [ "$added" -eq 0 ]; then
        echo "resolved nothing new this round — stopping" | tee -a "$LOG"
        echo "$out" | /usr/bin/grep -E "undefined module" | head -10 | tee -a "$LOG"
        break
    fi

    echo "  regenerating vendor makefiles ($added new blob(s))" | tee -a "$LOG"
    (cd "$DEV" && ./extract-files.py "$DUMP" >/dev/null 2>&1) \
        || { echo "extract-files failed" | tee -a "$LOG"; break; }
done

echo
echo "=== summary ==="
/usr/bin/grep -c '^  + ' "$LOG" 2>/dev/null | xargs echo "blobs added:"
echo "device manifest: $(/usr/bin/grep -cvE '^\s*(#|$)' "$DEV/proprietary-files.txt") entries"
echo "common manifest: $(/usr/bin/grep -cvE '^\s*(#|$)' "$COM/proprietary-files.txt") entries"
echo "log: $LOG"
