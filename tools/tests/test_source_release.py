"""Run in a VM or hosted CI only; never installs or launches the desktop."""
import importlib.util
import io
import json
import os
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

spec = importlib.util.spec_from_file_location("source_release", Path(__file__).parents[1] / "source-release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.remote = Path(self.workspace.name) / "origin"
        self.root = Path(self.workspace.name) / "checkout"
        self.remote.mkdir()
        self.git(self.remote, "init", "-b", "main")
        self.git(self.remote, "config", "user.name", "VM Test")
        self.git(self.remote, "config", "user.email", "vm@example.invalid")
        (self.remote / "VERSION").write_text("0.1.0\n")
        self.git(self.remote, "add", "VERSION")
        self.git(self.remote, "commit", "-m", "first release")
        self.git(self.remote, "tag", "-a", "v0.1.0", "-m", "first release")
        self.first = self.git(self.remote, "rev-parse", "HEAD")
        (self.remote / "VERSION").write_text("0.2.0-dev\n")
        self.git(self.remote, "commit", "-am", "continue development")
        self.git(self.remote, "tag", "v9.9.9")  # deliberately mismatched tag
        self.latest = self.git(self.remote, "rev-parse", "HEAD")
        subprocess.run(["git", "clone", str(self.remote), str(self.root)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    @staticmethod
    def git(root, *args):
        return subprocess.check_output(["git", "-C", str(root), *args], text=True, stderr=subprocess.DEVNULL).strip()

    def test_explicit_annotated_tag_selects_exact_commit(self):
        release.select(self.root, "v0.1.0")
        self.assertEqual(self.git(self.root, "rev-parse", "HEAD"), self.first)
        self.assertEqual(self.git(self.root, "rev-parse", "main"), self.latest)
        self.assertEqual(release.identity(self.root)["version"], "0.1.0")

    def test_stable_resolves_then_uses_exact_tag(self):
        with patch.object(release, "latest_release", return_value="v0.1.0"):
            release.select(self.root, "stable")
        self.assertEqual(self.git(self.root, "rev-parse", "HEAD"), self.first)

    def test_development_can_follow_detached_tag(self):
        release.select(self.root, "v0.1.0")
        release.select(self.root, "main")
        self.assertEqual(self.git(self.root, "rev-parse", "HEAD"), self.latest)

    def test_untracked_file_blocks_switch(self):
        (self.root / "personal.qml").write_text("keep this")
        with self.assertRaisesRegex(ValueError, "local changes"):
            release.select(self.root, "v0.1.0")
        self.assertEqual((self.root / "personal.qml").read_text(), "keep this")
        self.assertEqual(self.git(self.root, "rev-parse", "HEAD"), self.latest)

    def test_modified_version_blocks_switch(self):
        (self.root / "VERSION").write_text("0.3.0-dev\n")
        with self.assertRaisesRegex(ValueError, "local changes"):
            release.select(self.root, "v0.1.0")

    def test_failed_fetch_does_not_reuse_previous_fetch_head(self):
        release.select(self.root, "v0.1.0")
        with self.assertRaises(subprocess.CalledProcessError):
            release.select(self.root, "v8.8.8")
        self.assertEqual(self.git(self.root, "rev-parse", "HEAD"), self.first)

    def test_wrong_tag_version_does_not_checkout(self):
        with self.assertRaisesRegex(ValueError, "disagrees"):
            release.select(self.root, "v9.9.9")
        self.assertEqual(self.git(self.root, "rev-parse", "HEAD"), self.latest)

    def test_other_repository_does_not_change_origin(self):
        with self.assertRaisesRegex(ValueError, "differs"):
            release.select(self.root, "main", "https://github.com/other/repository.git")
        self.assertEqual(self.git(self.root, "remote", "get-url", "origin"), str(self.remote))

    def test_stamp_is_snapshot_not_current_checkout(self):
        record = Path(self.workspace.name) / "installed" / "release.json"
        release.write_identity(record, release.identity(self.root))
        release.select(self.root, "v0.1.0")
        self.assertEqual(json.loads(record.read_text())["revision"], self.latest)
        self.assertEqual(release.identity(self.root)["revision"], self.first)

    def test_archive_does_not_inherit_enclosing_git_identity(self):
        archive = self.root / "archive"
        archive.mkdir()
        (archive / "VERSION").write_text("0.1.0\n")
        self.assertEqual(release.identity(archive)["revision"], "unknown")


class ApiTests(unittest.TestCase):
    def test_no_release_does_not_fall_back_to_main(self):
        error = urllib.error.HTTPError("https://api.github.com", 404, "Not Found", {}, None)
        with patch.object(release.urllib.request, "urlopen", side_effect=error):
            with self.assertRaisesRegex(ValueError, "No latest official release"):
                release.latest_release("https://github.com/SuceV587/NextKde.git")

    def test_prerelease_rejected_even_if_api_returns_it(self):
        payload = io.BytesIO(json.dumps({"tag_name": "v0.1.0-rc.1", "prerelease": True}).encode())
        with patch.object(release.urllib.request, "urlopen", return_value=payload):
            with self.assertRaisesRegex(ValueError, "not a stable"):
                release.latest_release("https://github.com/SuceV587/NextKde.git")

    def test_canonical_api_repository_and_stable_tag(self):
        payload = io.BytesIO(json.dumps({"tag_name": "v0.1.0", "prerelease": False, "draft": False}).encode())
        with patch.object(release.urllib.request, "urlopen", return_value=payload) as request:
            self.assertEqual(release.latest_release("https://github.com/SuceV587/NextKde.git"), "v0.1.0")
        self.assertEqual(request.call_args.args[0].full_url, "https://api.github.com/repos/SuceV587/NextKde/releases/latest")


class CliTests(unittest.TestCase):
    def test_version_reports_installed_and_source_without_creating_build_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tools").mkdir()
            original = Path(__file__).parents[1]
            for name in ("kosctl", "source-release.py"):
                shutil.copy(original / name, root / "tools" / name)
            (root / "VERSION").write_text("0.2.0-dev\n")
            record = root / "installed" / "share" / "kos" / "release.json"
            release.write_identity(record, {"version": "0.1.0", "revision": "installed-commit", "dirty": False})
            result = subprocess.run(["bash", str(root / "tools" / "kosctl"), "version"],
                env={**os.environ, "KOS_PREFIX": str(root / "installed"), "KOS_RELEASE_RECORD": str(record)},
                text=True, capture_output=True, check=True)
            self.assertIn("Installed: 0.1.0 (installed-commit)", result.stdout)
            self.assertIn("Source: 0.2.0-dev (unknown)", result.stdout)
            self.assertFalse((root / ".build").exists())

    def test_version_without_git_still_reports_archive_version(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "VERSION").write_text("0.1.0\n")
            with patch.object(release, "git", side_effect=FileNotFoundError("git")):
                self.assertEqual(release.identity(root)["revision"], "unknown")


if __name__ == "__main__":
    unittest.main()
