#!/usr/bin/env bash
# boot-cycle.sh — unattended build → flash → boot-test cycle.
#
# Assumes the phone is in BOOTLOADER fastboot and that a failed boot returns it
# there by itself (observed: fast failures drop back in ~30-60s, the long hang
# after ~320s). If the device stops coming back on its own, this stops and asks
# for a power-cycle -- that is the one thing it cannot do itself.
#
# Order matters: vendor.img must be built BEFORE inject-vendor-mountpoints.sh,
# which creates the /vendor mount points the fstab needs and rebuilds the image.
# Skipping that step silently reintroduces a known-fatal defect.

set -o pipefail
unset -f grep 2>/dev/null || true
G=/usr/bin/grep
TOP=$HOME/android/arcfox
WS=$HOME/workspace/motorola-lineageos
O="$TOP/out/target/product/arcfox"
FB=/opt/android-sdk/platform-tools/fastboot
A=/opt/android-sdk/platform-tools/adb

say() { echo "[$(date +%H:%M:%S)] $*"; }

# --- liveness probe: `fastboot devices` only proves USB enumeration ----------
wait_bootloader() {
    local i out
    # The previous cycle ends in TWRP (it reboots there to harvest evidence), so
    # try to get to the bootloader over adb first -- no human required.
    if [ -n "$($A devices 2>/dev/null | $G <device-serial>)" ]; then
        say "device is in adb/recovery -- rebooting to bootloader"
        $A reboot bootloader >/dev/null 2>&1
        sleep 15
    fi
    for i in $(seq 1 "${1:-60}"); do
        out=$(timeout 8 "$FB" getvar product 2>&1 | head -1)
        case "$out" in *product:*) say "bootloader responsive"; return 0 ;; esac
        # retry the adb route in case it landed back in recovery
        if [ $((i % 10)) -eq 0 ] && [ -n "$($A devices 2>/dev/null | $G <device-serial>)" ]; then
            $A reboot bootloader >/dev/null 2>&1
        fi
        sleep 5
    done
    return 1
}

say "=== 0. validate device-tree XML ==="
# Cheap gate in front of a ~15 minute build. A double hyphen inside an XML comment
# is a known trap here and has still broken the build three times; aapt2 reports it
# with no line number, and a broken vintf fragment installs fine and only fails at
# runtime. Two seconds here beats finding out at minute fourteen.
"$WS/validate-xml.sh" || { say "XML VALIDATION FAILED — fix before building"; exit 1; }

say "=== 1. build system + vendor + vbmeta ==="
# systemimage is NOT optional here: the boot logger installs to /system/bin, so
# a cycle that rebuilds only vendorimage silently reflashes the PREVIOUS
# logger and every "improved logging" change is a no-op. Cost is small -- the
# logger is a copied file, so this is a repack, not a compile.
(cd "$TOP" && source build/envsetup.sh >/dev/null 2>&1 && breakfast arcfox >/dev/null 2>&1 \
    && LC_ALL=C USE_CCACHE=1 mka systemimage vendorimage vendorbootimage vbmetaimage vbmetasystemimage) > /tmp/bc-build.log 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then say "BUILD FAILED"; $G -m6 -E "error:|FAILED" /tmp/bc-build.log; exit 1; fi
say "build ok"

say "=== 2. inject vendor mount points (must follow vendorimage) ==="
"$WS/inject-vendor-mountpoints.sh" > /tmp/bc-mnt.log 2>&1
for d in firmware_mnt dsp bt_firmware fsg; do
    [ -d "$O/vendor/$d" ] || { say "MOUNT POINT MISSING: /vendor/$d"; exit 1; }
done
say "mount points present"

say "=== 3. assemble super ==="
"$WS/build-super-mix.sh" all > /tmp/bc-super.log 2>&1 || { say "SUPER FAILED"; tail -5 /tmp/bc-super.log; exit 1; }
ls -l "$O/super.img" | awk '{print "  super:", $5, "bytes"}'

