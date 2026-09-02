#!/usr/bin/env bash
# resolve-hal-deps.sh — iterate the vendor build, resolving each
# "depends on undefined module" the right way:
#
#   * if <module>.so exists in the firmware dump  -> add it to proprietary-files.txt
#   * otherwise it is an AIDL/HIDL *interface* module (foo-V1-ndk, foo@1.0),
#     which is GENERATED from .aidl/.hal source Motorola does not publish, so it
#     can never be satisfied -> DROP the HAL that depends on it, along with its
#     .rc and vintf .xml
#
# That distinction is the whole trick: adding blobs blindly loops forever on the
# interface modules, and dropping blindly throws away HALs we actually need.
#
# Context: the vendor blob list was built by intersecting zeekr's (SM8475) list
# with this SM8635 firmware, which silently dropped 62 HAL binaries. add-missing-hals.sh
# put them back; this resolves the dependency fallout.
#
# USAGE: ./resolve-hal-deps.sh [max_rounds]

set -o pipefail
unset -f grep 2>/dev/null || true
G=/usr/bin/grep

TOP=$HOME/android/arcfox
DUMP=$HOME/android/firmware/W1UXS36H/extracted
LIST="$TOP/device/motorola/sm8635-common/proprietary-files.txt"
DEVLIST="$TOP/device/motorola/arcfox/proprietary-files.txt"
DEVDIR="$TOP/device/motorola/arcfox"
LOG=/tmp/arcfox-haldep.log
MAX="${1:-12}"

