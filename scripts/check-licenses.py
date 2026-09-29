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
("or later"); anything else that is not a plain SPDX id fails, except the few
free-text names in LICENCE_ALIASES that have exactly one meaning.

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
- development-only dependencies: derived from uv.lock dependency groups and
  from the devDependencies of pnpm-lock.yaml importers (a package that
  dependencies also reach is not development-only), and listed under
  "dev_only" in scripts/licence-exceptions.json for any other case, as
  "ecosystem:name" (for example "npm:eslint"). Not applied to --image scans:
  an image ships what it holds;
- component-level exceptions under "components" in
  scripts/licence-exceptions.json: a named component, in the listed syft
  ecosystems, may carry one of the listed licences. Every entry names the
  decision record that allows it. An entry with "images" applies only to
  --image scans of those image repositories (for example
  "chrislusf/seaweedfs", any tag). Another component with the same licence
  still fails.

syft reports the SHA-256 of a file it found by name but could not match to a
licence. Where every such file is plainly not a licence text (a file named
NOTICE*, such as NOTICE.txt or notice_response.go, or a workflow file under
.github/workflows/, such as .github/workflows/license_check.yml, that is not
itself named LICENSE, COPYING or the like) the entry is dropped; any other
unmatched file, LICENSE.json or COPYING.py included, still fails.

A component whose registry metadata carries no usable licence (only a
classifier, or free text such as "Dual License") may have its licence
recorded under "corrections" in scripts/licence-exceptions.json, as
"ecosystem:name@version" with the SPDX expression read from the package's own
licence file, the exact licence text the metadata reports ("reported"; an
empty string when it reports none) and the reason. A correction applies only
while the metadata reports exactly that text; any other value fails the
check, so a correction never replaces a licence it was not written for.
Metadata that already states the corrected licence itself also passes. The corrected licence is then judged against the allowlist
like any other, so a correction cannot let through a licence the allowlist
rejects; and it names one version, so an upgrade is checked again.

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
    "BSD-2-Clause-Patent", "BSD-2-Clause-Views", "BSD-3-Clause-Clear",
    "BSD-3-Clause-LBNL",
    # Notice-only licences: keep the notice, no other obligation.
    "curl", "blessing", "Zlib", "PSF-2.0", "PostgreSQL", "BSL-1.0", "CC-BY-4.0",
}
APPROVED_EXCEPTIONS = {"LLVM-exception"}
# Free-text licence names that registry metadata carries instead of an SPDX id
# (PyPI's `license` field), mapped only where the name has exactly one meaning.
# "BSD License" and similar stay unmapped and fail: the variant is unknown.
LICENCE_ALIASES = {
    "mit license": "MIT",
    "isc license": "ISC",
    "the mit license": "MIT",
    "apache license 2.0": "Apache-2.0",
    "apache license, version 2.0": "Apache-2.0",
    "apache software license 2.0": "Apache-2.0",
}
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
SKIP_DIRS = {".git", "node_modules", "dist", "build", ".venv", "venv"}
# Where vendored third-party source conventionally lives; never first-party.
VENDOR_DIRS = {"vendor", "third_party", "third-party", "external", "extern"}
# OS package types in an image scan. These are the system layer: GPL and LGPL
# are expected there and are covered by the source offer, but a service
# licence the allowlist policy rejects outright is still refused.
OS_PACKAGE_TYPES = {"apk", "deb", "rpm", "alpm", "portage"}
RESTRICTED_SERVICE = re.compile(r"^(AGPL|SSPL|BUSL|Elastic|RSAL|Timescale|LicenseRef-Timescale)", re.I)
EXCEPTIONS_FILE = os.path.join("scripts", "licence-exceptions.json")
# Files that syft's licence-file name match picks up but that hold no licence
# terms: files named NOTICE* (attribution, or source such as
# notice_response.go) and GitHub workflow files under .github/workflows/.
# A file named like a licence (LICENSE, LICENCE, COPYING, UNLICENSE, with or
# without an extension) is always judged, wherever it sits; so is anything
# else, such as LICENSE.json or a licence file elsewhere under .github/.
NOT_LICENCE_TEXT = re.compile(r"(^|/)notice[^/]*$|(^|/)\.github/workflows/", re.I)
LICENCE_FILE_NAME = re.compile(r"(^|/)(licen[cs]e|copying|unlicen[cs]e)(\.[^/]*)?$", re.I)


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


def allowed(node, ok=ALLOWED.__contains__):
    """Whether a parsed expression is satisfied when each licence id is
    judged by ok (by default: on the allowlist)."""
    kind, value = node
    if kind == "id":
        return ok(value)
    if kind == "and":
        return all(allowed(n, ok) for n in value)
    return any(allowed(n, ok) for n in value)


