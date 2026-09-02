#!/usr/bin/env python3
"""Reject copyleft dependency licences.

Reads a syft JSON SBOM on stdin and exits non-zero when any component declares
a copyleft licence. This library is Apache-2.0 and is meant to be usable inside
commercial products, so a copyleft dependency would propagate its terms
downstream to every user of the library. Allowed: MIT, Apache-2.0, BSD, ISC and
similar permissive terms. See AGENTS.md, section on licence hygiene.
"""
import json
import re
import sys

DENY = re.compile(r"(?<![A-Za-z])(A?GPL|LGPL|SSPL|EUPL|OSL|CC-BY-SA|MPL-1)", re.IGNORECASE)


def main() -> int:
    raw = sys.stdin.read().strip()
    if not raw:
        print("check-licenses: empty SBOM on stdin", file=sys.stderr)
        return 2
    doc = json.loads(raw)
    bad = set()
    for art in doc.get("artifacts", []):
        name = art.get("name", "?")
        version = art.get("version", "?")
        for lic in art.get("licenses") or []:
            value = lic.get("value") or lic.get("spdxExpression") or ""
            if value and DENY.search(value):
                bad.add("{}@{}  {}".format(name, version, value))
    if bad:
        print("Copyleft dependencies found - not permitted in this project:")
        for line in sorted(bad):
            print("  " + line)
        return 1
    print("check-licenses: no copyleft dependencies found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
