# SPDX-License-Identifier: Apache-2.0
"""Unit tests for scripts/check-licenses.py (run: python3 -m unittest scripts/test_check_licenses.py)."""
import importlib.util
import json
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("check_licenses", os.path.join(HERE, "check-licenses.py"))
cl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cl)


def art(name, *licences, version="1.0.0", kind="python"):
    return {"name": name, "version": version, "type": kind,
            "licenses": [{"value": v} for v in licences]}


class RepoCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel, text):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)

    def bad(self, *artifacts, image=False, image_name=None):
        return cl.violations(list(artifacts), self.root, image=image, image_name=image_name)


class AllowlistTest(RepoCase):
    def test_notice_only_licences_pass(self):
        for licence in ("curl", "blessing", "Zlib", "PSF-2.0", "PostgreSQL", "BSL-1.0", "CC-BY-4.0"):
            self.assertEqual(self.bad(art("x", licence)), set(), licence)

    def test_copyleft_and_restrictive_licences_fail(self):
        for licence in ("GPL-3.0-only", "AGPL-3.0-only", "LGPL-2.1-or-later", "SSPL-1.0", "MPL-2.0"):
            self.assertTrue(self.bad(art("x", licence)), licence)

    def test_missing_licence_fails(self):
        self.assertTrue(self.bad(art("x")))

    def test_unambiguous_free_text_name_is_read_as_its_spdx_id(self):
        self.assertEqual(self.bad(art("x", "MIT License"), art("y", "Apache License 2.0")), set())

    def test_ambiguous_free_text_name_fails(self):
        self.assertTrue(self.bad(art("x", "BSD License")))


class ExceptionTest(RepoCase):
    def setUp(self):
        super().setUp()
        self.write("scripts/licence-exceptions.json", json.dumps({
            "components": [{"name": "libmodbus", "ecosystems": ["conan"],
                            "licences": ["LGPL-2.1-or-later"], "reason": "test"}],
            "dev_only": ["python:certifi"],
        }))

    def test_named_component_with_listed_licence_passes(self):
        self.assertEqual(self.bad(art("libmodbus", "LGPL-2.1-or-later", kind="conan")), set())

    def test_lgpl_2_1_only_is_not_covered_by_the_or_later_entry(self):
        self.assertTrue(self.bad(art("libmodbus", "LGPL-2.1-only", kind="conan")))

    def test_same_name_in_another_ecosystem_gets_no_exception(self):
        self.assertTrue(self.bad(art("libmodbus", "LGPL-2.1-or-later", kind="npm")))

    def test_dev_only_listing_is_scoped_to_its_ecosystem(self):
        self.assertTrue(self.bad(art("certifi", "MPL-2.0", kind="npm")))

    def test_licences_given_as_a_string_is_rejected(self):
        self.write("scripts/licence-exceptions.json", json.dumps({"components": [
            {"name": "libmodbus", "ecosystems": ["conan"], "licences": "LGPL-2.1-or-later", "reason": "x"}]}))
        with self.assertRaises(ValueError):
            self.bad(art("x", "MIT"))

    def test_versioned_dev_only_entry_covers_only_that_version(self):
        self.write("scripts/licence-exceptions.json", json.dumps({"components": [],
                                                                   "dev_only": ["npm:eslint@9.1.0"]}))
        self.assertEqual(self.bad(art("eslint", "GPL-3.0-only", version="9.1.0", kind="npm")), set())
        self.assertTrue(self.bad(art("eslint", "GPL-3.0-only", version="8.0.0", kind="npm")))

    def test_bare_dev_only_entry_is_rejected(self):
        self.write("scripts/licence-exceptions.json", json.dumps({"components": [], "dev_only": ["certifi"]}))
        with self.assertRaises(ValueError):
            self.bad(art("x", "MIT"))

    def test_same_licence_on_another_component_fails(self):
        self.assertTrue(self.bad(art("libfoo", "LGPL-2.1-or-later")))

    def test_named_component_with_unlisted_licence_fails(self):
        self.assertTrue(self.bad(art("libmodbus", "GPL-3.0-only", kind="conan")))

    def test_dev_only_listing_is_skipped(self):
        self.assertEqual(self.bad(art("certifi", "MPL-2.0")), set())

    def test_entry_without_reason_is_rejected(self):
        self.write("scripts/licence-exceptions.json", json.dumps({
            "components": [{"name": "libmodbus", "ecosystems": ["conan"], "licences": ["LGPL-2.1-or-later"]}]}))
        with self.assertRaises(ValueError):
            self.bad(art("libmodbus", "LGPL-2.1-or-later", kind="conan"))


