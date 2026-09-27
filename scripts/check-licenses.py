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
  listed under "dev_only" in scripts/licence-exceptions.json for ecosystems
  whose lock file syft does not mark (pnpm), as "ecosystem:name" (for
  example "npm:eslint"). Not applied to --image scans: an image ships what it
  holds;
- component-level exceptions under "components" in
  scripts/licence-exceptions.json: a named component, in the listed syft
  ecosystems, may carry one of the listed licences. Every entry names the decision record that allows it. Another
  component with the same licence still fails.

With --image the SBOM is a container image scanned without its binary
catalogers (see the Makefile). Language packages are checked against the
allowlist; OS packages are the system layer, where GPL and LGPL are accepted
but AGPL, SSPL, BUSL, Elastic, RSAL and Timescale licences still fail unless
excepted. The repository's submodule and manifest checks are skipped.
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
# Where vendored third-party source conventionally lives; never first-party.
VENDOR_DIRS = {"vendor", "third_party", "third-party", "external", "extern"}
# OS package types in an image scan. These are the system layer: GPL and LGPL
# are expected there and are covered by the source offer, but a service
# licence the allowlist policy rejects outright is still refused.
OS_PACKAGE_TYPES = {"apk", "deb", "rpm", "alpm", "portage"}
RESTRICTED_SERVICE = re.compile(r"^(AGPL|SSPL|BUSL|Elastic|RSAL|Timescale|LicenseRef-Timescale)", re.I)
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
    """PEP 503 name: case-insensitive, with -, _ and . equivalent."""
    return re.sub(r"[-_.]+", "-", name).lower()


def identity(ecosystem, name):
    """Skip-set key: the syft package type plus the name as that ecosystem
    compares it. Only Python names are folded; npm, Go and Rust names are kept
    as written, so a package in one ecosystem never matches another's."""
    return (ecosystem, normalise(name) if ecosystem == "python" else name)


FIRST_PARTY_MANIFESTS = {
    "package.json": "npm",
    "pyproject.toml": "python",
    "Cargo.toml": "rust-crate",
    "go.mod": "go-module",
}


def walk_files(root, names):
    """Files in this repository only: nested git repositories (submodules) are
    third-party components and are not searched."""
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and d not in VENDOR_DIRS
                       and not os.path.exists(os.path.join(dirpath, d, ".git"))]
        for f in filenames:
            if f in names:
                yield os.path.join(dirpath, f)


def first_party_names(root="."):
    """(ecosystem, name, version) of the packages this repository declares;
    version is None when the manifest has none (go.mod), matching any version."""
    names = set()
    for path in walk_files(root, set(FIRST_PARTY_MANIFESTS)):
        base = os.path.basename(path)
        try:
            version = None
            if base == "package.json":
                with open(path, encoding="utf-8") as fh:
                    data = json.load(fh)
                name, version = data.get("name"), data.get("version")
            elif base == "go.mod":
                with open(path, encoding="utf-8") as fh:
                    match = re.search(r"^module\s+(\S+)", fh.read(), re.M)
                name = match.group(1) if match else None
            else:
                with open(path, "rb") as fh:
                    data = tomllib.load(fh)
                if base == "pyproject.toml":
                    table = data.get("project", {}) or data.get("tool", {}).get("poetry", {})
                else:
                    table = data.get("package", {})
                name, version = table.get("name"), table.get("version")
        except (OSError, ValueError, tomllib.TOMLDecodeError):
            continue
        if name:
            names.add(identity(FIRST_PARTY_MANIFESTS[base], name) + (version,))
    return names


def uv_closures(path, versions):
    """(shipped, dev) package-name closures of one uv.lock: shipped is what the
    project packages depend on, dev what their dependency groups pull in. The
    locked versions are collected into `versions`."""
    with open(path, "rb") as fh:
        packages = tomllib.load(fh).get("package", [])
    for pkg in packages:
        versions.setdefault(normalise(pkg["name"]), set()).add(pkg.get("version"))
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

    return reach(roots), reach(group_heads)


