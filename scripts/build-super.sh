#!/usr/bin/env bash
# build-super.sh — assemble super.img with lpmake, matching stock's geometry.
#
# Why not `mka superimage`: the build only knows about the partitions we build
# (system, system_ext, product, vendor). Stock's first-stage fstab ALSO requires
# vendor_dlkm and system_dlkm as logical partitions inside super:
#
#   vendor_dlkm  /vendor_dlkm  erofs ro  wait,slotselect,avb=vbmeta,logical,first_stage_mount
#   system_dlkm  /system_dlkm  erofs ro  wait,slotselect,avb=vbmeta,logical,first_stage_mount
#
# Both are `wait` + `first_stage_mount` with no `nofail`, so if they are absent
# first-stage init dies before console, adb or logging exist — a totally silent
# boot failure. `mka superimage` produced a super without them, and flashing it
# ERASED stock's copies. That also removed the 287 vendor_dlkm + 60 system_dlkm
# driver modules the whole prebuilt-GKI approach depends on.
#
# We do not build those modules, so we reuse Motorola's, extracted from the
# stock super. That is the same bargain already made for vendor_boot and dtbo.
#
# Geometry replicated from `lpdump` of the stock super:
#   device      super, 26616004608 bytes, first sector 2048
#   groups      mot_dp_group_a / mot_dp_group_b, max 26611810304 each
#   metadata    65536 bytes max, 3 slots
#
# Deliberately WITHOUT --virtual-ab, even though stock sets that header flag.
# Stock is a Virtual A/B device; our LineageOS build is not -- there is no
# VIRTUAL_AB anywhere in the device trees and no ro.virtual_ab* property in any
# built build.prop. Declaring virtual_ab_device makes first-stage init bring up
# SnapshotManager and resolve snapshot state out of /metadata. /metadata is
# erased and unformatted, so that lookup cannot succeed, and init aborts before
# it ever reaches the `formattable` metadata entry in the fstab.
#
# Evidence this is the failure point, gathered from a TWRP shell: after several
# boot attempts BOTH userdata and metadata still report "no fs signature", i.e.
# they were never formatted -- yet /metadata is
# `wait,check,formattable,first_stage_mount` and first-stage init formats it on
# mount failure. So init dies BEFORE that entry, while handling the logical
# partitions. Meanwhile the bootloader log shows a clean kernel handoff and all
# six logical partitions mount by hand in TWRP, so the images themselves and
# AVB are fine.
#
# Note the groups are each ~26.6GB, NOT < SUPER/2. That rule applies to classic
# A/B, where both slots are materialized at once. This is Virtual A/B: only one
# slot exists on disk, the other is a snapshot, so a group may span nearly the
# whole device.

set -o pipefail
TOP=$HOME/android/arcfox
OUT="$TOP/out/target/product/arcfox"
STOCK=$HOME/android/firmware/W1UXS36H/images
LPMAKE="$TOP/out/host/linux-x86/bin/lpmake"

[ -x "$LPMAKE" ] || { echo "lpmake missing — run a build first" >&2; exit 1; }

# ours
SYSTEM="$OUT/system.img"
SYSTEM_EXT="$OUT/system_ext.img"
PRODUCT="$OUT/product.img"
VENDOR="$OUT/vendor.img"
# Motorola's, kept as-is
VENDOR_DLKM="$STOCK/vendor_dlkm_a.img"
SYSTEM_DLKM="$STOCK/system_dlkm_a.img"

for f in "$SYSTEM" "$SYSTEM_EXT" "$PRODUCT" "$VENDOR" "$VENDOR_DLKM" "$SYSTEM_DLKM"; do
    [ -s "$f" ] || { echo "missing or empty: $f" >&2; exit 1; }
done

sz() { stat -c %s "$1"; }

SUPER_SIZE=26616004608
GROUP_SIZE=26611810304
OUTIMG="$OUT/super.img"

echo "=== component sizes ==="
printf '  %-14s %12s  %s\n' system      "$(sz "$SYSTEM")"      "ours"
printf '  %-14s %12s  %s\n' system_ext  "$(sz "$SYSTEM_EXT")"  "ours"
printf '  %-14s %12s  %s\n' product     "$(sz "$PRODUCT")"     "ours"
printf '  %-14s %12s  %s\n' vendor      "$(sz "$VENDOR")"      "ours"
printf '  %-14s %12s  %s\n' vendor_dlkm "$(sz "$VENDOR_DLKM")" "STOCK (drivers)"
printf '  %-14s %12s  %s\n' system_dlkm "$(sz "$SYSTEM_DLKM")" "STOCK (drivers)"

TOTAL=$(( $(sz "$SYSTEM") + $(sz "$SYSTEM_EXT") + $(sz "$PRODUCT") + $(sz "$VENDOR") \
        + $(sz "$VENDOR_DLKM") + $(sz "$SYSTEM_DLKM") ))
echo "  total: $TOTAL / group max $GROUP_SIZE"
[ "$TOTAL" -lt "$GROUP_SIZE" ] || { echo "does not fit" >&2; exit 1; }

echo
echo "=== lpmake ==="
"$LPMAKE" \
    --metadata-size 65536 \
    --metadata-slots 3 \
    --super-name super \
    --device super:$SUPER_SIZE \
    --group mot_dp_group_a:$GROUP_SIZE \
    --group mot_dp_group_b:$GROUP_SIZE \
    --partition system_a:readonly:$(sz "$SYSTEM"):mot_dp_group_a           --image system_a="$SYSTEM" \
    --partition system_ext_a:readonly:$(sz "$SYSTEM_EXT"):mot_dp_group_a   --image system_ext_a="$SYSTEM_EXT" \
    --partition product_a:readonly:$(sz "$PRODUCT"):mot_dp_group_a         --image product_a="$PRODUCT" \
    --partition vendor_a:readonly:$(sz "$VENDOR"):mot_dp_group_a           --image vendor_a="$VENDOR" \
    --partition vendor_dlkm_a:readonly:$(sz "$VENDOR_DLKM"):mot_dp_group_a --image vendor_dlkm_a="$VENDOR_DLKM" \
    --partition system_dlkm_a:readonly:$(sz "$SYSTEM_DLKM"):mot_dp_group_a --image system_dlkm_a="$SYSTEM_DLKM" \
    --partition system_b:readonly:0:mot_dp_group_b \
    --partition system_ext_b:readonly:0:mot_dp_group_b \
    --partition product_b:readonly:0:mot_dp_group_b \
    --partition vendor_b:readonly:0:mot_dp_group_b \
    --partition vendor_dlkm_b:readonly:0:mot_dp_group_b \
    --partition system_dlkm_b:readonly:0:mot_dp_group_b \
    --sparse \
    --output "$OUTIMG" || exit 1

echo
ls -l "$OUTIMG"
echo "flash with: fastboot flash super $OUTIMG"