round=0
while [ "$round" -lt "$MAX" ]; do
    round=$((round + 1))
    echo "########## round $round ##########"

    # ANALYSIS ONLY. Every failure class handled below is a soong or kati error
    # raised while generating the ninja file -- none of them need the image built.
    # `mka nothing` runs product config + soong + kati and stops: ~11s per round
    # instead of ~90s for `mka vendorimage`. The image is built once at the end.
    (cd "$TOP" && source build/envsetup.sh >/dev/null 2>&1 \
        && breakfast arcfox >/dev/null 2>&1 \
        && LC_ALL=C USE_CCACHE=1 mka nothing) > "$LOG" 2>&1
    rc=$?

    if [ "$rc" -eq 0 ]; then
        echo "=== analysis clean after $round round(s) - building vendor.img for real ==="
        rm -f "$TOP/out/target/product/arcfox/vendor.img"
        (cd "$TOP" && source build/envsetup.sh >/dev/null 2>&1 \
            && breakfast arcfox >/dev/null 2>&1 \
            && LC_ALL=C USE_CCACHE=1 mka vendorimage) > "$LOG" 2>&1
        brc=$?
        if [ "$brc" -eq 0 ] && [ -s "$TOP/out/target/product/arcfox/vendor.img" ]; then
            ls -l "$TOP/out/target/product/arcfox/vendor.img" | awk '{print $5, $9}'
            echo "bin/hw installed: $(ls "$TOP/out/target/product/arcfox/vendor/bin/hw" 2>/dev/null | wc -l)"
            exit 0
        fi
        # Image build failed. Do NOT exit -- fall through to the handlers below,
        # because image-stage errors (host_init_verifier orphans, double installs)
        # are exactly the ones they know how to fix. Exiting here meant the
        # orphaned-init-script handler could never run.
        echo "  analysis clean, image build failed - falling through to handlers"
    fi

    # A blob listed in BOTH namespaces is a hard error:
    #   module "X" ... found in multiple namespaces(.../sm8635-common and .../arcfox)
    #
    # Resolve by dropping it from the DEVICE list, keeping the COMMON copy.
    # Direction matters and is not arbitrary: vendor/motorola/arcfox's
    # soong_namespace *imports* sm8635-common, and imports are one-way, so a
    # common module can never see an arcfox module. Removing the common copy
    # instead makes the dependency unsatisfiable, the next round re-adds it, and
    # the loop oscillates forever (observed: rounds 11-16 flip-flopping on
    # libEseUtils).
    mapfile -t DUPES < <($G -oE 'module "[^"]+" variant [^ ]+ found in multiple namespaces' "$LOG" \
        | sed -E 's/module "([^"]+)".*/\1/' | sort -u)
    if [ "${#DUPES[@]}" -gt 0 ]; then
        for m in "${DUPES[@]}"; do
            /usr/bin/sed -i "\|/${m}\.so\$|d; \|/${m}\.so;|d" "$DEVLIST"
            echo "  ~ DEDUPE $m (removed from arcfox, kept in sm8635-common)"
        done
        (cd "$DEVDIR" && ./extract-files.py "$DUMP" >/dev/null 2>&1)
        continue
    fi

    # AIDL VERSION CONFLICT:
    #   module "X" ... depends on multiple versions of the same aidl_interface:
    #     android.hardware.foo-V3-ndk-source, android.hardware.foo-V4-ndk-source
    # The blob was built against an older interface than Android 16 ships. There
    # is no way to satisfy both, so the HAL has to go -- together with its .rc
    # and its vintf .xml, because leaving a manifest entry for a HAL we no longer
    # ship makes the framework expect something that is not there.
    # (Some of these, e.g. drm clearkey and cas, are also built by AOSP from
    # source, so shipping our blob was wrong regardless.)
    mapfile -t VERCONF < <($G -oE 'module "[^"]+" variant [^ ]+: depends on multiple versions of the same aidl_interface' "$LOG" \
        | sed -E 's/module "([^"]+)".*/\1/' | sort -u)
    if [ "${#VERCONF[@]}" -gt 0 ]; then
        echo "=== AIDL VERSION CONFLICT — stopping for a human ==="
        echo
        echo "Do NOT just drop these HALs. Motorola's vendor is frozen at vendor API"
        echo "level 34, so its blobs legitimately link against OLDER interface versions"
        echo "than the platform builds from source. The firmware SHIPS those interface"
        echo "libraries (145 of them under vendor/lib64/*-V[0-9]-ndk.so) and the right"
        echo "fix is to add the needed one as a blob."
        echo
        echo "An earlier version of this script auto-dropped on this error and silently"
        echo "threw away wifi, health, sensors, wpa_supplicant and the display composer."
        echo
        for m in "${VERCONF[@]}"; do
            echo "  conflict: $m"
            b=$(find "$DUMP" -name "$m" -o -name "${m}.so" 2>/dev/null | head -1)
            if [ -n "$b" ]; then
                echo "    needs:  $(readelf -d "$b" 2>/dev/null | $G -oE '[A-Za-z0-9._]+-V[0-9]+-(ndk|cpp)\.so' | sort -u | tr '\n' ' ')"
            fi
        done
        echo
        echo "Add the listed interface libraries to proprietary-files.txt, re-run"
        echo "extract-files.py, then re-run this script."
        exit 2
    fi

    # PARTITION CONFLICT:
    #   module "X" ... partition is different: system(X) != vendor(prebuilt_X)
    # We shipped a vendor prebuilt of an AIDL interface that the PLATFORM already
    # builds at that same version. Ship the prebuilt only when the platform builds
    # a DIFFERENT version (e.g. vendor needs biometrics.common-V3 while the
    # platform builds V4). Same version -> drop our copy and use the platform's.
    # Two message shapes: with and without a "(created by ...)" clause.
    mapfile -t PARTCONF < <($G -oE 'module "[^"]+" variant "[^"]+"( \(created by [^)]*\))?: partition is different' "$LOG" \
        | sed -E 's/module "([^"]+)".*/\1/' | sort -u)
    if [ "${#PARTCONF[@]}" -gt 0 ]; then
        for m in "${PARTCONF[@]}"; do
            for L in "$LIST" "$DEVLIST"; do
                /usr/bin/sed -i "\|/${m}\.so\$|d; \|/${m}\.so;|d" "$L"
            done
            echo "  ~ UNSHIP $m (platform builds this same version)"
        done
        (cd "$DEVDIR" && ./extract-files.py "$DUMP" >/dev/null 2>&1)
        continue
    fi

    # ALREADY DEFINED BY A SOURCE MODULE:
    #   error: vendor/motorola/sm8635-common: MODULE.TARGET.ETC.X already defined
    #          by hardware/interfaces/cas/aidl/default
    # An in-tree source module already provides this file (AOSP interfaces, or an
    # imported hardware/qcom-caf tree). Shipping our blob duplicates it -- unship.
    mapfile -t ALREADY < <($G -oE 'MODULE\.TARGET\.[A-Z_]+\.[^ ]+ already defined' "$LOG" \
        | sed -E 's/MODULE\.TARGET\.[A-Z_]+\.([^ ]+) already defined/\1/' | sort -u)
    if [ "${#ALREADY[@]}" -gt 0 ]; then
        prog=0
        for m in "${ALREADY[@]}"; do
            for L in "$LIST" "$DEVLIST"; do
                before=$(wc -l < "$L")
                # the reported name has no extension; entries may carry .so/.rc/.xml
                /usr/bin/sed -i "\|/${m}\$|d; \|/${m};|d; \|/${m}\.so\$|d; \|/${m}\.so;|d" "$L"
                [ "$(wc -l < "$L")" -ne "$before" ] && prog=1
            done
            echo "  ~ UNSHIP $m (already provided by an in-tree source module)"
        done
        # Without this the loop can spin forever "unshipping" something whose
        # entry never matched (observed: libEGL_angle, listed as
        # vendor/lib64/egl/libEGL_angle.so, 7 rounds of no-ops).
        if [ "$prog" -eq 0 ]; then
            echo "  !! no list entry matched -- remove it by hand, then re-run"
            exit 3
        fi
        (cd "$DEVDIR" && ./extract-files.py "$DUMP" >/dev/null 2>&1)
        continue
    fi

    # DOUBLE INSTALL:
    #   error: overriding commands for target `.../vendor/etc/vintf/manifest/X.xml',
    #          previously defined at ...
    # extract_utils attaches a HAL's vintf manifest to the prebuilt module as a
    # vintf_fragment AND we also list the .xml in proprietary-files.txt, so it is
    # installed twice. Drop our copy; the module installs it.
    mapfile -t DOUBLE < <($G -oE "overriding commands for target .[^']*/([^/']+)'" "$LOG" \
        | sed -E "s|.*/([^/']+)'|\1|" | sort -u)
    if [ "${#DOUBLE[@]}" -gt 0 ]; then
        for m in "${DOUBLE[@]}"; do
            for L in "$LIST" "$DEVLIST"; do
                /usr/bin/sed -i "\|/${m}\$|d; \|/${m};|d" "$L"
            done
            echo "  ~ UNSHIP $m (installed twice: module vintf_fragment + our copy)"
        done
        (cd "$DEVDIR" && ./extract-files.py "$DUMP" >/dev/null 2>&1)
        continue
    fi

    # ORPHANED INIT SCRIPT (image stage, not analysis):
    #   host_init_verifier: .../foo.rc: invalid interface in service '...':
    #     Interface is not in the known set of hidl_interfaces: '...'
    # The .rc declares a HIDL/AIDL interface that nothing builds -- typically
    # because its service was dropped earlier, leaving the init script behind.
    # Drop the orphan .rc.
    mapfile -t ORPHANRC < <($G -oE 'host_init_verifier: [^:]*/([^/:]+\.rc):' "$LOG" \
        | sed -E 's|.*/([^/:]+\.rc):|\1|' | sort -u)
    if [ "${#ORPHANRC[@]}" -gt 0 ]; then
        for m in "${ORPHANRC[@]}"; do
            for L in "$LIST" "$DEVLIST"; do
                /usr/bin/sed -i "\|/${m}\$|d; \|/${m};|d" "$L"
            done
            echo "  ~ UNSHIP $m (orphaned init script: declares an interface nothing builds)"
        done
        (cd "$DEVDIR" && ./extract-files.py "$DUMP" >/dev/null 2>&1)
        continue
    fi

    # UNRESOLVED SYMBOLS (check_elf_file):
    #   vendor/.../hw/foo: error: Unresolved symbol: BAR
    # A build-time sanity check, not a runtime requirement: the blob resolves
    # these against libraries the stock image has and we do not ship (or do not
    # need). The blob manifest has an explicit opt-out, ;DISABLE_CHECKELF.
    mapfile -t ELFBAD < <($G -oE '^vendor/motorola/[a-z0-9-]+/proprietary/[^:]+: error: Unresolved symbol' "$LOG" \
        | sed -E 's|^vendor/motorola/[a-z0-9-]+/proprietary/||; s|: error: Unresolved symbol$||' | sort -u)
    if [ "${#ELFBAD[@]}" -gt 0 ]; then
        n=0
        for b in "${ELFBAD[@]}"; do
            esc=${b//./\\.}
            for L in "$LIST" "$DEVLIST"; do
                if $G -qE "^-?${esc}(;|\$)" "$L" && ! $G -qE "^-?${esc}.*DISABLE_CHECKELF" "$L"; then
                    /usr/bin/sed -i -E "s|^(-?${esc})(;.*)?\$|\\1\\2;DISABLE_CHECKELF|" "$L"
                    echo "  + DISABLE_CHECKELF $b"
                    n=$((n+1))
                fi
            done
        done
        if [ "$n" -gt 0 ]; then
            (cd "$DEVDIR" && ./extract-files.py "$DUMP" >/dev/null 2>&1)
            continue
        fi
    fi

    # SONAME MISMATCH:
    #   .../libfoo.so: error: DT_SONAME "libfoo-ndk.so" must be equal to the file
    #   name "libfoo.so"
    # extract_utils has a flag for exactly this; annotate rather than drop.
    mapfile -t SONAME < <($G -oE 'proprietary/[^:]+: error: DT_SONAME' "$LOG" \
        | sed -E 's|proprietary/||; s|: error: DT_SONAME||' | sort -u)
    if [ "${#SONAME[@]}" -gt 0 ]; then
        prog=0
        for b in "${SONAME[@]}"; do
            esc=${b//./\\.}
            for L in "$LIST" "$DEVLIST"; do
                before=$(md5sum "$L" | cut -d' ' -f1)
                /usr/bin/sed -i -E "s|^(-?${esc})(;.*)?\$|\\1\\2;FIX_SONAME|" "$L"
                [ "$(md5sum "$L" | cut -d' ' -f1)" != "$before" ] && prog=1
            done
            echo "  + FIX_SONAME $b"
        done
        if [ "$prog" -eq 1 ]; then
            (cd "$DEVDIR" && ./extract-files.py "$DUMP" >/dev/null 2>&1)
            continue
        fi
        echo "  !! SONAME entry not matched -- fix by hand"; exit 3
    fi

    mapfile -t PAIRS < <($G -oE '"[^"]+" depends on undefined module "[^"]+"' "$LOG" \
        | sed -E 's/"([^"]+)" depends on undefined module "([^"]+)"/\1\t\2/' | sort -u)

    if [ "${#PAIRS[@]}" -eq 0 ]; then
        echo "=== no undefined-module errors left; other failure ==="
        $G -m8 -E "error:|FAILED" "$LOG"
        exit 1
    fi

    added=0; dropped=0
    declare -A DROP_HAL=()
    for p in "${PAIRS[@]}"; do
        consumer="${p%%$'\t'*}"; missing="${p##*$'\t'}"
        so=$(find "$DUMP" -name "${missing}.so" 2>/dev/null | head -1)
        if [ -n "$so" ]; then
            rel="${so#$DUMP/}"
            if ! $G -qxF "$rel" "$LIST"; then
                printf '%s\n' "$rel" >> "$LIST"
                echo "  + blob   $rel   (for $consumer)"
                added=$((added + 1))
            fi
        else
            DROP_HAL["$consumer"]=1
            echo "  - DROP   $consumer   (needs generated interface '$missing')"
        fi
    done

    for hal in "${!DROP_HAL[@]}"; do
        # remove the binary/library plus its init rc and vintf manifest
        /usr/bin/sed -i -E "\|/${hal}(\.so)?(;.*)?$|d; \|/${hal}\.rc(;.*)?$|d; \|/${hal}\.xml(;.*)?$|d" "$LIST"
        dropped=$((dropped + 1))
    done

    echo "  round $round: +$added blobs, -$dropped HALs"
    [ $((added + dropped)) -eq 0 ] && { echo "no progress; stopping"; exit 1; }

    (cd "$DEVDIR" && ./extract-files.py "$DUMP" >/dev/null 2>&1) || { echo "extract-files failed"; exit 1; }
done
echo "hit max rounds ($MAX)"
exit 1
