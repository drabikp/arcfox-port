#!/usr/bin/env bash
# build-super-mix.sh — build a super.img mixing OUR images with STOCK ones, to
# bisect which of our partitions breaks first-stage mount.
#
# Context: flashing stock's super while keeping our boot/init_boot/vbmeta boots
# stock Android fine, so the boot chain is proven good and the fault is inside
# our super. This script narrows down which image.
#
#   ./build-super-mix.sh vendor              # only vendor is ours, rest stock
#   ./build-super-mix.sh system system_ext   # those two ours, rest stock
#   ./build-super-mix.sh all                 # everything ours (the failing case)
#   ./build-super-mix.sh none                # everything stock (the known-good case)
#
# vendor_dlkm and system_dlkm are ALWAYS stock -- we never build them.
#
# Read the result with the zero-log progress indicator, from TWRP:
#   adb shell blkid /dev/block/by-name/metadata
# "no fs signature" => first-stage init never reached the metadata fstab entry,
# i.e. it died handling the logical partitions. Anything else => it got past
# them, so the swapped-in image mounts fine and the fault is elsewhere.
#
# That indicator works even when the mix cannot fully boot Android (e.g. our
# vendor under stock's system), because first-stage mount only cares that the
# images mount and pass AVB -- not about HAL compatibility.

set -o pipefail
TOP=$HOME/android/arcfox
OUT="$TOP/out/target/product/arcfox"
STOCK=$HOME/android/firmware/W1UXS36H/images
LPMAKE="$TOP/out/host/linux-x86/bin/lpmake"

[ -x "$LPMAKE" ] || { echo "lpmake missing" >&2; exit 1; }
[ $# -ge 1 ] || { echo "usage: $0 <all|none|partition...>" >&2; exit 1; }

case "$1" in
  all)  OURS="system system_ext product vendor" ;;
  none) OURS="" ;;
  *)    OURS="$*" ;;
esac

pick() {  # pick <partition> -> path, and report provenance on stderr
    local p="$1"
    for o in $OURS; do
        if [ "$o" = "$p" ]; then echo "$OUT/$p.img"; return; fi
    done
    echo "$STOCK/${p}_a.img"
}

sz() { stat -c %s "$1"; }

SUPER_SIZE=26616004608
GROUP_SIZE=26611810304
OUTIMG="$OUT/super.img"

declare -A SRC
for p in system system_ext product vendor; do SRC[$p]=$(pick "$p"); done
# vendor_dlkm / system_dlkm are now BUILT by us (from Motorola's own modules,
# lifted out of the stock images). Prefer ours: unlike stock's, they are covered
# by our vbmeta, which the fstab requires -- it mounts both with `avb=vbmeta`.
# Fall back to stock's if a build has not produced them.
# STOCK_DLKM=1 forces stock's dlkm images, to bisect them separately from vendor.
for p in vendor_dlkm system_dlkm; do
    if [ -n "$STOCK_DLKM" ]; then SRC[$p]="$STOCK/${p}_a.img"
    elif [ -s "$OUT/$p.img" ]; then SRC[$p]="$OUT/$p.img"
    else SRC[$p]="$STOCK/${p}_a.img"; fi
done

echo "=== composition ==="
for p in system system_ext product vendor vendor_dlkm system_dlkm; do
    f="${SRC[$p]}"
    [ -s "$f" ] || { echo "missing or empty: $f" >&2; exit 1; }
    case "$f" in
        "$OUT"/*) tag="OURS " ;;
        *)        tag="stock" ;;
    esac
    printf '  %-14s %-6s %12s  %s\n' "$p" "$tag" "$(sz "$f")" "$(basename "$f")"
done

ARGS=()
for p in system system_ext product vendor vendor_dlkm system_dlkm; do
    f="${SRC[$p]}"
    ARGS+=( --partition "${p}_a:readonly:$(sz "$f"):mot_dp_group_a" --image "${p}_a=$f" )
    ARGS+=( --partition "${p}_b:readonly:0:mot_dp_group_b" )
done

echo
echo "=== lpmake ==="
# --virtual-ab is BACK ON, to make our super metadata match stock's exactly
# (stock: version 10.2, "Header flags: virtual_ab_device"; without the flag
# lpmake emits 10.0 / no flags). It was removed earlier on the theory that
# first-stage init would look for snapshot state in an erased /metadata, but
# that test predated the fstab, vbmeta_system, dlkm, dtbo and vendor_boot fixes,
# so it was never a clean experiment. Retesting it now is cheap.
# Old note kept for context:
# No --virtual-ab: our build has no Virtual A/B support, and declaring it makes
# first-stage init try to resolve snapshot state out of an unformatted /metadata.
"$LPMAKE" \
    --metadata-size 65536 \
    --metadata-slots 3 \
    --super-name super \
    --virtual-ab \
    --device super:$SUPER_SIZE \
    --group mot_dp_group_a:$GROUP_SIZE \
    --group mot_dp_group_b:$GROUP_SIZE \
    "${ARGS[@]}" \
    --sparse \
    --output "$OUTIMG" 2>&1 | tail -3 || exit 1

echo
ls -l "$OUTIMG"
echo "flash: fastboot flash super $OUTIMG"