def licence_ok(expr):
    if not expr or expr.strip().upper() in ("NOASSERTION", "NONE"):
        return False
    expr = LICENCE_ALIASES.get(expr.strip().lower(), expr)
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


def walk_files(root, names, nested=False):
    """Files in this repository only: nested git repositories (submodules) and
    vendored directories are third-party components and are not searched.
    With nested, they are searched too, for what the delivery ships."""
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and (nested or (
            d not in VENDOR_DIRS and not os.path.exists(os.path.join(dirpath, d, ".git"))))]
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
    """Python packages that this repository's uv dependency groups pull in and
    that nothing shipped does, submodules and vendored code included."""
    shipped, dev, versions = set(), set(), {}
    own = set(walk_files(root, {"uv.lock"}))
    for path in walk_files(root, {"uv.lock"}, nested=True):
        lock_shipped, lock_dev = uv_closures(path, versions)
        shipped |= lock_shipped
        if path in own:
            dev |= lock_dev
    return {identity("python", n) + (v,) for n in dev - shipped for v in versions.get(n, {None})}


PNPM_LOCKFILE_MAJOR = "9"


DOUBLE_QUOTED_ESCAPES = {'"': '"', "\\": "\\", "/": "/"}


def quoted_scalar(text):
    """(value, rest) of the YAML quoted scalar that opens text. A single-quoted
    scalar writes a quote as two quotes; a double-quoted one uses backslash
    escapes, of which only those a path can need are accepted, so anything
    else fails the check rather than being read wrongly."""
    quote, i, out = text[0], 1, []
    while i < len(text):
        c = text[i]
        if c == quote:
            if quote == "'" and text[i + 1:i + 2] == "'":
                out.append("'")
                i += 2
                continue
            return "".join(out), text[i + 1:]
        if quote == '"' and c == "\\":
            esc = text[i + 1:i + 2]
            if esc not in DOUBLE_QUOTED_ESCAPES:
                raise ValueError("unsupported escape in lockfile: {!r}".format(text))
            out.append(DOUBLE_QUOTED_ESCAPES[esc])
            i += 2
            continue
        out.append(c)
        i += 1
    raise ValueError("unterminated quoted scalar in lockfile: {!r}".format(text))


def unquote(text):
    text = text.strip()
    if text[:1] in ("'", '"'):
        value, rest = quoted_scalar(text)
        if rest.strip():
            raise ValueError("unexpected text after quoted scalar in lockfile: {!r}".format(text))
        return value
    return text


def split_entry(text):
    """`key: value` of one YAML mapping line; the key may be quoted. An
    unquoted key ends at ": " or at a trailing ":", so keys such as
    `prod@file:prod` keep their inner colons."""
    if text[:1] in ("'", '"'):
        key, rest = quoted_scalar(text)
        return key, rest.lstrip(":").strip()
    key, sep, rest = text.partition(": ")
    if sep:
        return key, rest.strip()
    return (text[:-1], "") if text.endswith(":") else (text, "")


def parse_pnpm_lock(path):
    """(importers, snapshots, packages) of a pnpm lockfile v9, reduced to the
    dependency edges: importers maps importer -> field -> {name: version},
    snapshots maps a snapshot key -> {name: version}, and packages is the set
    of package keys (a snapshot key without its peer context). Only the fixed
    block layout pnpm writes is understood; any other lockfile version fails
    the check."""
    importers, snapshots, packages = {}, {}, set()
    section = key = field = dep = None
    version_seen = False
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            text = line.strip()
            if not text or text.startswith("#"):
                continue
            indent = len(line) - len(line.lstrip(" "))
            name, value = split_entry(text)
            if indent == 0:
                section = name
                if name == "lockfileVersion":
                    if unquote(value).split(".")[0] != PNPM_LOCKFILE_MAJOR:
                        raise ValueError("{}: unsupported pnpm lockfile version {}".format(path, value))
                    version_seen = True
                continue
            if section == "importers":
                if indent == 2:
                    key = name
                    importers[key] = {}
                elif indent == 4:
                    field = name
                elif indent == 6:
                    dep = name
                elif indent == 8 and name == "version":
                    importers[key].setdefault(field, {})[dep] = unquote(value)
            elif section == "packages":
                if indent == 2:
                    packages.add(name)
            elif section == "snapshots":
                if indent == 2:
                    key = name
                    snapshots[key] = {}
                elif indent == 4:
                    field = name
                elif indent == 6 and field in ("dependencies", "optionalDependencies"):
                    snapshots[key][name] = unquote(value)
    if not version_seen:
        raise ValueError("{}: no lockfileVersion".format(path))
    return importers, snapshots, packages


