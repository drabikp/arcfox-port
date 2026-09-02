#!/usr/bin/env bash
# capture-contract.sh — record the arcfox hardware contract from stock Android.
#
# Motorola Razr 50 Ultra / Razr+ 2024 (arcfox, SM8635 "pineapple").
#
# The phone must be booted into STOCK ANDROID (not TWRP) with USB debugging on.
# Everything here is read-only. Nothing is flashed, nothing is modified.
#
# Run it once per hinge position so the three captures can be diffed:
#
#   ./capture-contract.sh closed     # lid shut, outer display active
#   ./capture-contract.sh half       # ~90-110 deg, hinge at the BOTTOM, like a
#                                    #   tiny laptop -> HALF_OPENED_MAIN
#   ./capture-contract.sh open       # fully open, inner display active
#   ./capture-contract.sh tent       # same fold angle as half, but flipped so
#                                    #   the crease points UP and it rests on
#                                    #   both outer edges -> TENT
#
# Orientation matters, not just angle. TENT and HALF_OPENED_MAIN can share a
# hinge angle; what separates them is hinge_posture value[1], which reads 1.00
# in tent and 0.00 otherwise.
#
# The point of the diff: which display ID is default in each position, what the
# hall sensor reports, and where the hinge-angle thresholds sit. Those three
# facts are exactly what fold/device_state_configuration.xml and
# fold/display_layout_configuration.xml need.
#
# NOTE ON "closed": adb over USB keeps working with the lid shut, but the screen
# state changes. Don't touch the phone between plugging in and capturing, or you
# will record a display that woke up because you moved it.

set -uo pipefail

STATE="${1:-}"
case "$STATE" in
  closed|half|open|tent) ;;
  *)
    echo "usage: $0 {closed|half|open|tent}" >&2
    exit 2
    ;;
esac

OUT="$(cd "$(dirname "$0")" && pwd)/contract/$STATE"
COMMON="$(cd "$(dirname "$0")" && pwd)/contract/common"
mkdir -p "$OUT" "$COMMON"

if ! command -v adb >/dev/null 2>&1; then
  echo "adb not found. On Arch: sudo pacman -S --needed android-tools" >&2
  exit 1
fi

# Fail loudly rather than writing a directory full of empty files.
if [ -z "$(adb devices | awk 'NR>1 && $2=="device"')" ]; then
  echo "No authorized device. Check the USB-debugging prompt on the phone." >&2
  adb devices -l >&2
  exit 1
fi

say() { printf '  %-34s' "$1"; }
ok()  { echo "ok"; }

# grab <outfile> <adb shell command...>
# Writes stderr into the file too: a permission denial is itself a finding worth
# keeping, and a silently empty file is not.
grab() {
  local dest="$1"; shift
  say "$(basename "$dest")"
  adb shell "$@" >"$dest" 2>&1 || true
  ok
}

echo "=== arcfox hardware contract: state=$STATE ==="
echo
echo "State-dependent captures -> contract/$STATE/"

# --- The three that actually decide the fold config -------------------------
# Display topology per hinge position. Which physical display is default here?
grab "$OUT/dumpsys-display.txt"        dumpsys display
grab "$OUT/surfaceflinger-displays.txt" dumpsys SurfaceFlinger --display-id
# DeviceStateManager's own view. Service name has moved between releases, so try
# the modern one and fall back.
grab "$OUT/device-state.txt"           "dumpsys device_state || cmd device_state print-states || echo UNAVAILABLE"
# Live sensor values: the hall-effect sensor and the hinge-angle sensor report
# here, and their names must match the fold XML exactly.
grab "$OUT/sensorservice.txt"          dumpsys sensorservice
# Cheap, greppable summary of what is awake right now.
grab "$OUT/display-power.txt"          "dumpsys power | head -80"

echo
echo "Static captures -> contract/common/  (identical across states; last run wins)"

# --- Identity and platform --------------------------------------------------
grab "$COMMON/getprop.txt"             "getprop | sort"
grab "$COMMON/uname.txt"               uname -a
grab "$COMMON/cpuinfo.txt"             "cat /proc/cpuinfo"
# Settles the open question of which kernel tree is correct. Decide from
# ro.board.platform and the kernel version string, never from a repo name.
grab "$COMMON/platform.txt"            "getprop ro.board.platform; getprop ro.hardware; getprop ro.build.fingerprint; getprop ro.vendor.build.security_patch"

# --- HAL surface: what the vendor image actually provides -------------------
grab "$COMMON/lshal.txt"               lshal
grab "$COMMON/services.txt"            service list
grab "$COMMON/packages-vendor.txt"     "pm list packages -s"

# --- Camera: IDs, and whether the 2x telephoto is independently exposed ------
grab "$COMMON/media-camera.txt"        dumpsys media.camera
grab "$COMMON/camera-ids.txt"          "cmd media.camera get-camera-ids || echo UNAVAILABLE"

# --- Input: hall sensor and hinge show up as input devices ------------------
grab "$COMMON/getevent.txt"            getevent -il

# --- Partition layout, for later flashing sanity ----------------------------
grab "$COMMON/partitions.txt"          "ls -l /dev/block/by-name/ 2>&1"

echo
echo "Pulling vendor config trees (may take a moment)"
for path in /vendor/etc/vintf /vendor/etc/camera /vendor/etc/sensors; do
  say "$(basename "$path")"
  adb pull "$path" "$COMMON/" >/dev/null 2>&1 && ok || echo "skipped (absent or denied)"
done

echo
echo "Done. state=$STATE"
echo
echo "Next: rerun in the other hinge positions, then diff the display topology:"
echo "  diff contract/closed/dumpsys-display.txt contract/open/dumpsys-display.txt"
echo
echo "Before publishing, run ./scrub-check.sh — getprop and the vintf tree can"
echo "carry the IMEI, serial, and build fingerprints tied to your handset."
