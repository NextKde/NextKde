#!/usr/bin/env python3
"""Standalone-app release metadata validation, without network access."""

import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("app_release", ROOT / "tools/prepare-app-release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class AppReleaseTest(unittest.TestCase):
    def test_settings_bundles_reviewed_installer_without_divergence(self):
        self.assertEqual(
            (ROOT / "apps/settings/app-store/installer.py").read_bytes(),
            (ROOT / "tools/app-installer.py").read_bytes(),
            "Update the Settings installer copy whenever the canonical engine changes",
        )

    def test_each_repository_is_allowlisted_and_pinned(self):
        for app, (repository, app_id) in release.APPS.items():
            with self.subTest(app=app):
                data = release.manifest(app, "1.2.3", "a" * 40, "b" * 64)
                self.assertEqual(data["appId"], app_id)
                self.assertEqual(data["archiveUrl"], f"https://codeload.github.com/NextKde/{repository}/tar.gz/" + "a" * 40)
                self.assertEqual(data["schemaVersion"], 1)

    def test_unstable_or_ambiguous_versions_are_rejected(self):
        for version in ("main", "latest", "v1.2.3", "1.2.3-rc.1", "01.2.3", "1.2", "1.2.3/evil", "1.2.3\n"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                release.manifest("calendar", version, "a" * 40, "b" * 64)

    def test_mutable_or_invalid_revisions_are_rejected(self):
        for revision in ("main", "a" * 39, "A" * 40, "../" + "a" * 40, "a" * 40 + "\n"):
            with self.subTest(revision=revision), self.assertRaises(ValueError):
                release.manifest("calendar", "1.2.3", revision, "b" * 64)

    def test_unknown_application_and_invalid_digest_are_rejected(self):
        with self.assertRaises(ValueError):
            release.manifest("untrusted", "1.2.3", "a" * 40, "b" * 64)
        for digest in ("", "b" * 63, "B" * 64):
            with self.subTest(digest=digest), self.assertRaises(ValueError):
                release.manifest("weather", "1.2.3", "a" * 40, digest)


if __name__ == "__main__":
    unittest.main()
