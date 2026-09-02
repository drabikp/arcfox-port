#!/usr/bin/env bash
# build-blob-manifest.sh — generate a CANDIDATE proprietary-files.txt for arcfox
# by intersecting zeekr's known-good blob lists with an extracted firmware tree.
#
#   ./build-blob-manifest.sh <extracted-dir>
#
# Example:
#   ./build-blob-manifest.sh ~/android/firmware/W1UXS36H/extracted
#
# The extracted tree comes from extract-firmware.sh. Do NOT source the inventory
# from `adb shell find`: the shell SELinux domain cannot stat most of /vendor and
# cannot read /vendor/firmware at all, so an on-device inventory silently
# undercounts by ~3x. See blobs/INVALID.md for the measurements.
#
# Why zeekr as reference: it is the Motorola Razr 40 Ultra, a working LineageOS
# port on a sibling flip from the same OEM. Its lists encode which files a real
# Motorola foldable port needed. NOTE the SoC differs (sm8475 vs sm8635), so the
# SoC-common list transfers far worse than the device list. Both rates are
# reported separately for exactly that reason.
#
# Output is a STARTING POINT, not a finished manifest.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-}"
OUT="$ROOT/blobs"
REF="$OUT/.ref"

[ -d "$SRC" ] || { echo "usage: $0 <extracted-dir>" >&2; exit 2; }
for p in vendor system system_ext product; do
  [ -d "$SRC/$p" ] || { echo "missing $SRC/$p — run extract-firmware.sh first" >&2; exit 1; }
done

rm -f "$OUT"/{candidates.txt,absent.txt,extras-hal.txt,extras-moto.txt,SUMMARY.txt,device-inventory.txt}
mkdir -p "$OUT" "$REF"

# --- 1. Reference lists -----------------------------------------------------
echo "==> fetching zeekr reference blob lists"
curl -sfL "https://raw.githubusercontent.com/AmeChanRain/device_motorola_zeekr/lineage-22.2/proprietary-files.txt" \
  -o "$REF/device.txt" || { echo "fetch failed" >&2; exit 1; }
curl -sfL "https://raw.githubusercontent.com/AmeChanRain/device_motorola_sm8475-common/master/proprietary-files.txt" \
  -o "$REF/common.txt" || { echo "fetch failed" >&2; exit 1; }
echo "    device: $(wc -l < "$REF/device.txt") lines, common: $(wc -l < "$REF/common.txt") lines"

# LineageOS extract_utils format: [-]path[:destination][;OPTIONS]
# '-' means needs blob fixup, ':' remaps destination, ';' carries options.
# We want the SOURCE path only.
norm() {
  grep -vE '^\s*(#|$)' "$1" \
    | sed -E 's/^-//; s/;.*$//; s/\|.*$//' \
    | awk -F: '{print $1}' \
    | sed -E 's/[[:space:]]+$//' \
    | sort -u
}
norm "$REF/device.txt" > "$REF/device-paths.txt"
norm "$REF/common.txt" > "$REF/common-paths.txt"
sort -u "$REF/device-paths.txt" "$REF/common-paths.txt" > "$REF/all-paths.txt"

# --- 2. Inventory the extracted tree ----------------------------------------
# Path shapes differ per partition. system.img is system-as-root, so its real
# content sits at system/system/... and must collapse to system/... to match
# manifest convention. The others are flat.
echo "==> inventorying extracted firmware"
{
  find "$SRC/vendor"     -type f -printf 'vendor/%P\n'      2>/dev/null
  find "$SRC/system_ext" -type f -printf 'system_ext/%P\n'  2>/dev/null
  find "$SRC/product"    -type f -printf 'product/%P\n'     2>/dev/null
  find "$SRC/system/system" -type f -printf 'system/%P\n'   2>/dev/null
} | sort -u > "$OUT/device-inventory.txt"
echo "    files: $(wc -l < "$OUT/device-inventory.txt")"

# --- 3. Intersect, reporting the two reference lists separately -------------
echo "==> intersecting"
comm -12 "$REF/all-paths.txt"    "$OUT/device-inventory.txt" > "$REF/present.txt"
comm -23 "$REF/all-paths.txt"    "$OUT/device-inventory.txt" > "$OUT/absent.txt"
DEV_HIT=$(comm -12 "$REF/device-paths.txt" "$OUT/device-inventory.txt" | wc -l)
COM_HIT=$(comm -12 "$REF/common-paths.txt" "$OUT/device-inventory.txt" | wc -l)
DEV_TOT=$(wc -l < "$REF/device-paths.txt")
COM_TOT=$(wc -l < "$REF/common-paths.txt")