class CorrectionTest(RepoCase):
    def setUp(self):
        super().setUp()
        self.write("scripts/licence-exceptions.json", json.dumps({"corrections": [
            {"component": "python:classifier-only@1.0", "licence": "BSD-3-Clause", "reported": "",
             "reason": "LICENSE.txt"},
            {"component": "python:dual@1.0", "licence": "MIT", "reported": "Dual License",
             "reason": "LICENSE"},
            {"component": "python:mislabelled@1.0", "licence": "GPL-3.0-only", "reported": "",
             "reason": "LICENSE"},
        ]}))

    def test_correction_applies_where_the_metadata_reports_no_licence(self):
        self.assertEqual(self.bad(art("classifier-only", version="1.0"),
                                  art("Classifier_Only", version="1.0")), set())

    def test_correction_applies_to_the_exact_text_it_was_written_for(self):
        self.assertEqual(self.bad(art("dual", "Dual License", version="1.0")), set())

    def test_any_other_metadata_fails(self):
        for text in ("GPL-3.0-only", "GNU General Public License v3 (GPLv3)",
                     "Non-Commercial License", "Commercial License",
                     "CeCILL Free Software License Agreement v2.1", "MIT", "Dual License"):
            self.assertTrue(self.bad(art("classifier-only", text, version="1.0")), text)

    def test_metadata_that_states_the_corrected_licence_passes(self):
        self.assertEqual(self.bad(art("classifier-only", "BSD-3-Clause", version="1.0"),
                                  art("dual", "MIT", version="1.0")), set())

    def test_metadata_that_no_longer_reports_the_recorded_text_fails(self):
        self.assertTrue(self.bad(art("dual", version="1.0")))

    def test_correction_names_one_version(self):
        self.assertTrue(self.bad(art("classifier-only", version="2.0")))

    def test_corrected_licence_is_still_judged(self):
        self.assertTrue(self.bad(art("mislabelled", version="1.0")))

    def test_correction_without_a_version_is_rejected(self):
        self.write("scripts/licence-exceptions.json", json.dumps({"corrections": [
            {"component": "python:any", "licence": "MIT", "reported": "", "reason": "x"}]}))
        with self.assertRaises(ValueError):
            self.bad(art("any", "MIT"))

    def test_correction_without_the_reported_text_is_rejected(self):
        self.write("scripts/licence-exceptions.json", json.dumps({"corrections": [
            {"component": "python:any@1.0", "licence": "MIT", "reason": "x"}]}))
        with self.assertRaises(ValueError):
            self.bad(art("any", version="1.0"))


class FirstPartyTest(RepoCase):
    def test_own_packages_are_skipped(self):
        self.write("web/package.json", json.dumps({"name": "phm-web"}))
        self.write("backend/pyproject.toml", '[project]\nname = "phm_backend"\n')
        self.write("go.mod", "module example.com/phm\n")
        self.assertEqual(self.bad(art("phm-web", kind="npm"), art("phm-backend"),
                                  art("example.com/phm", kind="go-module")), set())

    def test_poetry_project_name_is_first_party(self):
        self.write("pyproject.toml", '[tool.poetry]\nname = "phm-tools"\n')
        self.assertEqual(self.bad(art("phm_tools")), set())

    def test_other_version_of_a_first_party_name_is_checked(self):
        self.write("package.json", json.dumps({"name": "same", "version": "1.0.0"}))
        self.assertTrue(self.bad(art("same", "GPL-3.0-only", version="9.9.9", kind="npm")))

    def test_vendored_manifest_is_not_first_party(self):
        self.write("vendor/crate/Cargo.toml", '[package]\nname = "vendored"\nversion = "1.0.0"\n')
        self.assertTrue(self.bad(art("vendored", kind="rust-crate")))

    def test_manifest_in_build_output_is_not_first_party(self):
        self.write("build/_deps/dep/package.json", json.dumps({"name": "generated"}))
        self.assertTrue(self.bad(art("generated", kind="npm")))

    def test_same_name_in_another_ecosystem_is_not_first_party(self):
        self.write("backend/pyproject.toml", '[project]\nname = "acme_backend"\n')
        self.assertTrue(self.bad(art("acme-backend", "GPL-3.0-only", kind="npm")))

    def test_other_unlicensed_packages_still_fail(self):
        self.write("package.json", json.dumps({"name": "phm-web"}))
        self.assertTrue(self.bad(art("left-pad", kind="npm")))


