#!/usr/bin/env bash
# add-missing-hals.sh — append every vendor HAL file that stock ships and our
# build does not, to sm8635-common/proprietary-files.txt.
#
# WHY
# ---
# The vendor blob list was originally built by intersecting zeekr's list with
# this firmware. zeekr is SM8475, arcfox is SM8635, so anything named
# differently silently fell out of the intersection -- and 62 HAL service
# binaries went missing with no build error. Measured against stock:
#
#              ours   stock
#   bin/hw       15      76
#   etc/init     46     143
#   vintf man.   12     103
#   permissions   4      60
#   lib64/hw     23      58
#
# Missing includes android.hardware.boot-service.qti (boot-control, MANDATORY on
# an A/B device -- nothing can mark the slot successful without it, which
# matches slot-retry-count decrementing on every attempt) and the
# gatekeeper/keymint/weaver chain (without which vold cannot set up metadata
# encryption, so /data never mounts).
#
# This adds the files themselves. Their shared-library dependencies are NOT
# resolved here -- the build will report them as "depends on undefined module"
# and resolve-build-blobs.sh / build-loop.sh handle that loop.
#
# USAGE:
#   ./add-missing-hals.sh            # show what would be added
#   ./add-missing-hals.sh --apply    # actually append

set -o pipefail
DEV=$HOME/android/arcfox/device/motorola
OUT=$HOME/android/arcfox/out/target/product/arcfox/vendor
STOCK=$HOME/android/firmware/W1UXS36H/extracted/vendor
LIST="$DEV/sm8635-common/proprietary-files.txt"

[ -d "$OUT" ]   || { echo "no built vendor tree at $OUT (run 'mka vendorimage')" >&2; exit 1; }
[ -d "$STOCK" ] || { echo "no stock vendor dump at $STOCK" >&2; exit 1; }

# Directories worth syncing toward stock. Deliberately NOT syncing app/,
# priv-app/, framework/ or overlay/ -- those are Motorola's UI payload, which is
# exactly the spyware surface this ROM exists to remove.
#
# Widened from the original HAL-only set after the HAL restoration alone did not
# fix the boot: our vendor was still 1,180 files short of stock (382 in lib64,
# 199 in bin, 118 in etc, 74 in firmware). We ship 126 init scripts but only 259
# of stock's 458 bin executables, so many services reference binaries that do not
# exist. Stock's vendor boots; ours does not; closing the gap is the most direct
# route to finding out what is load-bearing.
DIRS=(
    bin bin/hw
    lib lib64 lib/hw lib64/hw lib64/camera lib64/soundfx lib64/egl lib/egl
    etc etc/init etc/init/hw etc/vintf etc/vintf/manifest etc/permissions etc/seccomp_policy
    etc/display etc/wifi etc/sensors etc/camera etc/media_codecs etc/audio
    firmware
)