# --- 4. Rebuild the manifest preserving zeekr's annotations -----------------
# A bare path list throws away the '-' fixup markers and ';' options zeekr
# learned the hard way. Re-emit the ORIGINAL line for every surviving path.
echo "==> rebuilding manifest with annotations preserved"
{
  echo "# Proprietary files for motorola arcfox (Razr 50 Ultra / Razr+ 2024)"
  echo "#"
  echo "# CANDIDATE LIST - generated, not curated. Review before use."
  echo "# Source firmware: $(grep -m1 'Build Fingerprint' "$(dirname "$SRC")/build-info.txt" 2>/dev/null | sed 's/.*: //')"
  echo "# Reference: AmeChanRain/device_motorola_zeekr (+ sm8475-common)"
  echo "#"
  echo "# Annotations (-prefix, ;OPTIONS) carried over from zeekr verbatim."
  echo "# They were correct for sm8475; verify them for sm8635."
  echo "#"
  awk 'NR==FNR {keep[$0]=1; next}
       /^[[:space:]]*(#|$)/ {next}
       { line=$0
         p=line; sub(/^-/,"",p); sub(/;.*$/,"",p); sub(/\|.*$/,"",p)
         split(p,a,":"); p=a[1]; sub(/[[:space:]]+$/,"",p)
         if (p in keep) print line }' \
      "$REF/present.txt" "$REF/device.txt" "$REF/common.txt"
} > "$OUT/candidates.txt"

# --- 5. What zeekr never had ------------------------------------------------
# arcfox-specific hardware (different camera stack, the fold sensors) will be
# absent from zeekr's lists entirely. Surface high-signal areas only.
echo "==> scanning for arcfox blobs zeekr never listed"
grep -E '^vendor/(bin/hw|lib|lib64)/' "$OUT/device-inventory.txt" \
  | comm -23 - "$REF/all-paths.txt" > "$OUT/extras-hal.txt"
grep -E '^vendor/(firmware|etc/camera|etc/sensors)/' "$OUT/device-inventory.txt" \
  | comm -23 - "$REF/all-paths.txt" > "$OUT/extras-firmware.txt"
grep -iE 'moto|mmi' "$OUT/device-inventory.txt" \
  | comm -23 - "$REF/all-paths.txt" > "$OUT/extras-moto.txt"

# --- 6. Summary -------------------------------------------------------------
pct() { [ "$2" -gt 0 ] && echo "$(( $1 * 100 / $2 ))%" || echo "n/a"; }
{
  echo "arcfox candidate blob manifest"
  echo "source: $SRC"
  echo
  echo "reference match rates (these are NOT equivalent):"
  printf "  zeekr DEVICE list (Razr-specific)  : %5s / %-5s  %s\n" \
    "$DEV_HIT" "$DEV_TOT" "$(pct "$DEV_HIT" "$DEV_TOT")"
  printf "  zeekr COMMON list (sm8475 SoC)     : %5s / %-5s  %s\n" \
    "$COM_HIT" "$COM_TOT" "$(pct "$COM_HIT" "$COM_TOT")"
  echo "  The common list is for a DIFFERENT SoC (sm8475 vs sm8635)."
  echo "  A low rate there is expected and not a problem."
  echo
  echo "candidates.txt entries : $(grep -cvE '^\s*(#|$)' "$OUT/candidates.txt")"
  echo "absent.txt entries     : $(wc -l < "$OUT/absent.txt")"
  echo
  echo "arcfox files zeekr never listed:"
  printf "  vendor HAL bins/libs : %s\n" "$(wc -l < "$OUT/extras-hal.txt")"
  printf "  firmware/camera/sens : %s\n" "$(wc -l < "$OUT/extras-firmware.txt")"
  printf "  motorola-named       : %s\n" "$(wc -l < "$OUT/extras-moto.txt")"
  echo
  echo "NEXT"
  echo "  1. Split candidates.txt: SoC-generic vendor/ paths belong in the"
  echo "     common tree, device-specific ones (camera tuning, fold, display)"
  echo "     in device/motorola/arcfox."
  echo "  2. extras-firmware.txt matters most. /vendor/firmware is invisible"
  echo "     from adb, so nothing in it could have been found on-device."
  echo "  3. Expect the first build to fail on something this missed. Normal."
} > "$OUT/SUMMARY.txt"

cat "$OUT/SUMMARY.txt"