UV_LOCK = """
version = 1

[[package]]
name = "phm-backend"
version = "0.1.0"
source = { virtual = "." }
dependencies = [{ name = "fastapi" }]

[package.dev-dependencies]
dev = [{ name = "pytest" }, { name = "httpx" }]

[[package]]
name = "fastapi"
version = "1.0"
source = { registry = "https://pypi.org/simple" }
dependencies = [{ name = "httpx" }]

[[package]]
name = "httpx"
version = "1.0"
source = { registry = "https://pypi.org/simple" }

[[package]]
name = "pytest"
version = "1.0"
source = { registry = "https://pypi.org/simple" }
dependencies = [{ name = "certifi" }]

[[package]]
name = "certifi"
version = "1.0"
source = { registry = "https://pypi.org/simple" }
"""


class UvDevOnlyTest(RepoCase):
    def setUp(self):
        super().setUp()
        self.write("backend/uv.lock", UV_LOCK)

    def test_dev_group_and_its_closure_are_skipped(self):
        self.assertEqual(self.bad(art("pytest", "GPL-2.0-only", version="1.0"),
                                  art("certifi", "MPL-2.0", version="1.0")), set())

    def test_other_version_of_a_dev_package_is_checked(self):
        self.assertTrue(self.bad(art("pytest", "GPL-2.0-only", version="9.0")))

    def test_image_scan_ignores_dev_only_exemptions(self):
        self.assertTrue(self.bad(art("pytest", "GPL-2.0-only", version="1.0"), image=True))

    def test_package_also_shipped_is_still_checked(self):
        self.assertTrue(self.bad(art("httpx", "GPL-3.0-only")))

    def test_shipped_dependency_is_checked(self):
        self.assertTrue(self.bad(art("fastapi", "AGPL-3.0-only")))


PNPM_LOCK = """lockfileVersion: '9.0'

settings:
  autoInstallPeers: true

importers:

  .:
    dependencies:
      react-dom:
        specifier: 1.0.0
        version: 1.0.0(react@1.0.0)
    devDependencies:
      '@build/tool':
        specifier: 2.0.0
        version: 2.0.0(react@1.0.0)
      width-cjs:
        specifier: npm:width@3.0.0
        version: width@3.0.0

packages:

  '@build/tool@2.0.0':
    resolution: {integrity: sha512-x}

snapshots:

  '@build/tool@2.0.0(react@1.0.0)':
    dependencies:
      css-min: 1.0.0
      shared: 1.0.0
    transitivePeerDependencies:
      - supports-color

  css-min@1.0.0: {}

  react-dom@1.0.0(react@1.0.0):
    dependencies:
      react: 1.0.0
      shared: 1.0.0
    optionalDependencies:
      native: 1.0.0

  native@1.0.0:
    optional: true

  react@1.0.0: {}

  shared@1.0.0: {}

  width@3.0.0: {}
"""


