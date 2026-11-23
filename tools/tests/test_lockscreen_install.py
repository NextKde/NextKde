"""Real lifecycle backend, extracted installer functions, throwaway HOME only.

Run with KOS_LOCKSCREEN_SETTINGS_TEST_BINARY=/absolute/path/to/kos-settings.
No kosctl entry point, service operation, installation or real lock is invoked.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = (ROOT / "tools/kosctl").read_text()
BINARY = os.environ.get("KOS_LOCKSCREEN_SETTINGS_TEST_BINARY", "")


def function(name):
    return re.search(r"^" + name + r"\(\) \{.*?^\}", SCRIPT, re.M | re.S).group()


@unittest.skipUnless(BINARY, "set KOS_LOCKSCREEN_SETTINGS_TEST_BINARY to the isolated build")
class LockScreenInstall(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.prefix = self.root / "installed"
        self.source = self.root / "checkout/apps/lockscreen"
        (self.source / "contents/lockscreen").mkdir(parents=True)
        (self.source / "metadata.json").write_text(json.dumps({"KPlugin": {"Id": "org.kos.desktop"}, "X-Plasma-APIVersion": "2"}))
        (self.source / "contents/defaults").write_text("[Desktop]\nContainment=org.kde.desktopcontainment\n")
        (self.source / "contents/lockscreen/LockScreen.qml").write_text("import QtQuick\nItem {}\n")
        self.home = self.root / "home"
        self.config = self.home / "config"
        self.config.mkdir(parents=True)
        self.rc = self.config / "plasmashellrc"
        self.original = "[Shell]\nShellPackage=org.kde.plasma.desktop\n\n[Other]\nKeep=yes\n"
        self.rc.write_text(self.original)
        (self.prefix / "bin").mkdir(parents=True)
        (self.prefix / "bin/kos-settings").symlink_to(Path(BINARY).resolve())
        self.shell = self.prefix / "share/plasma/shells/org.kos.desktop"
        self.skin = self.shell / "contents/lockscreen/LockScreen.qml"
        self.runtime = self.root / "units"
        self.runtime.mkdir()
        self.env = {**os.environ, "HOME": str(self.home), "XDG_CONFIG_HOME": str(self.config),
                    "XDG_DATA_HOME": str(self.prefix / "share"), "XDG_DATA_DIRS": str(self.root / "empty"),
                    "XDG_CACHE_HOME": str(self.home / "cache"), "DBUS_SESSION_BUS_ADDRESS": "unix:path=/nonexistent/kos-test"}
        # These are only installer functions. No source of kosctl, no global
        # command dispatch, build/deploy hooks, daemon start or lock request.
        names = ["lockscreen_settings", "refresh_lockscreen_package", "owned_theme_root",
                 "core_install_present", "previous_plasma_shell", "write_shell_package_key",
                 "migrate_plasma_appletsrc", "switch_plasma_shell", "restore_plasma_shell",
                 "take_over_plasma_desktop", "install_lockscreen", "remove_lockscreen"]
        self.functions = "\n".join(function(name) for name in names)

    def run_functions(self, commands, ok=True):
        script = """set -euo pipefail