def pnpm_target(name, version, snapshots):
    """The snapshot key a dependency entry points at, looked up rather than
    guessed: `name@version` for a registry, `file:` or git dependency, or the
    version itself for an alias (which records the real `name@version`).
    Only a workspace `link:` has no snapshot; the linked importer's own
    entries are read separately. An entry that matches no snapshot fails the
    check, since its dependencies could not be followed."""
    if version.startswith("link:"):
        return None
    for key in ("{}@{}".format(name, version), version):
        if key in snapshots:
            return key
    raise ValueError("pnpm-lock.yaml: no snapshot for {} {}".format(name, version))


def trailing_group_start(text):
    """Index of the "(" that opens the balanced parenthesised group ending
    text, or None when text does not end in one."""
    if not text.endswith(")"):
        return None
    depth = 0
    for start in range(len(text) - 1, -1, -1):
        if text[start] == ")":
            depth += 1
        elif text[start] == "(":
            depth -= 1
            if depth == 0:
                return start
    return None


def strip_peer_suffix(key):
    """key without the trailing groups that look like pnpm's peer context,
    each naming a package@version. Only a fallback for a snapshot with no
    entry under packages; see pnpm_package_key."""
    while (start := trailing_group_start(key)) is not None and start > 0 and "@" in key[start:]:
        key = key[:start]
    return key


def pnpm_package_key(snapshot_key, packages):
    """The packages-section key a snapshot belongs to: a snapshot key is its
    package key followed by pnpm's peer context, one or more trailing
    parenthesised groups. The longest form of the snapshot key found among
    the package keys is taken, so a parenthesis that belongs to a file: path
    is never mistaken for peer context."""
    key = snapshot_key
    while key not in packages:
        start = trailing_group_start(key)
        if start is None or start == 0:
            return strip_peer_suffix(snapshot_key)
        key = key[:start]
    return key


def pnpm_package(package_key):
    """(name, version) of a package key. A package name holds an "@" only as
    the leading scope marker, so the delimiter is the first "@" after that;
    the version part (a file: path or a git locator such as git@host) may
    contain more."""
    at = package_key.index("@", 1)
    return package_key[:at], package_key[at + 1:]


def pnpm_closures(path):
    """(shipped, dev) package-key closures of one pnpm-lock.yaml: shipped is
    what the importers' dependencies and optionalDependencies reach, dev what
    their devDependencies reach."""
    importers, snapshots, packages = parse_pnpm_lock(path)

    def heads(fields):
        return {t for imp in importers.values() for f in fields
                for n, v in imp.get(f, {}).items() if (t := pnpm_target(n, v, snapshots))}

    def reach(start):
        seen, stack = set(), list(start)
        while stack:
            node = stack.pop()
            if node not in seen:
                seen.add(node)
                stack.extend(t for n, v in snapshots[node].items()
                             if (t := pnpm_target(n, v, snapshots)))
        return seen

    def package_keys(snapshot_keys):
        return {pnpm_package_key(k, packages) for k in snapshot_keys}

    return (package_keys(reach(heads(("dependencies", "optionalDependencies")))),
            package_keys(reach(heads(("devDependencies",)))))


def pnpm_dev_only_names(root="."):
    """npm packages that only this repository's pnpm devDependencies pull in:
    anything a lockfile ships, submodules and vendored code included, is
    not development-only."""
    shipped, dev = set(), set()
    own = set(walk_files(root, {"pnpm-lock.yaml"}))
    for path in walk_files(root, {"pnpm-lock.yaml"}, nested=True):
        lock_shipped, lock_dev = pnpm_closures(path)
        shipped |= {pnpm_package(k) for k in lock_shipped}
        if path in own:
            dev |= {pnpm_package(k) for k in lock_dev}
    return {identity("npm", n) + (v,) for n, v in dev - shipped}


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
                and texts(entry.get("ecosystems")) and texts(entry.get("licences"))
                and ("images" not in entry or texts(entry["images"]))):
            raise ValueError("{}: every component needs name and reason (strings) and "
                             "ecosystems and licences (non-empty lists of strings); "
                             "images, when given, is a non-empty list of strings".format(path))
    for item in data.get("dev_only", []):
        if not text(item) or ":" not in item:
            raise ValueError('{}: dev_only entries are "ecosystem:name", got {!r}'.format(path, item))
    for entry in data.get("corrections", []):
        if not (isinstance(entry, dict) and text(entry.get("component")) and text(entry.get("licence"))
                and text(entry.get("reason")) and isinstance(entry.get("reported"), str)
                and listed_identity(entry["component"])[2]):
            raise ValueError('{}: every correction needs component ("ecosystem:name@version"), '
                             "licence, reported (a string, empty for none) and reason".format(path))
    return data