class PnpmDevOnlyTest(RepoCase):
    def setUp(self):
        super().setUp()
        self.write("frontend/pnpm-lock.yaml", PNPM_LOCK)

    def npm(self, name, *licences, version="1.0.0"):
        return art(name, *licences, version=version, kind="npm")

    def test_dev_dependency_and_its_closure_are_skipped(self):
        self.assertEqual(self.bad(self.npm("@build/tool", "GPL-3.0-only", version="2.0.0"),
                                  self.npm("css-min", "MPL-2.0")), set())

    def test_aliased_dev_dependency_is_skipped(self):
        self.assertEqual(self.bad(self.npm("width", "GPL-3.0-only", version="3.0.0")), set())

    def test_shipped_closure_is_checked(self):
        self.assertTrue(self.bad(self.npm("react", "GPL-3.0-only")))
        self.assertTrue(self.bad(self.npm("native", "GPL-3.0-only")))

    def test_package_reached_from_both_sides_is_checked(self):
        self.assertTrue(self.bad(self.npm("shared", "GPL-3.0-only")))

    def test_other_version_of_a_dev_package_is_checked(self):
        self.assertTrue(self.bad(self.npm("css-min", "MPL-2.0", version="9.0.0")))

    def test_image_scan_ignores_dev_only_exemptions(self):
        self.assertTrue(self.bad(self.npm("css-min", "MPL-2.0"), image=True))

    def test_closure_of_a_file_dependency_is_shipped(self):
        self.write("frontend/pnpm-lock.yaml", PNPM_LOCK.replace(
            """    devDependencies:
      '@build/tool':""",
            """      local-lib:
        specifier: file:./local-lib
        version: file:local-lib
    devDependencies:
      '@build/tool':""").replace(
            """  css-min@1.0.0: {}""",
            """  css-min@1.0.0: {}

  local-lib@file:local-lib:
    dependencies:
      css-min: 1.0.0"""))
        self.assertTrue(self.bad(self.npm("css-min", "GPL-3.0-only")))

    def test_file_dependency_with_an_at_sign_in_its_path_is_shipped(self):
        self.write("frontend/pnpm-lock.yaml", PNPM_LOCK.replace(
            """    devDependencies:
      '@build/tool':""",
            """      local-lib:
        specifier: file:./libs@local/lib
        version: file:libs@local/lib
    devDependencies:
      '@build/tool':""").replace(
            """  css-min@1.0.0: {}""",
            """  css-min@1.0.0: {}

  local-lib@file:libs@local/lib:
    dependencies:
      css-min: 1.0.0"""))
        self.assertTrue(self.bad(self.npm("css-min", "GPL-3.0-only")))

    def test_file_dependency_with_a_quote_and_colon_in_its_path_is_shipped(self):
        # pnpm writes such a path as a single-quoted scalar with the quote doubled.
        self.write("frontend/pnpm-lock.yaml", PNPM_LOCK.replace(
            """    devDependencies:
      '@build/tool':""",
            """      local-lib:
        specifier: 'file:./libs: ''x'
        version: 'file:libs: ''x'
    devDependencies:
      '@build/tool':""").replace(
            """  css-min@1.0.0: {}""",
            """  css-min@1.0.0: {}

  'local-lib@file:libs: ''x':
    dependencies:
      css-min: 1.0.0"""))
        self.assertTrue(self.bad(self.npm("css-min", "GPL-3.0-only")))

    def test_git_dependency_over_ssh_is_shipped(self):
        self.write("frontend/pnpm-lock.yaml", PNPM_LOCK.replace(
            """    devDependencies:
      '@build/tool':""",
            """      git-lib:
        specifier: git+ssh://git@example.com/org/git-lib.git
        version: git+ssh://git@example.com/org/git-lib.git#abc123
    devDependencies:
      '@build/tool':""").replace(
            """  css-min@1.0.0: {}""",
            """  css-min@1.0.0: {}

  git-lib@git+ssh://git@example.com/org/git-lib.git#abc123:
    dependencies:
      css-min: 1.0.0"""))
        self.assertTrue(self.bad(self.npm("css-min", "GPL-3.0-only")))

    def test_dependency_without_a_snapshot_fails_the_check(self):
        self.write("frontend/pnpm-lock.yaml", PNPM_LOCK.replace(
            "  css-min@1.0.0: {}\n", ""))
        with self.assertRaises(ValueError):
            self.bad(self.npm("css-min", "MIT"))

    def test_dev_only_identity_keeps_at_signs_in_the_locator(self):
        self.write("frontend/pnpm-lock.yaml", PNPM_LOCK.replace(
            """      width-cjs:""",
            """      local-tool:
        specifier: file:./libs@local/tool
        version: file:libs@local/tool
      '@scope/git-tool':
        specifier: git+ssh://git@example.com/org/git-tool.git
        version: git+ssh://git@example.com/org/git-tool.git#abc123
      width-cjs:""").replace(
            """  css-min@1.0.0: {}""",
            """  css-min@1.0.0: {}

  local-tool@file:libs@local/tool: {}

  '@scope/git-tool@git+ssh://git@example.com/org/git-tool.git#abc123': {}"""))
        self.assertEqual(self.bad(
            self.npm("local-tool", "GPL-3.0-only", version="file:libs@local/tool"),
            self.npm("@scope/git-tool", "GPL-3.0-only",
                     version="git+ssh://git@example.com/org/git-tool.git#abc123")), set())

    def test_package_key_is_found_among_the_lockfile_packages(self):
        packages = {"react-dom@1.0.0", "@a/b@2.0.0", "local-tool@file:../libs(x)/tool",
                    "local-tool@file:../libs/(react@1.0.0)"}
        cases = {
            "react-dom@1.0.0(react@1.0.0)": "react-dom@1.0.0",
            "@a/b@2.0.0(@c/d@1.0.0(e@1.0.0))(e@1.0.0)": "@a/b@2.0.0",
            "local-tool@file:../libs(x)/tool": "local-tool@file:../libs(x)/tool",
            "local-tool@file:../libs/(react@1.0.0)": "local-tool@file:../libs/(react@1.0.0)",
            "local-tool@file:../libs/(react@1.0.0)(react@1.0.0)": "local-tool@file:../libs/(react@1.0.0)",
        }
        for key, expected in cases.items():
            self.assertEqual(cl.pnpm_package_key(key, packages), expected, key)

    def test_peer_context_is_stripped_by_shape_without_a_package_entry(self):
        self.assertEqual(cl.pnpm_package_key("x@1.0.0(react@1.0.0)", set()), "x@1.0.0")
        self.assertEqual(cl.pnpm_package_key("x@file:../libs(x)/tool", set()), "x@file:../libs(x)/tool")

    def test_package_key_splits_at_the_name(self):
        self.assertEqual(cl.pnpm_package("@a/b@file:../libs/(react@1.0.0)"),
                         ("@a/b", "file:../libs/(react@1.0.0)"))

    def test_unsupported_escape_fails_the_check(self):
        self.write("frontend/pnpm-lock.yaml", PNPM_LOCK.replace(
            "  css-min@1.0.0: {}", '  "css-min@1.0.0\\n": {}'))
        with self.assertRaises(ValueError):
            self.bad(self.npm("css-min", "MIT"))

    def test_lockfile_with_a_package_manager_document_first(self):
        # pnpm records its own version in a first YAML document when the
        # project pins it; the project's lock follows as a second document.
        self.write("frontend/pnpm-lock.yaml", """---
lockfileVersion: '9.0'

importers:

  .:
    configDependencies: {}
    packageManagerDependencies:
      pnpm:
        specifier: 12.6.0
        version: 12.6.0

snapshots:

  pnpm@12.6.0: {}

---
""" + PNPM_LOCK)
        self.assertEqual(self.bad(self.npm("css-min", "MPL-2.0")), set())
        self.assertTrue(self.bad(self.npm("react", "GPL-3.0-only")))

    def test_other_lockfile_version_is_rejected(self):
        self.write("frontend/pnpm-lock.yaml", "lockfileVersion: '6.0'\n")
        with self.assertRaises(ValueError):
            self.bad(self.npm("css-min", "MIT"))