prefix=$1
project_dir=$2
config_dir=$XDG_CONFIG_HOME
build_dir=$3
runtime_unit_dir=$4
kos_shell_id=org.kos.desktop
shells_dir=$prefix/share/plasma/shells/$kos_shell_id
laf_dir=$prefix/share/plasma/look-and-feel/$kos_shell_id
plasma_shell_state=$prefix/share/kos/plasma-shell-state
qdbus_bin=
""" + self.functions + "\n" + commands
        result = subprocess.run(["bash", "-c", script, "lockscreen-install-test", str(self.prefix),
                                 str(self.root / "checkout"), str(self.root / "build"), str(self.runtime)],
                                env=self.env, text=True, capture_output=True, timeout=20)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_core_upgrade_preserves_opt_in_and_system_fallback(self):
        self.run_functions("take_over_plasma_desktop")
        self.assertFalse(self.skin.exists())
        self.assertTrue((self.prefix / "share/kos/lockscreen/contents/lockscreen/LockScreen.qml").is_file())
        self.assertIn("ShellPackage=org.kos.desktop", self.rc.read_text())
        self.run_functions("install_lockscreen")
        self.assertTrue(self.skin.is_file())
        self.run_functions("take_over_plasma_desktop")
        self.assertTrue(self.skin.is_file())
        (self.runtime / "kos-shell.service").write_text("fixture")
        before = self.rc.read_bytes()
        self.run_functions("remove_lockscreen")
        self.assertFalse(self.skin.exists())
        self.assertTrue((self.shell / "contents/defaults").is_file())
        self.assertEqual(self.rc.read_bytes(), before)
        self.run_functions("take_over_plasma_desktop")
        self.assertFalse(self.skin.exists())

    def test_standalone_install_and_restore(self):
        self.run_functions("install_lockscreen")
        self.assertTrue(self.skin.is_file())
        self.assertIn("ShellPackage=org.kos.desktop", self.rc.read_text())
        self.run_functions("remove_lockscreen")
        self.assertFalse(self.shell.exists())
        self.assertIn("ShellPackage=org.kde.plasma.desktop", self.rc.read_text())
        self.assertIn("Keep=yes", self.rc.read_text())

    def test_copy_failure_keeps_old_entry_and_selection(self):
        self.run_functions("install_lockscreen")
        before, selection = self.skin.read_bytes(), self.rc.read_bytes()
        (self.source / "contents/lockscreen/LockScreen.qml").unlink()
        self.run_functions("take_over_plasma_desktop", ok=False)
        self.assertEqual(self.skin.read_bytes(), before)
        self.assertEqual(self.rc.read_bytes(), selection)

    def test_linked_contents_and_foreign_look_and_feel_are_untouched(self):
        self.run_functions("install_lockscreen")
        (self.runtime / "kos-shell.service").write_text("fixture")
        laf = self.prefix / "share/plasma/look-and-feel/org.kos.desktop"
        laf.mkdir(parents=True)
        (laf / "metadata.json").write_text('{"KPlugin":{"Id":"other.desktop"}}')
        self.run_functions("remove_lockscreen")
        self.assertTrue((laf / "metadata.json").exists())
        self.run_functions("install_lockscreen")
        external = self.root / "external-contents"
        (self.shell / "contents").rename(external)
        (self.shell / "contents").symlink_to(external)
        self.run_functions("remove_lockscreen", ok=False)
        self.assertTrue((external / "lockscreen/LockScreen.qml").exists())

    def test_old_backend_is_not_launched(self):
        backend = self.prefix / "bin/kos-settings"
        backend.unlink()
        marker = self.root / "old-backend-was-run"
        backend.write_text('#!/bin/sh\ntouch "' + str(marker) + '"\n')
        backend.chmod(0o755)
        self.run_functions("install_lockscreen", ok=False)
        self.assertFalse(marker.exists())
        self.assertEqual(self.rc.read_text(), self.original)
        built = self.root / "build/apps/settings/kos-settings"
        built.parent.mkdir(parents=True)
        built.symlink_to(Path(BINARY).resolve())
        self.run_functions("install_lockscreen")
        self.assertFalse(marker.exists())
        self.assertTrue(self.skin.exists())

    def test_standalone_uses_build_backend_without_core(self):
        (self.prefix / "bin/kos-settings").unlink()
        backend = self.root / "build/apps/settings/kos-settings"
        backend.parent.mkdir(parents=True)
        backend.symlink_to(Path(BINARY).resolve())
        self.run_functions("install_lockscreen")
        self.assertTrue(self.skin.exists())


if __name__ == "__main__":
    unittest.main()