def image_repository(name):
    """The repository of an image reference, without its tag or digest and
    with Docker Hub written short: docker.io/library/postgres:18@sha256:...
    and postgres are the same repository. A registry port (host:5000/repo)
    is kept, since its colon comes before the last slash."""
    if not name:
        return name
    name = name.split("@", 1)[0]
    if name.rfind(":") > name.rfind("/"):
        name = name[:name.rfind(":")]
    for prefix in ("docker.io/library/", "docker.io/", "index.docker.io/library/", "index.docker.io/"):
        if name and name.startswith(prefix):
            return name[len(prefix):]
    return name


def exception_for(ident, expr, exceptions, image_name=None):
    """The component exception that allows this licence on this package, or
    None. An exception applies to the named package in the listed syft
    ecosystems only, and one that lists images only to a scan of one of
    those images. Conditions an exception carries that no SBOM can show,
    such as libmodbus being linked dynamically, are enforced by the build."""
    for entry in exceptions.get("components", []):
        if "images" in entry and image_repository(image_name) not in entry["images"]:
            continue
        if expr.strip() in entry["licences"] and any(
                identity(eco, entry["name"]) == ident for eco in entry["ecosystems"]):
            return entry
    return None


def reported_licences(art):
    """The licence expressions syft reports for a component ([""] for none),
    without the hashes of unmatched files that are not licence texts."""
    exprs = []
    for entry in art.get("licenses") or []:
        expr = entry.get("spdxExpression") or entry.get("value") or ""
        sources = [url.rsplit("#", 1)[-1] for url in entry.get("urls") or []]
        sources += [loc.get("path", "") for loc in entry.get("locations") or [] if isinstance(loc, dict)]
        if expr.startswith("sha256:") and sources and all(
                NOT_LICENCE_TEXT.search(s) and not LICENCE_FILE_NAME.search(s) for s in sources):
            continue
        exprs.append(expr)
    return exprs or [""]


def corrected(exprs, correction):
    """The licences after a correction, or None when the metadata is not what
    the correction was written for. A correction replaces exactly the
    metadata it records; metadata that already states the corrected licence
    (an image's installed metadata can carry what the registry lacks) needs
    no replacing."""
    reported = sorted({e.strip() for e in exprs if e.strip()})
    expected = [correction["reported"]] if correction["reported"] else []
    if reported not in (expected, [correction["licence"]]):
        return None
    return [correction["licence"]]


def listed_identity(entry):
    """A dev_only entry "ecosystem:name" or "ecosystem:name@version"; without a
    version it covers every version of that package."""
    eco, rest = entry.split(":", 1)
    name, _, version = rest.rpartition("@") if "@" in rest[1:] else (rest, "", "")
    return identity(eco, name) + (version or None,)


def violations(artifacts, root=".", image=False, image_name=None):
    """Components outside the allowlist. For a shipped image (image=True) the
    dev-only exemptions do not apply: whatever is in the image is distributed.
    image_name is the scanned image's repository, for image-scoped exceptions;
    it is ignored unless image is set."""
    image_name = image_name if image else None
    exceptions = load_exceptions(root)
    skip = first_party_names(root)
    listed_dev = set()
    if not image:
        skip |= dev_only_names(root) | pnpm_dev_only_names(root)
        listed_dev = {listed_identity(e) for e in exceptions.get("dev_only", [])}
    corrections = {listed_identity(e["component"]): e for e in exceptions.get("corrections", [])}
    bad = set()
    for art in artifacts:
        name = art.get("name", "?")
        kind = art.get("type", "")
        ident = identity(kind, name)
        version = art.get("version")
        if {ident + (version,), ident + (None,)} & (skip | listed_dev):
            continue
        exprs = reported_licences(art)
        correction = corrections.get(ident + (version,))
        if correction is not None:
            fixed = corrected(exprs, correction)
            if fixed is None:
                bad.add("{}@{}  {} (correction written for: {})".format(
                    name, version or "?", " / ".join(e for e in exprs if e) or "(no licence)",
                    correction["reported"] or "(no licence)"))
                continue
            exprs = fixed
        for expr in exprs:
            if exception_for(ident, expr, exceptions, image_name):
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
    sbom = json.loads(raw)
    artifacts = sbom.get("artifacts", [])
    source = sbom.get("source") or {}
    image_name = source.get("name") if image_mode and source.get("type") == "image" else None
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
        bad = violations(artifacts, image=image_mode, image_name=image_name)
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
