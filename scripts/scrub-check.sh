#!/usr/bin/env bash
# scrub-check.sh — find handset-identifying values before publishing contract/.
#
# The contract captures are useful to other people precisely because they are
# verbatim. That is also the problem: getprop alone carries the IMEI, the device
# serial, the SIM subscriber ID, and Wi-Fi/Bluetooth MACs. Publishing them
# deanonymizes the handset, and unlike a bad commit they cannot be recalled.
#
# This script only REPORTS. It does not edit anything, because a bad automatic
# redaction that silently mangles a hinge threshold is worse than a manual pass.
#
#   ./scrub-check.sh            # report
#   ./scrub-check.sh --redact   # write scrubbed copies to contract-public/

set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/contract"
DEST="$ROOT/contract-public"
REDACT=0
[ "${1:-}" = "--redact" ] && REDACT=1

if [ ! -d "$SRC" ]; then
  echo "No contract/ directory. Run ./capture-contract.sh first." >&2
  exit 1
fi

# Property keys and patterns that identify a specific handset rather than a
# model. Deliberately broad: a false positive costs you ten seconds, a false
# negative costs you your IMEI.
PATTERNS=(
  'ro\.serialno'
  'ro\.boot\.serialno'
  'ril\.serialnumber'
  'ro\.ril\.oem\.imei'
  'persist\.radio\.imei'
  'gsm\.imei'
  'imei'
  'meid'
  'iccid'
  'imsi'
  'subscriber'
  'ro\.boot\.cid'
  'ro\.boot\.mid'
  'bluetooth.*addr'
  'wifi.*mac'
  'ethaddr'
  'ro\.boot\.wifimacaddr'
  'ro\.boot\.btmacaddr'
  'androidId'
  'ro\.boot\.androidboot\.serial'
  'ZY[0-9A-Z]{8}'                 # Motorola serial format, e.g. <device-serial>
  '\b[0-9]{15}\b'                 # bare IMEI-length digit runs
  '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'  # MAC addresses
)

JOINED=$(IFS='|'; echo "${PATTERNS[*]}")

echo "=== scanning $SRC for handset-identifying values ==="
echo

HITS=0
while IFS= read -r f; do
  n=$(grep -InE "$JOINED" "$f" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$n" -gt 0 ]; then
    HITS=$((HITS + n))
    printf '%6s  %s\n' "$n" "${f#$ROOT/}"
  fi
done < <(find "$SRC" -type f \( -name '*.txt' -o -name '*.xml' \) | sort)

echo
if [ "$HITS" -eq 0 ]; then
  echo "No matches. Still eyeball getprop.txt yourself before pushing."
  exit 0
fi

echo "$HITS candidate lines across the files above."
echo
echo "Review them with:"
echo "  grep -InE '$JOINED' contract/common/getprop.txt | less"
echo

if [ "$REDACT" -eq 0 ]; then
  echo "Re-run with --redact to write scrubbed copies to contract-public/."
  exit 0
fi

echo "Writing scrubbed copies to ${DEST#$ROOT/}/ ..."
rm -rf "$DEST"
mkdir -p "$DEST"
(cd "$SRC" && find . -type d -exec mkdir -p "$DEST/{}" \;)

while IFS= read -r f; do
  rel="${f#$SRC/}"
  # Replace the VALUE after the last delimiter, keeping the key visible so the
  # shape of the data survives. Reviewers need to see that a key exists.
  sed -E "s/($JOINED)([^]]*)(=|: |\]: \[)?[^]]*/\1\3<REDACTED>/Ig" "$f" >"$DEST/$rel"
done < <(find "$SRC" -type f | sort)

echo
echo "Done. Now diff before you trust it:"
echo "  diff -r contract contract-public | head -50"
echo
echo "Publish contract-public/. Keep contract/ local and gitignored."
