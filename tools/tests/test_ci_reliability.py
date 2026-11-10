#!/usr/bin/env python3
"""VM/CI-only regressions for dependency retry boundaries and failure reporting."""
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import textwrap
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("ci_tests", ROOT / "tools/ci/ci_tests.py")
REPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORT)


class PackageInstallation(unittest.TestCase):
    def install(self, attempts, mirror="Server = https://fastly.mirror.pkgbuild.com/$repo/os/$arch\n"):
        workflow = (ROOT / ".github/workflows/tests.yml").read_text()
        block = re.search(r"(?m)^  KOS_CI_PACMAN: \|\n((?:^    .*\n|^\n)*)", workflow)
        self.assertIsNotNone(block)
        program = textwrap.dedent(block[1])
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / "attempts.json").write_text(json.dumps(attempts))
            mirrorlist = directory / "mirrorlist"
            mirrorlist.write_text(mirror)
            pacman = directory / "pacman"
            pacman.write_text(f"#!{sys.executable}\n" + textwrap.dedent('''\
                import json, os, sys
                from pathlib import Path
                root = Path(os.environ["PACKAGE_FIXTURE"])
                calls = root / "calls.jsonl"
                index = len(calls.read_text().splitlines()) if calls.exists() else 0
                with calls.open("a") as stream:
                    stream.write(json.dumps(sys.argv[1:]) + "\\n")
                attempts = json.loads((root / "attempts.json").read_text())
                status, message = attempts[min(index, len(attempts)-1)]
                print(message)
                sys.exit(status)
                '''))
            pacman.chmod(0o755)
            (directory / "sleep").write_text("#!/bin/sh\nexit 0\n")
            (directory / "sleep").chmod(0o755)
            summary = directory / "summary.md"
            env = dict(os.environ, PATH=f"{directory}:{os.environ['PATH']}",
                       RUNNER_TEMP=tmp, PACKAGE_FIXTURE=tmp,
                       KOS_CI_MIRRORLIST=str(mirrorlist), GITHUB_STEP_SUMMARY=str(summary))
            result = subprocess.run(["bash", "-c", program, "--", "-Syu", "--noconfirm", "git"],
                                    env=env, capture_output=True, text=True, timeout=15)
            calls = [json.loads(line) for line in (directory / "calls.jsonl").read_text().splitlines()]
            return result, calls, mirrorlist.read_text(), summary.read_text() if summary.exists() else ""

    def test_success_has_no_retry(self):
        result, calls, _, summary = self.install([(0, "installed")])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 1)
        self.assertEqual(summary, "")

    def test_download_retry_keeps_transaction_and_adds_fallback(self):
        result, calls, mirror, summary = self.install([
            (1, "error: failed retrieving file 'qt.pkg.tar.zst': Connection timed out"), (0, "installed")])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [["-Syu", "--noconfirm", "git"]] * 2)
        self.assertTrue(mirror.startswith("Server = https://geo.mirror.pkgbuild.com/"))
        self.assertEqual(summary, "")

    def test_exhausted_download_fails_after_three_attempts(self):
        result, calls, _, summary = self.install([(1, "error: failed to retrieve some files")])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(calls), 3)
        self.assertIn("Dependency download failed", summary)

    def test_snapshot_is_never_replaced_by_rolling_mirrors(self):
        original = "Server = https://archive.archlinux.org/repos/2026/05/15/$repo/os/$arch\n"
        result, calls, mirror, _ = self.install([(1, "failed retrieving file"), (0, "ok")], original)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(len(calls), 2)
        self.assertEqual(mirror, original)

    def test_non_transient_errors_never_retry(self):
        for message in ["could not satisfy dependencies", "invalid or corrupted package",
                        "signature is unknown trust", "target not found: missing", "No space left on device",
                        "failed to init transaction", "unrecognised failure"]:
            with self.subTest(message=message):
                result, calls, _, summary = self.install([(1, message)])
                self.assertEqual(result.returncode, 1)
                self.assertEqual(len(calls), 1)
                self.assertIn("Dependency installation failed", summary)

    def test_dependency_error_overrides_download_error(self):
        result, calls, _, _ = self.install([(1, "failed retrieving file\nopenssl breaks dependency libssl")])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(calls), 1)

    def test_interruption_does_not_retry(self):
        result, calls, _, _ = self.install([(143, "failed retrieving file")])
        self.assertEqual(result.returncode, 143)
        self.assertEqual(len(calls), 1)


