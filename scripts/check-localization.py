#!/usr/bin/env python3
"""Placeholder parity across every string catalog.

A translation that drops a format argument does not just read wrong — every later
argument shifts, so `%3$@` starts printing what `%2$@` meant. This compares the token
multiset of each localization against its source key and fails on any difference.
"""

import json
import re
import sys
from pathlib import Path

CATALOGS = [
    "App/Forge/Localizable.xcstrings",
    "App/Forge/InfoPlist.xcstrings",
    "App/ForgeWatch/Localizable.xcstrings",
    "App/ForgeWidgets/Localizable.xcstrings",
    "ForgeCore/Sources/ForgeCore/Resources/Localizable.xcstrings",
]

TOKEN = re.compile(r"%(?:\d+\$)?[@a-z]*(?:lld|ld|d|@|f|s)")


def tokens(text: str) -> list[str]:
    """Positional and non-positional forms compare equal: %2$@ counts as %@."""
    return sorted(re.sub(r"%(\d+)\$", "%", match) for match in TOKEN.findall(text))


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    problems = 0
    checked = 0
    for name in CATALOGS:
        path = root / name
        if not path.exists():
            continue
        catalog = json.loads(path.read_text())
        for key, entry in catalog.get("strings", {}).items():
            expected = tokens(key)
            if not expected:
                continue
            for locale, value in entry.get("localizations", {}).items():
                unit = value.get("stringUnit", {}).get("value")
                if unit is None:
                    continue
                checked += 1
                found = tokens(unit)
                if found != expected:
                    problems += 1
                    print(f"{name} [{locale}] {key!r}")
                    print(f"    value:    {unit!r}")
                    print(f"    expected: {expected}")
                    print(f"    found:    {found}")
    print(f"checked {checked} localizations")
    if problems:
        print(f"{problems} placeholder mismatch(es)", file=sys.stderr)
        return 1
    print("placeholder parity ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
