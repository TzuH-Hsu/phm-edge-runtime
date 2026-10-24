# SPDX-License-Identifier: Apache-2.0
"""Unit tests for scripts/check-sql.py (run: python3 -m unittest scripts/test_check_sql.py)."""
import contextlib
import importlib.util
import io
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(HERE, "..", "tests", "fixtures", "sql_check")
spec = importlib.util.spec_from_file_location("check_sql", os.path.join(HERE, "check-sql.py"))
cs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cs)


def run(*paths):
    """Runs main() and returns (exit status, stderr text)."""
    err = io.StringIO()
    with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
        status = cs.main(["check-sql.py", *paths])
    return status, err.getvalue()


class FixtureTest(unittest.TestCase):
    def test_select_star_fails_and_names_file_and_line(self):
        path = os.path.join(FIXTURES, "select_star.txt")
        status, err = run(path)
        self.assertEqual(status, 1)
        self.assertIn(f"{path}:2: SELECT *", err)

    def test_insert_without_columns_fails_and_names_file_and_line(self):
        path = os.path.join(FIXTURES, "insert_without_columns.txt")
        status, err = run(path)
        self.assertEqual(status, 1)
        self.assertIn(f"{path}:2: INSERT without a column list", err)

    def test_named_columns_pass(self):
        status, err = run(os.path.join(FIXTURES, "named_columns.txt"))
        self.assertEqual(status, 0, err)
        self.assertEqual(err, "")

    def test_library_sources_pass(self):
        status, err = run(os.path.join(HERE, "..", "src"))
        self.assertEqual(status, 0, err)


class PatternTest(unittest.TestCase):
    def lines(self, text):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "sample.cpp")
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
            return [line for line, _ in cs.findings(path)]

    def test_insert_variants_without_columns_fail(self):
        for sql in (
            '"insert into queue_items values (1)"',
            '"INSERT OR IGNORE INTO queue_drop_record VALUES (1)"',
            '"INSERT INTO main.queue_items SELECT seq FROM other"',
            '"INSERT INTO queue_items DEFAULT VALUES"',
            '"REPLACE INTO queue_items VALUES (1)"',
        ):
            with self.subTest(sql=sql):
                self.assertEqual(self.lines(sql), [1])

    def test_insert_with_columns_passes_even_without_a_space(self):
        for sql in (
            '"INSERT INTO queue_items(item_key) VALUES (?)"',
            '"INSERT OR IGNORE INTO queue_drop_record (id) VALUES (1)"',
        ):
            with self.subTest(sql=sql):
                self.assertEqual(self.lines(sql), [])

    def test_statement_split_across_string_literals_is_checked(self):
        self.assertEqual(self.lines('x;\n"SELECT "\n  "* FROM queue_items"\n'), [2])
        self.assertEqual(self.lines('"INSERT INTO queue_items "\n"(item_key) VALUES (?)"\n'), [])
        self.assertEqual(self.lines('"INSERT INTO queue_items "\n"VALUES (?)"\n'), [1])

    def test_count_star_and_select_distinct_star(self):
        self.assertEqual(self.lines('"SELECT count(*) FROM queue_items"'), [])
        self.assertEqual(self.lines('"SELECT DISTINCT * FROM queue_items"'), [1])

    def test_missing_path_is_an_error(self):
        status, err = run(os.path.join(FIXTURES, "does-not-exist"))
        self.assertEqual(status, 2)
        self.assertIn("no such path", err)


if __name__ == "__main__":
    unittest.main()
