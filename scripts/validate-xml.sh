#!/bin/bash
# Validate every XML file in the device trees before a build.
#
# WHY THIS EXISTS: "XML comments cannot contain a double hyphen" is recorded as a
# known trap in HANDOFF-NEXT.md and has still broken the build three times --
# config.xml, a vintf fragment, and then config.xml again in the very next commit.
# aapt2 reports it as a bare `xml parser error: not well-formed (invalid token)`
# with NO line number, and a vintf fragment with the same fault installs happily
# and only fails at runtime, so neither failure mode points at the cause.
#
# Ad-hoc `python3 -c ...parse()` checks are not enough: chained one-liners let a
# failure scroll past while a later "OK" from a different file gives false
# reassurance. That is exactly how bc26's build was launched against a broken
# file. This exits non-zero, loudly, and names the line.
#
# Usage:  ./validate-xml.sh            (validates both device trees)
#         ./validate-xml.sh <dir>...
set -u
TREES=("${@:-$HOME/android/arcfox/device/motorola/arcfox $HOME/android/arcfox/device/motorola/sm8635-common}")

python3 - "${TREES[@]}" <<'PY'
import sys, os, re, xml.dom.minidom

bad = 0
checked = 0
for root_arg in " ".join(sys.argv[1:]).split():
    for dirpath, _, files in os.walk(root_arg):
        for f in files:
            if not f.endswith(".xml"):
                continue
            p = os.path.join(dirpath, f)
            checked += 1
            try:
                xml.dom.minidom.parse(p)
            except Exception as e:
                bad += 1
                print(f"\n  BROKEN: {p}\n     {e}")
                # The overwhelmingly common cause: '--' inside a comment.
                try:
                    txt = open(p, encoding="utf-8", errors="replace").read()
                except Exception:
                    continue
                for m in re.finditer(r"<!--.*?-->", txt, re.S):
                    body = m.group(0)[4:-3]
                    if "--" in body:
                        line = txt[:m.start()].count("\n") + 1
                        for i, l in enumerate(body.split("\n")):
                            if "--" in l:
                                print(f"     line {line+i}: DOUBLE HYPHEN in comment:"
                                      f" {l.strip()[:88]}")
print(f"\n{checked} XML files checked, {bad} broken")
sys.exit(1 if bad else 0)
PY
