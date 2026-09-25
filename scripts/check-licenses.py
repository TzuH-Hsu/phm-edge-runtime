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
does not. `X WITH <exception>` is judged on X only when the exception is on
APPROVED_EXCEPTIONS; any other exception fails the component, since a custom
addition can change the terms. A licence id may carry one trailing `+`
("or later"); anything else that is not a plain SPDX id fails.

An empty SBOM passes only when the repository has no dependency manifest; if a
manifest exists and syft found nothing, the scan is treated as broken. A git
submodule declared in .gitmodules that is not checked out (no `.git` file or
directory at its path, whatever else the directory holds) also fails the check:
its components cannot have been scanned. Checked-out submodules are searched
for their own .gitmodules, to any depth.
"""
import json
import os
import re
import subprocess
import sys

ALLOWED = {
    "MIT", "MIT-0", "Apache-2.0", "ISC",
    "0BSD", "BSD-1-Clause", "BSD-2-Clause", "BSD-3-Clause",
    # Permissive BSD variants; BSD-4-Clause (advertising clause) stays out.
    "BSD-2-Clause-Patent", "BSD-3-Clause-Clear", "BSD-3-Clause-LBNL",
}
APPROVED_EXCEPTIONS = {"LLVM-exception"}
LICENCE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.-]*\+?$")

MANIFESTS = {
    # JavaScript
    "package.json", "package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml",
    "yarn.lock", "bun.lockb",
    # Python
    "requirements.txt", "pyproject.toml", "setup.py", "setup.cfg", "Pipfile",
    "Pipfile.lock", "poetry.lock", "uv.lock", "pdm.lock", "environment.yml",
    # Go, Rust, JVM
    "go.mod", "go.sum", "Cargo.toml", "Cargo.lock", "pom.xml", "build.gradle",
    "build.gradle.kts", "gradle.lockfile", "build.sbt",
    # Ruby, PHP, .NET, Swift, Dart, Elixir, C/C++
    "Gemfile", "Gemfile.lock", "composer.json", "composer.lock",
    "packages.config", "packages.lock.json", "Package.swift", "Package.resolved",
    "Podfile", "Podfile.lock", "pubspec.yaml", "pubspec.lock", "mix.exs",
    "mix.lock", "conanfile.txt", "conanfile.py", "vcpkg.json",
}
MANIFEST_PATTERNS = re.compile(r"^requirements[-_.].*\.txt$|\.(csproj|fsproj|vbproj|gemspec|cabal)$")
SKIP_DIRS = {".git", "node_modules", "dist", ".venv", "venv"}


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
            if not LICENCE_ID.match(tok):
                raise Unparseable("bad licence id " + tok)
            node = ("id", tok[:-1] if tok.endswith("+") else tok)
        if peek() == "WITH":
            if pos + 1 >= len(tokens):
                raise Unparseable("WITH without exception")
            exc = tokens[pos + 1]
            if exc not in APPROVED_EXCEPTIONS:
                raise Unparseable("unapproved exception " + exc)
            pos += 2  # an approved exception only adds permissions to the licence
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
        return value in ALLOWED
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
        found.extend(os.path.join(dirpath, f) for f in filenames
                     if f in MANIFESTS or MANIFEST_PATTERNS.search(f))
    return found


def declared_submodule_paths(gitmodules):
    """Submodule paths from a .gitmodules file, decoded by git's own config
    parser so quoted or escaped values (`path = "hash#dir"`) come out right."""
    result = subprocess.run(
        ["git", "config", "-z", "-f", gitmodules, "--get-regexp", r"^submodule\..*\.path$"],
        capture_output=True, text=True,
    )
    if result.returncode == 1 and not result.stdout:
        return []  # no path entries
    if result.returncode != 0:
        raise RuntimeError("cannot parse {}: {}".format(gitmodules, result.stderr.strip()))
    return [entry.split("\n", 1)[1] for entry in result.stdout.split("\0") if "\n" in entry]


def uninitialised_submodules(root="."):
    path = os.path.join(root, ".gitmodules")
    if not os.path.isfile(path):
        return []
    try:
        declared = declared_submodule_paths(path)
    except (OSError, RuntimeError) as err:
        return ["{} ({})".format(path, err)]
    missing = []
    for rel in declared:
        sub = os.path.normpath(os.path.join(root, rel))
        if not os.path.exists(os.path.join(sub, ".git")):
            missing.append(sub)
        else:
            missing.extend(uninitialised_submodules(sub))
    return missing


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
