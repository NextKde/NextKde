"""Regression tests for silent CI coverage loss; no external tools or session."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "ci_tests", Path(__file__).resolve().parents[2] / "tools/ci_tests.py")
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)


def test_entry(name, label, **properties):
    return {"name": name, "command": ["test-binary"], "properties": [
        {"name": "LABELS", "value": [label]},
        *({"name": key, "value": value} for key, value in properties.items())]}


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.entries = [test_entry("data", "data"), test_entry("logic", "logic"),
                        test_entry("widget", "widgets"), test_entry("ui", "headless")]
        self.required = {"data-platform": ["data"], "logic": ["logic"],
                         "widgets": ["widget"], "headless": ["ui"]}

    def test_missing_registration_and_changed_label(self):
        self.entries.pop()
        report = ci.inventory(self.entries, self.required)
        self.assertIn("Required test not registered: ui", report["errors"])
        self.entries.append(test_entry("ui", "ui"))
        report = ci.inventory(self.entries, self.required)
        self.assertIn("Required test lacks headless label: ui", report["errors"])

    def test_disabled_and_missing_executable(self):
        self.entries[0] = test_entry("data", "data", DISABLED=True)
        del self.entries[1]["command"]
        errors = ci.inventory(self.entries, self.required)["errors"]
        self.assertIn("Disabled CI test: data", errors)
        self.assertIn("Missing executable for CI test: logic", errors)

    def test_new_labelled_tests_are_automatically_accounted_for(self):
        self.entries.append(test_entry("new", "logic"))
        report = ci.inventory(self.entries, self.required)
        self.assertEqual([], report["errors"])
        self.assertIn("new", report["groups"]["logic"])

    def test_logic_test_cannot_also_belong_to_headless(self):
        self.entries[1]["properties"][0]["value"].append("headless")
        errors = ci.inventory(self.entries, self.required)["errors"]
        self.assertIn("Test selected by multiple groups: logic", errors)

    def test_complete_and_partial_results(self):
        report = ci.inventory(self.entries, self.required)
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for group, names in report["groups"].items():
                (directory / f"{group}.xml").write_text(
                    '<testsuite><testcase name="' + names[0] + '" status="run"/></testsuite>')
            self.assertEqual([], ci.results(report, directory)[1])
            (directory / "headless.xml").write_text(
                '<testsuite><testcase name="ui" status="notrun"><skipped/></testcase></testsuite>')
            (directory / "logic.xml").unlink()
            errors = ci.results(report, directory)[1]
            self.assertIn("Skipped in headless: ui", errors)
            self.assertIn("No result in logic: logic", errors)

    def test_failed_and_malformed_results(self):
        report = ci.inventory(self.entries, self.required)
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "logic.xml").write_text(
                '<testsuite><testcase name="logic"><failure/></testcase></testsuite>')
            (directory / "headless.xml").write_text('<broken')
            errors = ci.results(report, directory)[1]
            self.assertIn("Failed in logic: logic", errors)
            self.assertTrue(any(error.startswith("Invalid headless report:") for error in errors))

    def test_widget_regression_must_run_and_report(self):
        report = ci.inventory(self.entries, self.required)
        self.assertNotIn("widget", report["excluded"])
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            errors = ci.results(report, directory)[1]
            self.assertIn("No result in widgets: widget", errors)


if __name__ == "__main__":
    unittest.main()