say "=== 4. flash ==="
wait_bootloader 60 || { say "NEEDS PHYSICAL: bootloader not responding — power ~20s then VolDown+Power"; exit 2; }
# Capture A/B slot health while we are definitely IN fastboot. The BOOTED path at
# the end cannot do this -- by then the device is in Android and `fastboot getvar`
# just prints "< waiting for any device >", which reads like a failure and isn't.
# If slot-successful ever stays "no" while retry-count walks down to 0, the
# bootloader will mark the slot unbootable and the device stops booting.
say "--- slot health (a) ---"
timeout 10 "$FB" getvar slot-successful:a   2>&1 | $G -m1 slot-successful   || true
timeout 10 "$FB" getvar slot-retry-count:a  2>&1 | $G -m1 slot-retry-count  || true
timeout 10 "$FB" getvar slot-unbootable:a   2>&1 | $G -m1 slot-unbootable   || true
timeout 500 "$FB" flash super        "$O/super.img"        2>&1 | tail -1
# vendor_boot MUST be flashed too. Its bootconfig carries androidboot.* -- most
# importantly androidboot.selinux. A permissive flag added as a diagnostic and
# then reverted in the BUILD stayed live on the DEVICE for several cycles,
# because this script only ever flashed super+vbmeta, so every one of those runs
# was silently permissive while the tree said enforcing. Flash it every cycle so
# the device state cannot drift from the build.
timeout 120 "$FB" flash vendor_boot  "$O/vendor_boot.img"  2>&1 | tail -1
timeout 30  "$FB" flash vbmeta       "$O/vbmeta.img"       2>&1 | tail -1
timeout 30  "$FB" flash vbmeta_system "$O/vbmeta_system.img" 2>&1 | tail -1
timeout 30  "$FB" erase metadata 2>&1 | tail -1
timeout 60  "$FB" erase userdata 2>&1 | tail -1
timeout 20  "$FB" --set-active=a 2>&1 | tail -1

say "=== 5. boot test ==="
timeout 20 "$FB" reboot 2>&1 | tail -1
booted=0
# 75x8s = 600s, not 400s. The logger's give-up is ITERATION-based
# (GIVE_UP_AFTER=18), not time-based, and each iteration costs two full
# `logcat -b all -d` dumps plus dmesg plus /proc forensics. In bc20 iteration 17
# landed at uptime 254s (~16s/iteration by the end) and the reboot fired at
# ~271s -- comfortably inside 400s. But a NOISIER boot makes each iteration
# slower (bc16-era qcrild restarted 84x in 410s vs 52x here), and if the give-up
# slides past the window the host sees no fastboot and scores it BOOTED. That is
# the most likely way bc14 and bc16 earned unconfirmed passes. 600s buys margin.
for i in $(seq 1 75); do
    sleep 8
    s=$($A devices 2>/dev/null | $G <device-serial> | awk '{print $2}')
    u=$(lsusb 2>/dev/null | $G -oE "22b8:[0-9a-f]+|18d1:[0-9a-f]+" | head -1)
    say "t=$((i*8))s adb=${s:-none} usb=${u:-none}"
    if [ -n "$s" ] && [ "$s" != "recovery" ]; then say "*** ADB UP: $s ***"; booted=1; break; fi
    if [ "$u" = "22b8:2e82" ]; then say "*** ANDROID (MTP) — BOOTED ***"; booted=1; break; fi
    if [ "$u" = "22b8:2e80" ] && [ "$i" -gt 6 ]; then say "*** dropped to bootloader — FAILED ***"; break; fi
done

say "=== 6. verdict ==="
# A booted ROM sitting at the setup wizard shows NEITHER adb nor MTP: USB
# debugging is off until the user enables it, and MTP does not come up until
# setup completes. So "no adb, no usb" is NOT failure on its own.
#
# The reliable negative signal is the boot logger: it reboots the device INTO
# THE BOOTLOADER if sys.boot_completed never becomes 1. So if the device never
# appeared as fastboot during the window, it booted. This exact case was first
# hit when the ROM finally booted to the wizard and the script still said FAILED.
#
# THIS VERDICT IS INFERENCE, NOT MEASUREMENT -- treat it as provisional. It says
# "booted" from the ABSENCE of a signal, and there are three ways that absence
# lies: the give-up can slide past the window (see the loop bound above); the
# give-up's first two routes both go through init, which is exactly what is
# wedged in this failure mode; and its last resort `echo b > /proc/sysrq-trigger`
# resets into ANDROID, not the bootloader, so the host sees nothing either way.
# bc14 and bc16 were both scored BOOTED here with no independent confirmation.
#
# The logger now writes a BOOTSTATE line into every snapshot header, so the
# NEXT harvest settles it as fact. Until then this is a hypothesis.
if [ "$booted" -eq 0 ] && [ "${u:-none}" != "22b8:2e80" ]; then
    # One 8s probe is not enough to conclude "no bootloader" -- a single dropped
    # USB enumeration would fake a pass. Require three consecutive failures.
    fbseen=0
    for p in 1 2 3; do
        timeout 8 "$FB" getvar product 2>&1 | $G -q 'product:' && { fbseen=1; break; }
        sleep 4
    done
    if [ "$fbseen" -eq 0 ]; then
        say "*** NO BOOTLOADER AFTER ${i}x8s AND NO SELF-REBOOT (3 probes) ***"
        say "*** PROVISIONAL PASS: consistent with a boot, but not proof. ***"
        say "*** Confirm from the next harvest's BOOTSTATE line before believing it. ***"
        exit 0
    fi
