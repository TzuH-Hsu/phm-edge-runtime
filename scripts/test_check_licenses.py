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


def art(name, *licences, version="1.0.0"):
    return {"name": name, "version": version, "licenses": [{"value": v} for v in licences]}


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

    def bad(self, *artifacts):
        return cl.violations(list(artifacts), self.root)


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
            "components": [{"name": "libmodbus", "licences": ["LGPL-2.1-or-later"], "reason": "test"}],
            "dev_only": ["certifi"],
        }))

    def test_named_component_with_listed_licence_passes(self):
        self.assertEqual(self.bad(art("libmodbus", "LGPL-2.1-or-later")), set())

    def test_same_licence_on_another_component_fails(self):
        self.assertTrue(self.bad(art("libfoo", "LGPL-2.1-or-later")))

    def test_named_component_with_unlisted_licence_fails(self):
        self.assertTrue(self.bad(art("libmodbus", "GPL-3.0-only")))

    def test_dev_only_listing_is_skipped(self):
        self.assertEqual(self.bad(art("certifi", "MPL-2.0")), set())

    def test_entry_without_reason_is_rejected(self):
        self.write("scripts/licence-exceptions.json", json.dumps({
            "components": [{"name": "libmodbus", "licences": ["LGPL-2.1-or-later"]}]}))
        with self.assertRaises(ValueError):
            self.bad(art("libmodbus", "LGPL-2.1-or-later"))


class FirstPartyTest(RepoCase):
    def test_own_packages_are_skipped(self):
        self.write("web/package.json", json.dumps({"name": "phm-web"}))
        self.write("backend/pyproject.toml", '[project]\nname = "phm_backend"\n')
        self.write("go.mod", "module example.com/phm\n")
        self.assertEqual(self.bad(art("phm-web"), art("phm-backend"), art("example.com/phm")), set())

    def test_other_unlicensed_packages_still_fail(self):
        self.write("package.json", json.dumps({"name": "phm-web"}))
        self.assertTrue(self.bad(art("left-pad")))


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
        self.assertEqual(self.bad(art("pytest", "GPL-2.0-only"), art("certifi", "MPL-2.0")), set())

    def test_package_also_shipped_is_still_checked(self):
        self.assertTrue(self.bad(art("httpx", "GPL-3.0-only")))

    def test_shipped_dependency_is_checked(self):
        self.assertTrue(self.bad(art("fastapi", "AGPL-3.0-only")))


if __name__ == "__main__":
    unittest.main()
