#!/usr/bin/env python3
"""Enforce the dependency licence allowlist.

Reads a syft JSON SBOM on stdin and exits non-zero unless every component's
licence satisfies the allowlist in AGENTS.md (section on licence hygiene): MIT,
Apache-2.0, BSD, ISC, plus notice-only licences (curl, blessing, Zlib, PSF-2.0,
PostgreSQL, BSL-1.0, CC-BY-4.0). This library is Apache-2.0 and is meant to be
usable inside commercial products, so a copyleft dependency would propagate
its terms downstream to every user of the library.

Fails closed: a component with no licence, NOASSERTION, a LicenseRef-* or any
identifier not on the allowlist is rejected. SPDX expressions are evaluated,
so `MIT OR GPL-2.0-only` passes (MIT can be chosen) while `MIT AND GPL-2.0-only`
does not. `X WITH <exception>` is judged on X only when the exception is on
APPROVED_EXCEPTIONS; any other exception fails the component, since a custom
addition can change the terms. A licence id may carry one trailing `+`
("or later"); anything else that is not a plain SPDX id fails.

An empty SBOM passes only when the repository has no dependency manifest; if a
manifest exists and syft found nothing, the scan is treated as broken. A git
submodule declared in .gitmodules that is not a working git checkout (git must
resolve the submodule directory as its own work-tree top level; stale files or
a dangling `.git` do not count) also fails the check: its components cannot
have been scanned. Checked-out submodules are searched
for their own .gitmodules, to any depth.

Three kinds of component are not judged against the allowlist:
- the repository's own packages (names read from package.json, pyproject.toml,
  Cargo.toml and go.mod), which syft lists without a licence;
- development-only dependencies: derived from uv.lock dependency groups, and
  listed by name under "dev_only" in scripts/licence-exceptions.json for
  ecosystems whose lock file syft does not mark (pnpm);
- component-level exceptions under "components" in
  scripts/licence-exceptions.json: a named component may carry one of the listed
  licences. Every entry names the decision record that allows it. Another
  component with the same licence still fails.
"""
import json
import os
import re
import subprocess
import sys

try:
    import tomllib
except ModuleNotFoundError:  # Python < 3.11
    sys.exit("check-licenses: needs Python 3.11 or later (tomllib)")

ALLOWED = {
    "MIT", "MIT-0", "Apache-2.0", "ISC",
    "0BSD", "BSD-1-Clause", "BSD-2-Clause", "BSD-3-Clause",
    # Permissive BSD variants; BSD-4-Clause (advertising clause) stays out.
    "BSD-2-Clause-Patent", "BSD-3-Clause-Clear", "BSD-3-Clause-LBNL",
    # Notice-only licences: keep the notice, no other obligation.
    "curl", "blessing", "Zlib", "PSF-2.0", "PostgreSQL", "BSL-1.0", "CC-BY-4.0",
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
EXCEPTIONS_FILE = os.path.join("scripts", "licence-exceptions.json")


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


def is_checked_out(path):
    """True when git resolves `path` as the top level of a usable work tree."""
    if not os.path.exists(os.path.join(path, ".git")):
        return False
    result = subprocess.run(
        ["git", "-C", path, "rev-parse", "--show-toplevel"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        return False
    return os.path.realpath(result.stdout.strip()) == os.path.realpath(path)


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
        if not is_checked_out(sub):
            missing.append(sub)
        else:
            missing.extend(uninitialised_submodules(sub))
    return missing


def normalise(name):
    """Package names compare case-insensitively, with -, _ and . equivalent
    (PEP 503); harmless for the other ecosystems."""
    return re.sub(r"[-_.]+", "-", name).lower()


def walk_files(root, names):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for f in filenames:
            if f in names:
                yield os.path.join(dirpath, f)


def first_party_names(root="."):
    """Names of the packages this repository itself declares."""
    names = set()
    for path in walk_files(root, {"package.json", "pyproject.toml", "Cargo.toml", "go.mod"}):
        base = os.path.basename(path)
        try:
            if base == "package.json":
                with open(path, encoding="utf-8") as fh:
                    name = json.load(fh).get("name")
            elif base == "go.mod":
                with open(path, encoding="utf-8") as fh:
                    match = re.search(r"^module\s+(\S+)", fh.read(), re.M)
                name = match.group(1) if match else None
            else:
                with open(path, "rb") as fh:
                    data = tomllib.load(fh)
                section = "project" if base == "pyproject.toml" else "package"
                name = data.get(section, {}).get("name")
        except (OSError, ValueError, tomllib.TOMLDecodeError):
            continue
        if name:
            names.add(normalise(name))
    return names


def uv_dev_only(path):
    """Packages reachable only through dependency groups in one uv.lock."""
    with open(path, "rb") as fh:
        packages = tomllib.load(fh).get("package", [])
    deps = {}
    roots = []
    group_heads = set()
    for pkg in packages:
        name = normalise(pkg["name"])
        edges = {normalise(d["name"]) for d in pkg.get("dependencies", [])}
        for extra in pkg.get("optional-dependencies", {}).values():
            edges |= {normalise(d["name"]) for d in extra}
        deps.setdefault(name, set()).update(edges)
        source = pkg.get("source", {})
        if "virtual" in source or "editable" in source:
            roots.append(name)
            for group in pkg.get("dev-dependencies", {}).values():
                group_heads |= {normalise(d["name"]) for d in group}

    def reach(start):
        seen, stack = set(), list(start)
        while stack:
            node = stack.pop()
            if node not in seen:
                seen.add(node)
                stack.extend(deps.get(node, ()))
        return seen

    shipped = reach(roots)
    return reach(group_heads) - shipped


def dev_only_names(root=".", exceptions=None):
    names = {normalise(n) for n in (exceptions or {}).get("dev_only", [])}
    for path in walk_files(root, {"uv.lock"}):
        names |= uv_dev_only(path)
    return names


def load_exceptions(root="."):
    path = os.path.join(root, EXCEPTIONS_FILE)
    if not os.path.isfile(path):
        return {"components": [], "dev_only": []}
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    for entry in data.get("components", []):
        if not entry.get("name") or not entry.get("licences") or not entry.get("reason"):
            raise ValueError("{}: every component needs name, licences and reason".format(path))
    return data


def excepted(name, expr, exceptions):
    for entry in exceptions.get("components", []):
        if normalise(entry["name"]) == normalise(name) and expr.strip() in entry["licences"]:
            return True
    return False


def violations(artifacts, root="."):
    exceptions = load_exceptions(root)
    skip = first_party_names(root) | dev_only_names(root, exceptions)
    bad = set()
    for art in artifacts:
        name = art.get("name", "?")
        if normalise(name) in skip:
            continue
        version = art.get("version", "?")
        entries = art.get("licenses") or []
        exprs = [e.get("spdxExpression") or e.get("value") or "" for e in entries] or [""]
        for expr in exprs:
            if not licence_ok(expr) and not excepted(name, expr, exceptions):
                bad.add("{}@{}  {}".format(name, version, expr or "(no licence)"))
    return bad


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
    try:
        bad = violations(artifacts)
    except (OSError, ValueError, tomllib.TOMLDecodeError) as err:
        print("check-licenses: {}".format(err))
        return 1
    if bad:
        print("Dependencies outside the licence allowlist (see AGENTS.md, licence hygiene):")
        for line in sorted(bad):
            print("  " + line)
        return 1
    print("check-licenses: {} components, all within the allowlist".format(len(artifacts)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