fi
if [ "$booted" -eq 1 ]; then
    say "BOOTED. Checking slot state (must become successful or reboots burn retries)"
    timeout 10 "$FB" getvar slot-successful:a 2>&1 | head -1 || true
    exit 0
fi

# Failure: harvest evidence without needing a human.
if wait_bootloader 20; then
    timeout 10 "$FB" getvar slot-retry-count:a 2>&1 | head -1
    say "rebooting to TWRP to read the boot reason"
    timeout 20 "$FB" reboot recovery 2>&1 | tail -1
    for i in $(seq 1 20); do
        sleep 7
        [ -n "$($A devices 2>/dev/null | $G <device-serial>)" ] && break
    done
    say "--- ro.boot.bootreason ---";  $A shell getprop ro.boot.bootreason 2>&1 | head -1
    say "--- last reboot reason (misc BCB) ---"
    $A shell 'dd if=/dev/block/by-name/misc bs=1 count=2048 2>/dev/null | strings | head -5' 2>&1
    say "--- metadata magic (10 20 f5 f2 = first-stage reached it) ---"
    $A shell 'dd if=/dev/block/by-name/metadata bs=1 skip=1024 count=4 2>/dev/null | od -An -tx1' 2>&1
    say "--- BOOT LOGGER OUTPUT (ramdump partition, 128 MiB) ---"
    # The logger writes fixed 4 MiB slots into `ramdump`: slot 0 is the EARLY
    # snapshot (taken once, at the first opportunity), slot 1+i is iteration i
    # in full. Nothing is tailed, so this is a timeline rather than two samples
    # -- which is what it takes to see a service that is alive but silent.
    rm -f /tmp/arcfox-boot-*.txt
    $A shell 'dd if=/dev/block/by-name/ramdump bs=1M count=128 2>/dev/null' 2>/dev/null \
        > /tmp/arcfox-ramdump.raw
    for s in $(seq 0 31); do
        out=$( [ "$s" -eq 0 ] && echo /tmp/arcfox-boot-early.txt \
                              || printf '/tmp/arcfox-boot-iter%02d.txt' $((s-1)) )
        dd if=/tmp/arcfox-ramdump.raw bs=4096 skip=$((s*1024)) count=1024 2>/dev/null \
            | tr -d '\000' > "$out"
        [ -s "$out" ] || rm -f "$out"
    done
    if [ -s /tmp/arcfox-boot-early.txt ]; then
        say "EARLY $(wc -c < /tmp/arcfox-boot-early.txt) B -> /tmp/arcfox-boot-early.txt"
        n=$(ls /tmp/arcfox-boot-iter*.txt 2>/dev/null | wc -l)
        say "$n iteration snapshots -> /tmp/arcfox-boot-iterNN.txt"
        last=$(ls /tmp/arcfox-boot-iter*.txt 2>/dev/null | tail -1)
        say "--- keymint/qseecom/TEE chain, from the EARLY snapshot ---"
        $G -iE "keymint|qseecom|strongbox|tee|weaver|gatekeeper" /tmp/arcfox-boot-early.txt | head -40
        [ -n "$last" ] && { say "--- same, from the LAST snapshot ($last) ---"
            $G -iE "keymint|qseecom|keystore|Failed to construct" "$last" | tail -30; }
    else
        say "ramdump empty -- logger never ran (init died before post-fs)"
        say "trying the kpan fallback"
        $A shell 'dd if=/dev/block/by-name/kpan bs=4096 count=2048 2>/dev/null' 2>/dev/null \
            | tr -d '\000' > /tmp/arcfox-boot-early.txt
        [ -s /tmp/arcfox-boot-early.txt ] && say "kpan fallback: $(wc -c < /tmp/arcfox-boot-early.txt) B"
    fi
else
    say "NEEDS PHYSICAL: device did not return to bootloader on its own"
    exit 2
fi
exit 1
