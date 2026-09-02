#!/usr/bin/env bash
# extract-firmware.sh — unpack a Motorola RSA firmware package into mountable
# partition images and an extracted filesystem tree.
#
# This is the blob source. The device itself cannot provide one: the `shell`
# SELinux domain cannot stat most of /vendor and cannot read /vendor/firmware at
# all, `fastboot fetch` is refused on user builds, and no public dump of arcfox
# exists. Motorola's Rescue and Smart Assistant downloads the full package to
# flash it and leaves it on disk, which is where this comes from.
#
#   ./extract-firmware.sh <romfiles-dir> [output-dir]
#
# Example:
#   ./extract-firmware.sh \
#     "/run/media/peyko/<external-drive>/ProgramData/RSA/Download/RomFiles/ARCFOX_G_W1UXS36H.72_45_10_7_subsidy_DEFAULT_regulatory_DEFAULT_cid50_CFC.xml" \
#     ~/android/firmware/W1UXS36H
#
# Needs: android-tools (simg2img, lpunpack), erofs-utils (fsck.erofs).
# Reads the source read-only. Writes only under output-dir.

set -uo pipefail

SRC="${1:-}"
OUT="${2:-$HOME/android/firmware/extracted}"

[ -d "$SRC" ] || { echo "usage: $0 <romfiles-dir> [output-dir]" >&2; exit 2; }

for t in simg2img lpunpack fsck.erofs; do
  command -v "$t" >/dev/null 2>&1 || {
    echo "$t missing. Install: sudo pacman -S --needed android-tools erofs-utils" >&2
    exit 1
  }
done

mkdir -p "$OUT"/{images,extracted}

# --- 0. Record what this is -------------------------------------------------
echo "==> source: $SRC"
if compgen -G "$SRC/*.info.txt" >/dev/null; then
  grep -E "Build Fingerprint|Android Version|Build Id|Modem Version" "$SRC"/*.info.txt \
    | sed 's/^/    /'
  cp "$SRC"/*.info.txt "$OUT/build-info.txt" 2>/dev/null
fi

# --- 1. Merge the sparse chunks ---------------------------------------------
# ORDER MATTERS AND GLOB ORDER IS WRONG. A shell glob sorts sparsechunk.10
# before sparsechunk.2, which silently produces a corrupt super.img: lpunpack
# still emits partitions of the right SIZE, because sizes come from metadata at
# the head of the image, but their CONTENTS are scrambled. Nothing warns you.
#
# `sort -t. -kN -n` is NOT safe here either. Motorola's directory name contains
# dots (W1UXS36H.72_45_10_7..., CFC.xml), so dot-delimited field numbers do not
# line up and sort silently falls back to lexicographic. Split on the literal
# marker 'sparsechunk.' and sort on the integer that follows it.
if [ ! -f "$OUT/images/super.img" ]; then
  echo "==> merging super.img sparse chunks (numeric order)"
  mapfile -t CHUNKS < <(find "$SRC" -maxdepth 1 -name 'super.img_sparsechunk.*' \
                        | awk -F'sparsechunk\\.' '{printf "%d\t%s\n", $2, $0}' \
                        | sort -n | cut -f2-)
  [ "${#CHUNKS[@]}" -gt 0 ] || { echo "no sparsechunks found in $SRC" >&2; exit 1; }

  # Verify the ordering is a contiguous 0..N-1 run before spending minutes on it.
  EXPECT=0
  for c in "${CHUNKS[@]}"; do
    idx="${c##*sparsechunk.}"
    if [ "$idx" != "$EXPECT" ]; then
      echo "    chunk order broken: expected index $EXPECT, got $idx" >&2
      echo "    refusing to merge; super.img would be silently corrupt" >&2
      exit 1
    fi
    EXPECT=$((EXPECT + 1))
  done
  echo "    ${#CHUNKS[@]} chunks verified contiguous: 0..$((EXPECT - 1))"
  echo "    first=$(basename "${CHUNKS[0]}") last=$(basename "${CHUNKS[-1]}")"

  simg2img "${CHUNKS[@]}" "$OUT/images/super.img" || exit 1
  echo "    super.img: $(du -h "$OUT/images/super.img" | cut -f1)"
else
  echo "==> super.img already present, skipping merge"
fi

# --- 2. Split super into logical partitions ---------------------------------
# A/B device: lpunpack emits <name>_a and <name>_b. Slot A is what is running.
echo "==> unpacking super.img into logical partitions"
lpunpack "$OUT/images/super.img" "$OUT/images/" || exit 1
ls -la "$OUT/images/"*.img | awk '{printf "    %-28s %s\n", $NF, $5}'

# --- 3. Extract the filesystems ---------------------------------------------
# These are erofs (confirmed on-device: /vendor, /product, /system_ext all
# mount as erofs). fsck.erofs --extract walks the image without mounting, so no
# root and no loop device needed.
echo "==> extracting filesystems"
for p in vendor product system system_ext odm; do
  for cand in "$OUT/images/${p}_a.img" "$OUT/images/${p}.img"; do
    [ -f "$cand" ] || continue
    dest="$OUT/extracted/$p"
    if [ -d "$dest" ]; then
      echo "    $p already extracted, skipping"
      break
    fi
    printf '    %-12s ' "$p"
    mkdir -p "$dest"
    if fsck.erofs --extract="$dest" --overwrite "$cand" >/dev/null 2>&1; then
      echo "ok  ($(find "$dest" -type f | wc -l) files)"
    else
      echo "FAILED (not erofs? try: 7z x $cand)"
    fi
    break
  done
done

# --- 4. Summary -------------------------------------------------------------
echo
echo "=== extracted ==="
for p in vendor product system system_ext odm; do
  [ -d "$OUT/extracted/$p" ] && printf "  %-12s %6s files  %s\n" \
    "$p" "$(find "$OUT/extracted/$p" -type f | wc -l)" \
    "$(du -sh "$OUT/extracted/$p" | cut -f1)"
done
echo
echo "This tree is the blob source. Point extract-files.py at it, and rebuild"
echo "the candidate manifest against it instead of against the crippled"
echo "adb-shell inventory (see blobs/INVALID.md)."
echo
echo "Sanity check that the on-device permission problem is really gone:"
echo "  ls $OUT/extracted/vendor/firmware | head"
echo "  (this directory is completely invisible from an unrooted adb shell)"
