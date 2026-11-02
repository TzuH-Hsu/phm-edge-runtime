#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Fail on SQL that does not name its columns.

The disk queue's schema only grows: a later version may add columns to a
table an earlier version also uses. A statement that reads every column with
`SELECT *`, or an `INSERT` without a column list, changes meaning when that
happens, so neither may appear in the library's SQL.

Scans every file under the given paths (default: src/) and reports each
match as <file>:<line>: <message>. The match is case-insensitive and may span
lines and adjacent C++ string literals ("INSERT INTO t " "VALUES ..."). Exits
1 when anything is found, 2 when a path does not exist, 0 otherwise.

Run: python3 scripts/check-sql.py [path ...]
"""
import os
import re
import sys

# Separators allowed between SQL words: whitespace and the quotes that end one
# C++ string literal and start the next.
_SEP = r'[\s"]+'

SELECT_STAR = re.compile(
    r"\bSELECT" + _SEP + r"(?:(?:ALL|DISTINCT)" + _SEP + r")?\*",
    re.IGNORECASE,
)
# INSERT [OR <action>] INTO <table> followed by anything but "(": VALUES,
# SELECT or DEFAULT VALUES all mean the statement lists no columns. The two
# lookaheads stop a backtrack into a shorter table name or fewer separators
# from dodging the "(" test (an atomic group would need Python 3.11).
INSERT_WITHOUT_COLUMNS = re.compile(
    r"\b(?:INSERT|REPLACE)" + _SEP + r"(?:OR" + _SEP + r"\w+" + _SEP + r")?INTO" + _SEP
    + r'(?:\w+\.)?\w+(?![\w.])[\s"]*(?![\s"(])',
    re.IGNORECASE,
)

CHECKS = (
    (SELECT_STAR, "SELECT * reads every column; name the columns"),
    (INSERT_WITHOUT_COLUMNS, "INSERT without a column list; name the columns"),
)


def findings(path):
    """Returns sorted (line, message) pairs for every violation in one file."""
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except UnicodeDecodeError:
        return []  # not a text file: it holds no SQL source
    found = []
    for pattern, message in CHECKS:
        for match in pattern.finditer(text):
            found.append((text.count("\n", 0, match.start()) + 1, message))
    return sorted(found)


def files_under(paths):
    for root in paths:
        if os.path.isfile(root):
            yield root
            continue
        for directory, subdirs, names in os.walk(root):
            subdirs.sort()
            for name in sorted(names):
                yield os.path.join(directory, name)


def main(argv):
    paths = argv[1:] or ["src"]
    missing = [p for p in paths if not os.path.exists(p)]
    if missing:
        print("check-sql: no such path: " + ", ".join(missing), file=sys.stderr)
        return 2
    failed = False
    for path in files_under(paths):
        for line, message in findings(path):
            print(f"{path}:{line}: {message}", file=sys.stderr)
            failed = True
    if not failed:
        print("ok: every SQL statement names its columns")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