def dev_only_names(root="."):
    """Python packages that uv dependency groups pull in and that no uv project
    in the repository ships."""
    shipped, dev, versions = set(), set(), {}
    for path in walk_files(root, {"uv.lock"}):
        lock_shipped, lock_dev = uv_closures(path, versions)
        shipped |= lock_shipped
        dev |= lock_dev
    return {identity("python", n) + (v,) for n in dev - shipped for v in versions.get(n, {None})}


def load_exceptions(root="."):
    path = os.path.join(root, EXCEPTIONS_FILE)
    if not os.path.isfile(path):
        return {"components": [], "dev_only": []}
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    def text(value):
        return isinstance(value, str) and value.strip()

    def texts(value):
        return isinstance(value, list) and value and all(text(v) for v in value)

    for entry in data.get("components", []):
        if not (isinstance(entry, dict) and text(entry.get("name")) and text(entry.get("reason"))
                and texts(entry.get("ecosystems")) and texts(entry.get("licences"))):
            raise ValueError("{}: every component needs name and reason (strings) and "
                             "ecosystems and licences (non-empty lists of strings)".format(path))
    for item in data.get("dev_only", []):
        if not text(item) or ":" not in item:
            raise ValueError('{}: dev_only entries are "ecosystem:name", got {!r}'.format(path, item))
    return data


def excepted(ident, expr, exceptions):
    """A component exception applies to the named package in the listed syft
    ecosystems only. Conditions an exception carries that no SBOM can show,
    such as libmodbus being linked dynamically, are enforced by the build."""
    for entry in exceptions.get("components", []):
        if expr.strip() in entry["licences"] and any(
                identity(eco, entry["name"]) == ident for eco in entry["ecosystems"]):
            return True
    return False


def listed_identity(entry):
    """A dev_only entry "ecosystem:name" or "ecosystem:name@version"; without a
    version it covers every version of that package."""
    eco, rest = entry.split(":", 1)
    name, _, version = rest.rpartition("@") if "@" in rest[1:] else (rest, "", "")
    return identity(eco, name) + (version or None,)


def violations(artifacts, root=".", image=False):
    """Components outside the allowlist. For a shipped image (image=True) the
    dev-only exemptions do not apply: whatever is in the image is distributed."""
    exceptions = load_exceptions(root)
    skip = first_party_names(root)
    listed_dev = set()
    if not image:
        skip |= dev_only_names(root)
        listed_dev = {listed_identity(e) for e in exceptions.get("dev_only", [])}
    bad = set()
    for art in artifacts:
        name = art.get("name", "?")
        kind = art.get("type", "")
        ident = identity(kind, name)
        version = art.get("version")
        if {ident + (version,), ident + (None,)} & (skip | listed_dev):
            continue
        entries = art.get("licenses") or []
        exprs = [e.get("spdxExpression") or e.get("value") or "" for e in entries] or [""]
        for expr in exprs:
            if excepted(ident, expr, exceptions):
                continue
            if image and kind in OS_PACKAGE_TYPES:
                ok = not any(RESTRICTED_SERVICE.match(tok) for tok in tokenize(expr))
            else:
                ok = licence_ok(expr)
            if not ok:
                bad.add("{}@{}  {}".format(name, version or "?", expr or "(no licence)"))
    return bad


def main() -> int:
    image_mode = "--image" in sys.argv[1:]
    raw = sys.stdin.read().strip()
    if not raw:
        print("check-licenses: empty SBOM on stdin", file=sys.stderr)
        return 2
    artifacts = json.loads(raw).get("artifacts", [])
    if image_mode:
        # A container image scan: the repository's submodules and manifests say
        # nothing about it, and an image with no language packages is fine.
        missing, artifacts_expected = [], False
    else:
        missing, artifacts_expected = uninitialised_submodules(), True
    if missing:
        print("check-licenses: submodules not checked out, their licences were not scanned:")
        for path in sorted(missing):
            print("  " + path)
        print("run `git submodule update --init --recursive` first")
        return 1
    if not artifacts:
        manifests = find_manifests() if artifacts_expected else []
        if manifests:
            print("check-licenses: syft found no components, but these manifests exist:")
            for path in sorted(manifests):
                print("  " + path)
            return 1
        print("check-licenses: no dependency manifests and no components - nothing to check")
        return 0
    try:
        bad = violations(artifacts, image=image_mode)
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
