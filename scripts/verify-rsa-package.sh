#!/bin/bash
# Verify every file in the RSA package against the MD5s in flashfile.xml.
R="${1:?usage: verify-rsa-package.sh <RomFiles/ARCFOX_G_....xml directory>}"
bad=0; n=0
sed -e 's/></>\n</g' "$R/flashfile.xml" | grep -oE 'MD5="[0-9a-f]+" filename="[^"]+"' |
while read -r line; do
  md5=$(echo "$line" | sed 's/.*MD5="\([0-9a-f]*\)".*/\1/')
  f=$(echo "$line" | sed 's/.*filename="\([^"]*\)".*/\1/')
  got=$(md5sum "$R/$f" 2>/dev/null | cut -d' ' -f1)
  n=$((n+1))
  if [ "$got" = "$md5" ]; then printf '  OK   %s\n' "$f"
  else printf '  BAD  %s  expected=%s got=%s\n' "$f" "$md5" "$got"; bad=$((bad+1)); fi
done
