#!/usr/bin/env python3
"""Enforce the dependency licence allowlist.

Reads a syft JSON SBOM on stdin and exits non-zero unless every component's
licence satisfies the allowlist in AGENTS.md (section on licence hygiene): MIT,
Apache-2.0, BSD, ISC. This library is Apache-2.0 and is meant to be usable
inside commercial products, so a copyleft dependency would propagate its terms
downstream to every user of the library.

Fails closed: a component with no licence, NOASSERTION, a LicenseRef-* or any
identifier not on the allowlist is rejected. SPDX expressions are evaluated,
so `MIT OR GPL-2.0-only` passes (MIT can be chosen) while `MIT AND GPL-2.0-only`
does not. `X WITH <exception>` is judged on X, provided the exception is a
well-formed SPDX exception id (a LicenseRef-/AdditionRef- or operator there
fails the component).

An empty SBOM passes only when the repository has no dependency manifest; if a
manifest exists and syft found nothing, the scan is treated as broken. A git
submodule declared in .gitmodules whose directory is missing or empty also
fails the check: its components cannot have been scanned.
"""
import json
import os
import re
import sys

ALLOWED = re.compile(r"^(MIT|MIT-0|Apache-2\.0|0BSD|BSD-[0-9A-Za-z.-]+|ISC)$")

MANIFESTS = {
    "package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock",
    "requirements.txt", "pyproject.toml", "poetry.lock", "uv.lock", "Pipfile.lock",
    "go.mod", "Cargo.toml", "Cargo.lock", "pom.xml", "build.gradle",
    "build.gradle.kts", "Gemfile.lock", "composer.lock",
}
SKIP_DIRS = {".git", "node_modules", "dist", ".venv", "venv"}
EXCEPTION_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.+-]*$")


class Unparseable(ValueError):
    pass


def tokenize(expr):
    return re.findall(r"\(|\)|[^\s()]+", expr)


def parse(tokens):
    """Recursive descent: or := and (OR and)*; and := atom (AND atom)*."""
    pos = 0

    def peek():
        return tokens[pos].upper() if pos < len(tokens) else None

    def atom():
        nonlocal pos
        if pos >= len(tokens):
            raise Unparseable("unexpected end")
        tok = tokens[pos]
        pos += 1
        if tok == "(":
            node = or_expr()
            if peek() != ")":
                raise Unparseable("missing )")
            pos += 1
        elif tok.upper() in ("AND", "OR", "WITH", ")"):
            raise Unparseable("unexpected " + tok)
        else:
            node = ("id", tok.rstrip("+"))
        if peek() == "WITH":
            if pos + 1 >= len(tokens):
                raise Unparseable("WITH without exception")
            exc = tokens[pos + 1]
            if (not EXCEPTION_ID.match(exc)
                    or exc.upper() in ("AND", "OR", "WITH")
                    or re.match(r"(?i)(LicenseRef|AdditionRef|DocumentRef)-", exc)):
                raise Unparseable("bad exception " + exc)
            pos += 2  # a standard exception only adds permissions to the licence
        return node

    def and_expr():
        nonlocal pos
        nodes = [atom()]
        while peek() == "AND":
            pos += 1
            nodes.append(atom())
        return ("and", nodes)

    def or_expr():
        nonlocal pos
        nodes = [and_expr()]
        while peek() == "OR":
            pos += 1
            nodes.append(and_expr())
        return ("or", nodes)

    node = or_expr()
    if pos != len(tokens):
        raise Unparseable("trailing " + tokens[pos])
    return node


def allowed(node):
    kind, value = node
    if kind == "id":
        return bool(ALLOWED.match(value))
    if kind == "and":
        return all(allowed(n) for n in value)
    return any(allowed(n) for n in value)


def licence_ok(expr):
    if not expr or expr.strip().upper() in ("NOASSERTION", "NONE"):
        return False
    try:
        return allowed(parse(tokenize(expr)))
    except Unparseable:
        return False


def find_manifests(root="."):
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        found.extend(os.path.join(dirpath, f) for f in filenames if f in MANIFESTS)
    return found


def uninitialised_submodules(root="."):
    path = os.path.join(root, ".gitmodules")
    if not os.path.isfile(path):
        return []
    with open(path) as handle:
        declared = re.findall(r"^\s*path\s*=\s*(.+?)\s*$", handle.read(), re.MULTILINE)
    return [d for d in declared
            if not os.path.isdir(os.path.join(root, d)) or not os.listdir(os.path.join(root, d))]


def main() -> int:
    raw = sys.stdin.read().strip()
    if not raw:
        print("check-licenses: empty SBOM on stdin", file=sys.stderr)
        return 2
    artifacts = json.loads(raw).get("artifacts", [])
    missing = uninitialised_submodules()
    if missing:
        print("check-licenses: submodules not checked out, their licences were not scanned:")
        for path in sorted(missing):
            print("  " + path)
        print("run `git submodule update --init --recursive` first")
        return 1
    if not artifacts:
        manifests = find_manifests()
        if manifests:
            print("check-licenses: syft found no components, but these manifests exist:")
            for path in sorted(manifests):
                print("  " + path)
            return 1
        print("check-licenses: no dependency manifests and no components - nothing to check")
        return 0
    bad = set()
    for art in artifacts:
        name = art.get("name", "?")
        version = art.get("version", "?")
        entries = art.get("licenses") or []
        exprs = [e.get("spdxExpression") or e.get("value") or "" for e in entries] or [""]
        for expr in exprs:
            if not licence_ok(expr):
                bad.add("{}@{}  {}".format(name, version, expr or "(no licence)"))
    if bad:
        print("Dependencies outside the licence allowlist (MIT, Apache-2.0, BSD, ISC):")
        for line in sorted(bad):
            print("  " + line)
        return 1
    print("check-licenses: {} components, all within the allowlist".format(len(artifacts)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
