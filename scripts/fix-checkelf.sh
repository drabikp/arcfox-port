#!/usr/bin/env bash
# fix-checkelf.sh — append ;DISABLE_CHECKELF to every blob that soong's
# check_elf_file rejects for unresolved symbols.
#
#   ./fix-checkelf.sh /tmp/arcfox-build.log
#
# Why: some vendor blobs reference symbols from QTI interfaces that simply are
# not present in a LineageOS tree (e.g. the LHDC v5 bluetooth codec AIDL). The
# stock image resolves them at runtime against libraries we do not ship or do
# not need. check_elf_file is a build-time sanity check, not a runtime
# requirement, and the LineageOS blob manifest format has an explicit opt-out.
#
# This does NOT paper over missing dependencies that the build could satisfy —
# those show up as "depends on undefined module" and are handled by
# resolve-build-blobs.sh instead.

set -o pipefail
LOG="${1:-/tmp/arcfox-build.log}"
DEV=$HOME/android/arcfox/device/motorola/arcfox/proprietary-files.txt
COM=$HOME/android/arcfox/device/motorola/sm8635-common/proprietary-files.txt

[ -f "$LOG" ] || { echo "no log at $LOG" >&2; exit 1; }

mapfile -t BLOBS < <(
  /usr/bin/grep -oE '^vendor/motorola/[a-z0-9-]+/proprietary/[^:]+: error: Unresolved symbol' "$LOG" \
  | /usr/bin/sed -E 's|^vendor/motorola/[a-z0-9-]+/proprietary/||; s|: error: Unresolved symbol$||' \
  | sort -u
)

[ "${#BLOBS[@]}" -gt 0 ] || { echo "no check_elf_file failures in $LOG"; exit 0; }

n=0
for b in "${BLOBS[@]}"; do
  for f in "$DEV" "$COM"; do
    # Match the path with or without existing annotations, skip if already done.
    if /usr/bin/grep -qE "^-?${b//./\\.}(;|$)" "$f"; then
      if /usr/bin/grep -qE "^-?${b//./\\.}.*DISABLE_CHECKELF" "$f"; then
        echo "  already disabled: $b"
      else
        /usr/bin/sed -i -E "s|^(-?${b//./\\.})(;.*)?$|\1\2;DISABLE_CHECKELF|" "$f"
        echo "  + DISABLE_CHECKELF  $b   ($(basename "$(dirname "$f")"))"
        n=$((n+1))
      fi
      break
    fi
  done
done
echo "annotated $n blob(s)"
