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

    def bad(self, *artifacts, image=False):
        return cl.violations(list(artifacts), self.root, image=image)


class AllowlistTest(RepoCase):
    def test_notice_only_licences_pass(self):
        for licence in ("curl", "blessing", "Zlib", "PSF-2.0", "PostgreSQL", "BSL-1.0", "CC-BY-4.0"):
            self.assertEqual(self.bad(art("x", licence)), set(), licence)

    def test_copyleft_and_restrictive_licences_fail(self):
        for licence in ("GPL-3.0-only", "AGPL-3.0-only", "LGPL-2.1-or-later", "SSPL-1.0", "MPL-2.0"):
            self.assertTrue(self.bad(art("x", licence)), licence)

    def test_missing_licence_fails(self):
        self.assertTrue(self.bad(art("x")))


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


class SubmoduleBoundaryTest(RepoCase):
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

if __name__ == "__main__":
    unittest.main()
