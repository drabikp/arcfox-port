#!/bin/bash
# Restore arcfox to stock W1UXS36H.72-45-10-7, following Motorola's own
# flashfile.xml sequence exactly (order, partitions and erases all come from
# the package, not from guesswork).
#
# Run with the phone in BOOTLOADER mode (not fastbootd).
#   DRY=1 ./flash-stock.sh    # print the sequence, touch nothing
set -uo pipefail
R="${R:?set R to the RSA RomFiles directory, e.g. R=/mnt/win/ProgramData/RSA/Download/RomFiles/ARCFOX_G_W1UXS36H....xml}"
FB="${FB:-/opt/android-sdk/platform-tools/fastboot}"
SER="${SER:-}"
DRY="${DRY:-0}"
REBOOT="${REBOOT:-1}"
[ -n "$SER" ] && FBA=("$FB" -s "$SER") || FBA=("$FB")

fb(){ if [ "$DRY" = "1" ]; then echo "    would: fastboot $*"; else "${FBA[@]}" "$@"; fi; }

die(){ echo "FATAL: $*" >&2; exit 1; }

[ -d "$R" ] || die "firmware package not found at $R"
[ -x "$FB" ] || die "fastboot not executable at $FB"

echo "=== 0. liveness ==="
# `fastboot devices` only proves USB enumeration. Probe with a real getvar.
if [ "$DRY" != "1" ]; then
  prod=$("${FBA[@]}" getvar product 2>&1 | head -1)
  echo "  $prod"
  echo "$prod" | grep -qi arcfox || die "device is not arcfox (got: $prod) - refusing to flash"
  echo -n "  is-userspace (must be no; fastbootd cannot open super here): "
  "${FBA[@]}" getvar is-userspace 2>&1 | head -1
  "${FBA[@]}" getvar is-userspace 2>&1 | head -1 | grep -qi "no" || die "in fastbootd - reboot to the BOOTLOADER"
  echo -n "  max-sparse-size: "; "${FBA[@]}" getvar max-sparse-size 2>&1 | head -1
fi

echo "=== 1. enter Motorola flash mode ==="
fb oem fb_mode_set

echo "=== 2. boot chain + firmware (Motorola's order) ==="
while read -r part file; do
  [ -z "$part" ] && continue
  [ -f "$R/$file" ] || { echo "  SKIP $part ($file missing)"; continue; }
  printf '  %-14s <- %s\n' "$part" "$file"
  fb flash "$part" "$R/$file" || die "flashing $part failed"
done <<'EOF'
partition      gpt.bin
bootloader     bootloader.img
vbmeta         vbmeta.img
vbmeta_system  vbmeta_system.img
radio          radio.img
bluetooth      BTFM.bin
dsp            dspso.bin
logo           logo.bin
boot           boot.img
init_boot      init_boot.img
vendor_boot    vendor_boot.img
dtbo           dtbo.img
recovery       recovery.img
pvmfw          pvmfw.img
EOF

echo "=== 3. super (23 sparse chunks) ==="
i=0
while [ -f "$R/super.img_sparsechunk.$i" ]; do
  printf '  chunk %-3s ' "$i"
  fb flash super "$R/super.img_sparsechunk.$i" || die "super chunk $i failed - DO NOT REBOOT, re-run"
  i=$((i + 1))
done
echo "  $i chunks flashed"

echo "=== 4. erases (Motorola's list) ==="
for p in apdp apdpb debug_token carrier userdata metadata ddr; do
  printf '  erase %-12s ' "$p"
  fb erase "$p" 2>&1 | tail -1
done

echo "=== 5. leave flash mode ==="
fb oem fb_mode_clear
fb oem config unset console
fb oem config unset cmdl

echo
if [ "$REBOOT" = "1" ]; then
  echo "=== done. Rebooting to stock. ==="
  fb reboot
else
  echo "=== done. Staying in the bootloader (REBOOT=0). ==="
fi
