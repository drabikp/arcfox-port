#!/usr/bin/env bash
# split-manifest.sh — turn blobs/candidates.txt plus the extras into per-tree
# proprietary-files.txt drafts, tiered by confidence.
#
#   ./split-manifest.sh
#
# Requires build-blob-manifest.sh to have run first.
#
# THREE TIERS, because "every file on the vendor partition" is not a blob list.
#
#   Tier 1  zeekr-derived, split device vs common using zeekr's OWN split.
#           A working Motorola foldable port already decided which paths are
#           SoC-generic and which are device-specific; reuse that judgment
#           rather than inventing heuristics. Start the build from this.
#
#   Tier 2  vendor/ paths zeekr never listed. Real arcfox hardware lives here
#           (telephoto calibration, lanai sensor configs, Motorola display and
#           touch HALs). Add on demand as the build complains, EXCEPT the
#           camera and sensor tuning which is almost certainly required.
#
#   Tier 3  product/, system/, system_ext/ Motorola packages. DELIBERATELY
#           EXCLUDED. These are the preinstalled Motorola and Google apps and
#           framework pieces — precisely the payload this project exists to
#           remove. Listed so the exclusion is a decision on record, not an
#           oversight.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
B="$ROOT/blobs"
REF="$B/.ref"
OUT="$B/split"

for f in "$B/device-inventory.txt" "$REF/device-paths.txt" "$REF/common-paths.txt"; do
  [ -f "$f" ] || { echo "missing $f — run build-blob-manifest.sh first" >&2; exit 1; }
done
mkdir -p "$OUT"

INV="$B/device-inventory.txt"

# --- Tier 1: reuse zeekr's device/common split ------------------------------
comm -12 "$REF/device-paths.txt" "$INV" > "$OUT/.t1-device"
comm -12 "$REF/common-paths.txt" "$INV" > "$OUT/.t1-common-raw"
# A path in both zeekr lists belongs to the device tree there; do not duplicate.
comm -23 "$OUT/.t1-common-raw" "$OUT/.t1-device" > "$OUT/.t1-common"

# --- Tier 2 / 3: paths zeekr never listed -----------------------------------
sort -u "$REF/device-paths.txt" "$REF/common-paths.txt" > "$OUT/.zeekr-all"
comm -23 "$INV" "$OUT/.zeekr-all" > "$OUT/.extras"

# Tier 3 first: anything outside vendor/ and odm/ is app or framework payload.
grep -vE '^(vendor|odm)/' "$OUT/.extras" > "$OUT/tier3-excluded-apps.txt"

# Tier 2: vendor/odm only, split into "almost certainly needed" and "on demand".
grep -E '^(vendor|odm)/' "$OUT/.extras" > "$OUT/.t2-all"

# Device-specific calibration and panel/touch hardware. These are per-handset
# and cannot come from any other device's list.
grep -E '^vendor/(etc/camera|etc/sensors|firmware/CAMERA)|panel|touch|imgtuner|_tele|golden' \
  "$OUT/.t2-all" > "$OUT/tier2-device-hardware.txt"
comm -23 "$OUT/.t2-all" "$OUT/tier2-device-hardware.txt" > "$OUT/tier2-vendor-ondemand.txt"

# --- Emit manifests, preserving zeekr annotations where they exist ----------
emit() {  # emit <pathlist> <zeekr-source-a> <zeekr-source-b>
  awk 'NR==FNR {keep[$0]=1; next}
       /^[[:space:]]*(#|$)/ {next}
       { line=$0
         p=line; sub(/^-/,"",p); sub(/;.*$/,"",p); sub(/\|.*$/,"",p)
         split(p,a,":"); p=a[1]; sub(/[[:space:]]+$/,"",p)
         if (p in keep) { print line; delete keep[p] } }' "$@"
}

FP=$(grep -m1 'Build Fingerprint' \
     $HOME/android/firmware/W1UXS36H/build-info.txt 2>/dev/null | sed 's/.*: //')

{
  echo "# Proprietary files for motorola arcfox — DEVICE tree"
  echo "# device/motorola/arcfox/proprietary-files.txt"
  echo "#"
  echo "# Tier 1 draft. Paths that zeekr (Razr 40 Ultra) keeps in its DEVICE"
  echo "# tree and that exist on arcfox. Annotations carried from zeekr verbatim;"
  echo "# they were correct for sm8475, verify for sm8635."
  echo "# Source firmware: $FP"
  echo "#"
  emit "$OUT/.t1-device" "$REF/device.txt" "$REF/common.txt"
} > "$OUT/proprietary-files-device.txt"

{
  echo "# Proprietary files for motorola sm8635 — COMMON tree"
  echo "# device/motorola/sm8635-common/proprietary-files.txt"
  echo "#"
  echo "# Tier 1 draft. Paths that zeekr keeps in its sm8475-common tree and"
  echo "# that exist on arcfox. NOTE the SoC differs (sm8475 -> sm8635); these"
  echo "# survived the intersection but library ABI and naming still need review."
  echo "# Source firmware: $FP"
  echo "#"
  emit "$OUT/.t1-common" "$REF/common.txt" "$REF/device.txt"
} > "$OUT/proprietary-files-common.txt"

# --- Report -----------------------------------------------------------------
n() { wc -l < "$1" | tr -d ' '; }
e() { grep -cvE '^\s*(#|$)' "$1"; }

{
  echo "arcfox blob manifest split"
  echo "source firmware: $FP"
  echo
  echo "TIER 1 — start the build from these"
  printf "  device tree  : %5s entries  -> proprietary-files-device.txt\n" "$(e "$OUT/proprietary-files-device.txt")"
  printf "  common tree  : %5s entries  -> proprietary-files-common.txt\n" "$(e "$OUT/proprietary-files-common.txt")"
  echo
  echo "TIER 2 — arcfox hardware zeekr never had"
  printf "  device hw    : %5s  -> tier2-device-hardware.txt  (camera/sensor tuning, panel, touch)\n" "$(n "$OUT/tier2-device-hardware.txt")"
  printf "  on demand    : %5s  -> tier2-vendor-ondemand.txt   (add when the build asks)\n" "$(n "$OUT/tier2-vendor-ondemand.txt")"
  echo
  echo "TIER 3 — deliberately EXCLUDED"
  printf "  moto/google apps and framework : %5s  -> tier3-excluded-apps.txt\n" "$(n "$OUT/tier3-excluded-apps.txt")"
  echo "  These are product/, system/ and system_ext/ packages: the preinstalled"
  echo "  Motorola and Google payload. Removing them is the point of the project."
  echo "  Excluded on purpose. Review only if something legitimately needs one."
  echo
  echo "NEXT"
  echo "  1. Drop the two Tier 1 files into their trees and run extract-files.py"
  echo "     against ~/android/firmware/W1UXS36H/extracted."
  echo "  2. Append tier2-device-hardware.txt to the DEVICE manifest. The"
  echo "     telephoto calibration (aec_golden_tele.bin, dual_golden_tele.bin)"
  echo "     and lanai_* sensor configs have no equivalent on any other handset."
  echo "  3. Leave tier2-vendor-ondemand.txt alone until a build failure names"
  echo "     something in it. Adding 1000 blobs speculatively hides real errors."
} > "$OUT/SPLIT-SUMMARY.txt"

rm -f "$OUT"/.t1-common-raw "$OUT"/.zeekr-all "$OUT"/.t2-all "$OUT"/.extras
cat "$OUT/SPLIT-SUMMARY.txt"
