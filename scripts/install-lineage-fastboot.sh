#!/usr/bin/env bash
# install-lineage-fastboot.sh — install LineageOS on arcfox WITHOUT recovery.
#
# Run with the phone in BOOTLOADER fastboot (power off, then Volume Down + Power).
# NOT fastbootd — our recovery's userspace fastboot has no working USB.
#
# Why this exists: our recovery boots and renders but never enumerates on USB,
# so `adb sideload` is impossible. Recovery is not actually required. Bootloader
# fastboot can write `super` directly (restore-stock.sh --full already does this
# with stock's chunks), and `super` is where system/vendor/product/system_ext
# live. So we build our own super.img and push the whole set from the bootloader.
#
# We flash a COHERENT SET. That matters: the two earlier "No valid operating
# system found" failures came from mixing our boot chain with stock's system.
# Here boot, init_boot, super and vbmeta all come from the same build.
#
# vendor_boot, dtbo, vendor_dlkm and system_dlkm stay STOCK by design — we ship
# the prebuilt GKI kernel and reuse Motorola's driver modules. Our vbmeta is
# built with `--flags 3` (HASHTREE_DISABLED | VERIFICATION_DISABLED), so the
# stock/ours mix is not hash-checked.
#
# Escape hatch if anything goes wrong: ./restore-stock.sh --full

set -o pipefail
FB=/opt/android-sdk/platform-tools/fastboot
OUT=$HOME/android/arcfox/out/target/product/arcfox

command -v "$FB" >/dev/null || { echo "fastboot missing" >&2; exit 1; }
[ -f "$OUT/super.img" ] || { echo "no super.img — run: mka superimage" >&2; exit 1; }

echo "waiting for a BOOTLOADER fastboot device..."
"$FB" wait-for-device 2>/dev/null

# fastbootd reports "yes"; the real bootloader reports "no". Only the bootloader
# can write super and the boot chain, and only it has working USB on this device.
IS_USERSPACE=$("$FB" getvar is-userspace 2>&1 | /usr/bin/grep -oE "^is-userspace: *\w+" | awk '{print $2}')
if [ "$IS_USERSPACE" = "yes" ]; then
    echo "ERROR: this is fastbootd (userspace), not the bootloader." >&2
    echo "Power the phone off fully, then hold Volume Down + Power." >&2
    exit 1
fi
"$FB" devices

flash() {  # flash <partition> <file> [extra fastboot args...]
    local part="$1" img="$2"; shift 2
    [ -f "$img" ] || { echo "  skip $part (no $(basename "$img"))"; return 0; }
    printf '  %-14s ' "$part"
    "$FB" "$@" flash "$part" "$img" 2>&1 | tail -1
}

echo
echo "=== 1/3 boot chain (ours) ==="
flash boot      "$OUT/boot.img"
flash init_boot "$OUT/init_boot.img"

echo
echo "=== 2/3 super (~1.5GB sparse, a few minutes) ==="
flash super "$OUT/super.img"

echo
echo "=== 3/3 vbmeta (verification disabled) ==="
# Do NOT pass --disable-verity/--disable-verification here. Those make fastboot
# rewrite the header before sending, and on this image it fails with
# "Failed to find AVB_MAGIC at offset: 0" — a spurious error (xxd confirms AVB0
# is at offset 0), which silently skips the flash entirely. They are redundant
# anyway: the build already sets --flags 3, verified by parsing the header.
flash vbmeta        "$OUT/vbmeta.img"
flash vbmeta_system "$OUT/vbmeta_system.img"

echo
echo "=== userdata ==="
# Encryption keys change with the ROM, so stock userdata cannot be decrypted and
# the first boot will hang or bootloop without this. `misc` is write-protected on
# this device, so do not be surprised if userdata is refused too.
"$FB" -w 2>&1 | tail -3

echo
echo "=== done — rebooting ==="
"$FB" reboot 2>&1 | tail -1
echo
echo "First boot of a new ROM can take 5-10 minutes. If it does not come up:"
echo "  ./restore-stock.sh --full"