class SubmoduleBoundaryTest(RepoCase):
    SUBMODULE_PNPM_LOCK = """lockfileVersion: '9.0'

importers:

  .:
    dependencies:
      css-min:
        specifier: 1.0.0
        version: 1.0.0

packages:

  css-min@1.0.0:
    resolution: {integrity: sha512-x}

snapshots:

  css-min@1.0.0: {}
"""

    def test_dev_package_that_a_submodule_ships_is_checked(self):
        self.write("frontend/pnpm-lock.yaml", PNPM_LOCK)
        self.write("vendor/lib/.git", "gitdir: ../../.git/modules/lib\n")
        self.write("vendor/lib/pnpm-lock.yaml", self.SUBMODULE_PNPM_LOCK)
        self.assertTrue(self.bad(art("css-min", "MPL-2.0", kind="npm")))

    def test_dev_group_of_a_submodule_grants_no_exemption(self):
        self.write("vendor/lib/.git", "gitdir: ../../.git/modules/lib\n")
        self.write("vendor/lib/uv.lock", UV_LOCK)
        self.assertTrue(self.bad(art("certifi", "MPL-2.0", version="1.0")))

    def test_package_inside_a_submodule_is_not_first_party(self):
        self.write("vendor/lib/package.json", json.dumps({"name": "vendored-lib"}))
        self.write("vendor/lib/.git", "gitdir: ../../.git/modules/lib\n")
        self.assertTrue(self.bad(art("vendored-lib", kind="npm")))


