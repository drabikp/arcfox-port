#!/usr/bin/env bash
# inject-vendor-mountpoints.sh — create the /vendor mount-point directories that
# the fstab needs, directly in the vendor staging tree, then rebuild vendor.img.
#
# WHY THIS EXISTS
# ---------------
# The device fstab mounts four PHYSICAL partitions onto directories INSIDE the
# vendor image:
#
#   /vendor/firmware_mnt  <- modem      wait,slotselect
#   /vendor/dsp           <- dsp        wait,slotselect
#   /vendor/bt_firmware   <- bluetooth  wait,slotselect
#   /vendor/fsg           <- fsg        wait,slotselect
#
# Stock's vendor image ships these as empty directories. Ours had none of them
# (1,394 files vs stock's 3,021), so all four mounts targeted a non-existent
# path. They are blocking `wait` mounts, and the kernel cmdline points
# firmware_class.path at /vendor/firmware_mnt/image, so modem/DSP firmware is
# unreachable as well.
#
# This was isolated by bisecting super with build-super-mix.sh:
#   all stock                                  -> BOOTS
#   all stock + our vendor_dlkm/system_dlkm    -> BOOTS
#   stock system/system_ext/product + our vendor -> FAILS, and fails FAST
#                                                   (~56s to bootloader), which
#                                                   is what a failed mount_all
#                                                   looks like rather than a hang
#
# WHY NOT PRODUCT_COPY_FILES
# --------------------------
# Android 16's soong filesystem generator refuses to install into a new
# top-level vendor directory:
#   error: build/soong/fsgen/Android.bp: module
#     "vendor-..._mountpoints_firmware_mnt-vendor_firmware_mnt-0" ...
#     Path is outside directory: ../firmware_mnt
# Reproduced with a hidden `.keep`, a plain `keep`, and with source directories
# mirroring the destination layout. A proper fix likely needs a soong module or
# an fs_config entry; this script is the stop-gap.
#
# USAGE: run AFTER `mka vendorimage`, then rebuild the image and super:
#   ./inject-vendor-mountpoints.sh
#   ./build-super-mix.sh all

set -o pipefail
TOP=$HOME/android/arcfox
STAGE="$TOP/out/target/product/arcfox/vendor"
OUTIMG="$TOP/out/target/product/arcfox/vendor.img"

[ -d "$STAGE" ] || { echo "no vendor staging dir at $STAGE — run 'mka vendorimage' first" >&2; exit 1; }

# rfs is not in the fstab but stock ships it; harmless and keeps us closer to stock.
for d in firmware_mnt dsp bt_firmware fsg rfs; do
    if [ -d "$STAGE/$d" ]; then
        echo "  already present: /vendor/$d"
    else
        mkdir -p "$STAGE/$d" && echo "  created: /vendor/$d"
    fi
done

echo
echo "=== rebuilding vendor.img (deleting it forces ninja to regenerate) ==="
rm -f "$OUTIMG"
cd "$TOP" || exit 1
unset -f grep 2>/dev/null || true
# shellcheck disable=SC1091
source build/envsetup.sh >/dev/null 2>&1
breakfast arcfox >/dev/null 2>&1
LC_ALL=C USE_CCACHE=1 mka vendorimage vbmetaimage 2>&1 | tail -3

echo
echo "=== verifying the directories survived into the image ==="
for d in firmware_mnt dsp bt_firmware fsg rfs; do
    printf '  /vendor/%-14s ' "$d"
    [ -d "$STAGE/$d" ] && echo present || echo MISSING
done
ls -l "$OUTIMG" 2>/dev/null | awk '{print $5, $9}'