# Files that must NEVER be re-added, with the reason. Without this the script
# resurrects them on every run and the resolver has to rediscover the conflict.
EXCLUDE=(
    # AOSP builds these from source; shipping a blob of the same name drags two
    # AIDL versions into the graph.
    android.hardware.drm-service.clearkey
    android.hardware.cas-service.example
    android.hardware.cas-service.xml
    # NOTE: display composer/allocator are NOT excluded any more -- they are
    # shipped as stock blobs on purpose. Excluding them while nothing built them
    # is exactly how the device ended up with no display HAL at all.
    # ANGLE (libEGL_angle, libGLESv1_CM_angle, libGLESv2_angle): AOSP builds
    # these from external/angle. Shipping the vendor copies collides.
    libEGL_angle.so
    libGLESv1_CM_angle.so
    libGLESv2_angle.so
    libfeature_support_angle.so
    # Built from source by hardware/qcom-caf/wlan (namespace already imported).
    libwifi-hal-qcom.so
    # --- now BUILT FROM SOURCE (see sm8635-common/common.mk) -----------------
    # These were blobs whose .rc was never listed in proprietary-files.txt, so
    # init never started them. The Soong modules carry their own init_rc and
    # vintf_fragments. Re-adding the blob would collide with the source module
    # ("already defined by an in-tree source module"), so they must stay out.
    # is_excluded() also matches "<name>.rc" and "<name>.xml".
    android.hardware.boot-service.qti
    boot-service.qti                     # its vintf frag is boot-service.qti.xml
    android.hardware.health-service.qti
    android.hardware.usb-service.qti
    android.hardware.usb.gadget-service.qti
    vendor.qti.hardware.memtrack-service
    vendor.qti.hardware.vibrator.service
    vendor.qti.qspa-service
    vndservice
    vndservicemanager
    # Files proven to be installed twice (module attaches them) or provided by an
    # in-tree source module. Harvested from resolver logs rather than rediscovered
    # one ~90s build round at a time.
    android.hardware.audio.service.rc
    android.hardware.health-service.qti.rc
    # sensors-multihal.xml is SHIPPED again (see proprietary-files.txt): without
    # it nothing declares android.hardware.sensors, and the multihal service
    # aborts on addService with STATUS_UNKNOWN_TRANSACTION, 184 times.
    android.hardware.sensors-service-multihal.rc
    android.hardware.usb-service.qti.rc
    android.hardware.wifi-service.rc
    android.hardware.wifi-service.xml
    android.hardware.wifi.hostapd.xml
    android.hardware.wifi.supplicant.xml
    bluetooth_audio.xml
    checkpoint_gc
    gpu_counter_producer
    libEGL_angle
    memtrack_qti.rc
    memtrack_qti.xml
    nfc-service-nxp.rc
    # NOTE: power.xml must NOT be excluded -- see proprietary-files.txt. Excluding
    # it left android.hardware.power.IPower/default undeclared in VINTF, and
    # HintManagerService NPEs on that, killing system_server on every boot.
    qspa_vendor.rc
    rkp_factory_extraction_tool64
    vendor.qti.hardware.vibrator.service.rc
    vendor.qti.hardware.vibrator.service.xml
    vendor.qti.qspa-service.rc
    vendor.qti.qspa-service.xml
    vndservicemanager.rc
    # Declares a HIDL interface nothing builds -> host_init_verifier rejects it.
    motorola.hardware.health.storage@1.0-service.rc
    vendor.qti.hardware.wifi.wifilearner@1.0-service.rc
)

is_excluded() {
    local b="$1"
    for e in "${EXCLUDE[@]}"; do
        case "$b" in "$e"|"$e".rc|"$e".xml) return 0 ;; esac
    done
    return 1
}

TMP=$(mktemp)
for d in "${DIRS[@]}"; do
    [ -d "$STOCK/$d" ] || continue
    while IFS= read -r f; do
        b=$(basename "$f")
        [ -e "$OUT/$d/$b" ] && continue                       # already shipped
        is_excluded "$b" && continue                          # never ship (see EXCLUDE)
        grep -qxF "vendor/$d/$b" "$LIST" 2>/dev/null && continue  # already listed
        echo "vendor/$d/$b"
    done < <(find "$STOCK/$d" -maxdepth 1 -type f | sort)
done > "$TMP"

n=$(wc -l < "$TMP")
echo "=== $n files missing from our vendor image ==="
for d in "${DIRS[@]}"; do
    c=$(grep -c "^vendor/$d/" "$TMP" 2>/dev/null || true)
    printf '  %-22s %s\n' "$d" "${c:-0}"
done

if [ "${1:-}" = "--apply" ]; then
    {
        echo ""
        echo "# --- HALs missing from the original zeekr-derived intersection -------------"
        echo "# 62 HAL service binaries and their init/vintf/permissions files were absent,"
        echo "# including android.hardware.boot-service.qti (boot-control, mandatory on A/B)"
        echo "# and the gatekeeper/keymint/weaver chain needed for /data encryption."
        echo "# Added by add-missing-hals.sh."
        cat "$TMP"
    } >> "$LIST"
    echo
    echo "appended $n entries to $LIST (now $(wc -l < "$LIST") lines)"
else
    echo
    echo "sample:"; head -12 "$TMP" | sed 's/^/  /'
    echo "(re-run with --apply to append)"
fi
rm -f "$TMP"