class UvAcrossLocksTest(RepoCase):
    def test_dev_in_one_lock_but_shipped_by_another_is_checked(self):
        self.write("backend/uv.lock", UV_LOCK)
        self.write("worker/uv.lock", """
version = 1

[[package]]
name = "phm-worker"
version = "0.1.0"
source = { virtual = "." }
dependencies = [{ name = "certifi" }]

[[package]]
name = "certifi"
version = "1.0"
source = { registry = "https://pypi.org/simple" }
""")
        self.assertTrue(self.bad(art("certifi", "MPL-2.0")))



class ImageOsPackageTest(RepoCase):
    def test_gpl_os_package_passes_in_an_image(self):
        self.assertEqual(self.bad(art("bash", "GPL-3.0-or-later", kind="deb"), image=True), set())

    def test_restricted_service_os_package_fails_in_an_image(self):
        self.assertTrue(self.bad(art("mongodb", "SSPL-1.0", kind="deb"), image=True))

    def test_excepted_os_package_passes_in_an_image(self):
        self.write("scripts/licence-exceptions.json", json.dumps({"components": [
            {"name": "timescaledb", "ecosystems": ["apk"], "licences": ["LicenseRef-Timescale"], "reason": "t"}]}))
        self.assertEqual(self.bad(art("timescaledb", "LicenseRef-Timescale", kind="apk"), image=True), set())


class ImageScopedExceptionTest(RepoCase):
    def setUp(self):
        super().setUp()
        self.write("scripts/licence-exceptions.json", json.dumps({"components": [
            {"name": "github.com/hashicorp/raft", "ecosystems": ["go-module"], "licences": ["MPL-2.0"],
             "images": ["chrislusf/seaweedfs"], "reason": "t"}]}))
        self.raft = art("github.com/hashicorp/raft", "MPL-2.0", kind="go-module")

    def test_exception_applies_in_a_scan_of_the_listed_image(self):
        for name in ("chrislusf/seaweedfs", "docker.io/chrislusf/seaweedfs"):
            self.assertEqual(self.bad(self.raft, image=True, image_name=name), set(), name)

    def test_exception_does_not_apply_to_another_image(self):
        self.assertTrue(self.bad(self.raft, image=True, image_name="phm-platform/backend"))

    def test_exception_does_not_apply_outside_an_image_scan(self):
        self.assertTrue(self.bad(self.raft))
        self.assertTrue(self.bad(self.raft, image_name="chrislusf/seaweedfs"))

    def test_images_given_as_a_string_is_rejected(self):
        self.write("scripts/licence-exceptions.json", json.dumps({"components": [
            {"name": "x", "ecosystems": ["go-module"], "licences": ["MPL-2.0"],
             "images": "chrislusf/seaweedfs", "reason": "t"}]}))
        with self.assertRaises(ValueError):
            self.bad(art("x", "MIT"))


def hashed(path, url=True):
    entry = {"value": "sha256:" + "0" * 64}
    if url:
        entry["urls"] = ["https://proxy.golang.org/m/@v/v1.0.0.zip#m@v1.0.0/" + path]
    else:
        entry["locations"] = [{"path": "/src/" + path}]
    return entry


class UnmatchedLicenceFileTest(RepoCase):
    def module(self, *entries):
        return {"name": "m", "version": "v1.0.0", "type": "go-module",
                "licenses": [{"value": "Apache-2.0", "spdxExpression": "Apache-2.0"}, *entries]}

    def test_hash_of_a_notice_file_is_dropped(self):
        self.assertEqual(self.bad(self.module(hashed("NOTICE"), hashed("NOTICE.txt", url=False))), set())

    def test_hash_of_a_source_or_ci_file_is_dropped(self):
        self.assertEqual(self.bad(self.module(hashed("pgproto3/notice_response.go"),
                                              hashed(".github/workflows/license_check.yml"))), set())

    def test_hash_of_an_unmatched_licence_file_fails(self):
        for path in ("LICENSE", "COPYING", "LICENSE.md", "LICENSE.json", "COPYING.py", "licenses/custom.go"):
            self.assertTrue(self.bad(self.module(hashed(path))), path)

    def test_hash_without_a_source_file_fails(self):
        self.assertTrue(self.bad(self.module({"value": "sha256:" + "0" * 64})))

    def test_component_with_only_a_notice_hash_has_no_licence(self):
        self.assertTrue(self.bad({"name": "m", "version": "v1", "type": "go-module",
                                  "licenses": [hashed("NOTICE")]}))


if __name__ == "__main__":
    unittest.main()
