#!/usr/bin/env bash
# restore-stock.sh — put arcfox back on stock Android 16 from the RSA firmware
# package. Run with the phone in fastboot (bootloader) mode.
#
#   ./restore-stock.sh              # boot-chain only (fast, usually enough)
#   ./restore-stock.sh --full       # every partition incl. super (slow, ~11GB)
#
# Why the boot chain alone is usually enough: a LineageOS attempt that fails to
# boot has only replaced boot / init_boot / vbmeta / recovery. The super
# partition (system, vendor, product, system_ext) is untouched until an OTA
# actually installs, so stock system images are still intact.

set -o pipefail
FB=/opt/android-sdk/platform-tools/fastboot
R="/run/media/peyko/<external-drive>/ProgramData/RSA/Download/RomFiles/ARCFOX_G_W1UXS36H.72_45_10_7_subsidy_DEFAULT_regulatory_DEFAULT_cid50_CFC.xml"

[ -d "$R" ] || { echo "stock firmware not found at $R" >&2; exit 1; }
command -v "$FB" >/dev/null || { echo "fastboot missing" >&2; exit 1; }

echo "waiting for a fastboot device..."
"$FB" wait-for-device 2>/dev/null
"$FB" devices

flash() {  # flash <partition> <file>
    [ -f "$R/$2" ] || { echo "  skip $1 (no $2)"; return; }
    printf '  %-14s ' "$1"
    "$FB" flash "$1" "$R/$2" 2>&1 | tail -1
}

echo
echo "=== restoring boot chain to stock W1UXS36H.72-45-10-7 ==="
flash boot        boot.img
flash init_boot   init_boot.img
flash vendor_boot vendor_boot.img
flash dtbo        dtbo.img
flash recovery    recovery.img
flash vbmeta      vbmeta.img
flash vbmeta_system vbmeta_system.img

if [ "${1:-}" = "--full" ]; then
    echo
    echo "=== full restore: super (23 sparse chunks, several minutes) ==="
    i=0
    while [ -f "$R/super.img_sparsechunk.$i" ]; do
        printf '  chunk %-3s ' "$i"
        "$FB" flash super "$R/super.img_sparsechunk.$i" 2>&1 | tail -1
        i=$((i + 1))
    done
    flash modem_a  radio.img
    flash bluetooth BTFM.bin
    flash dsp      dspso.bin
fi

echo
echo "=== done. Rebooting. ==="
"$FB" reboot 2>&1 | tail -1
echo
echo "If it still does not boot, re-run with --full, or use Motorola's Rescue"
echo "and Smart Assistant on Windows, which flashes this same package."