class FailureReporting(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name) / "test-results"
        self.directory.mkdir()
        self.addCleanup(self.temporary.cleanup)

    def junit(self, name="logic", *, failed=False, message="Assertion failed", output=""):
        suite = ET.Element("testsuite")
        case = ET.SubElement(suite, "testcase", name="example", status="run")
        if failed:
            ET.SubElement(case, "failure", message=message)
        ET.SubElement(case, "system-out").text = output
        ET.ElementTree(suite).write(self.directory / f"{name}.xml")

    def report(self, steps):
        env = dict(os.environ, CI_STEP_OUTCOMES=json.dumps(steps))
        env.pop("GITHUB_STEP_SUMMARY", None)
        return subprocess.run([sys.executable, str(ROOT / "tools/ci/ci_tests.py"), "report",
                               "--build-dir", self.temporary.name], env=env,
                              capture_output=True, text=True, timeout=10)

    def inventory(self):
        (self.directory / "inventory.json").write_text(json.dumps(
            {"groups": {"logic": ["example"]}, "errors": [], "excluded": []}))

    def test_first_failure_uses_execution_order(self):
        summary, errors = REPORT.stage_summary(
            {"headless": {"outcome": "failure"}, "prepare": {"outcome": "failure"}}, self.directory)
        self.assertLess(summary.index("**Build/configuration**"), summary.index("Other unsuccessful"))
        self.assertIn("Missing downstream results do not mean", summary)
        self.assertEqual(len(errors), 2)

    def test_failed_case_is_not_confused_with_successful_warning(self):
        self.junit(failed=True, output="QWARN: missing optional module\nFAIL! assertion\nActual: 7\nExpected: 5")
        detail = REPORT.first_test_failure(self.directory / "logic.xml")
        self.assertEqual(detail[:2], ("example", "Test failure"))
        self.assertIn("Expected: 5", detail[2])
        self.assertNotIn("QWARN", detail[2])
        self.junit(output="QWARN: failure and timeout")
        self.assertIsNone(REPORT.first_test_failure(self.directory / "logic.xml"))

    def test_timeout_and_markup_are_reported_safely(self):
        self.junit(failed=True, message="Timeout", output="<script>payload</script>")
        summary, _ = REPORT.stage_summary({"logic": {"outcome": "failure"}}, self.directory)
        self.assertIn("Timeout: **example**", summary)
        self.assertNotIn("<script>", summary)

    def test_incidental_timeout_warning_does_not_reclassify_assertion(self):
        self.junit(failed=True, output="QWARN: network timeout\nFAIL! values differ")
        detail = REPORT.first_test_failure(self.directory / "logic.xml")
        self.assertEqual(detail[1], "Test failure")

    def test_cancelled_is_not_labelled_as_an_assertion(self):
        summary, errors = REPORT.stage_summary({"headless": {"outcome": "cancelled"}}, self.directory)
        self.assertIn("not evidence of a test assertion failure", summary)
        self.assertTrue(errors)

    def test_missing_inventory_remains_a_failure(self):
        result = self.report({"prepare": {"outcome": "failure"}})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("First unsuccessful stage", result.stdout)
        self.assertIn("No inventory", result.stdout)

    def test_successful_report_keeps_success_exit_code(self):
        self.inventory()
        self.junit()
        result = self.report({"logic": {"outcome": "success"}})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("First unsuccessful stage", result.stdout)

    def test_failure_and_missing_results_still_fail_gate(self):
        self.inventory()
        result = self.report({"logic": {"outcome": "failure"}})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No result in logic", result.stdout)
        self.junit(failed=True)
        result = self.report({"logic": {"outcome": "failure"}})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Failed in logic: example", result.stdout)

    def test_extra_integration_failure_cannot_be_hidden_by_green_groups(self):
        self.inventory()
        self.junit()
        result = self.report({"logic": {"outcome": "success"}, "tray_menu": {"outcome": "failure"}})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Tray menu integration", result.stdout)

    def test_malformed_report_remains_a_failure(self):
        self.inventory()
        (self.directory / "logic.xml").write_text("<invalid")
        result = self.report({"logic": {"outcome": "failure"}})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid logic report", result.stdout)

    def test_skipped_case_still_fails_gate(self):
        self.inventory()
        self.junit()
        path = self.directory / "logic.xml"
        tree = ET.parse(path)
        ET.SubElement(tree.find("testcase"), "skipped")
        tree.write(path)
        result = self.report({"logic": {"outcome": "success"}})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Skipped in logic: example", result.stdout)

    def test_invalid_workflow_outcomes_fail_with_diagnostic(self):
        self.inventory()
        self.junit()
        result = self.report(["not a step mapping"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid workflow outcomes", result.stdout)


if __name__ == "__main__":
    unittest.main()
