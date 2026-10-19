"""Runtime deployment regressions. Execute only in a VM or hosted CI."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).parents[2]
spec = importlib.util.spec_from_file_location('deploy_runtime', ROOT / 'tools/deploy-runtime.py')
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)
        self.prefix, self.config, self.state = (self.root / name for name in ('prefix', 'config', 'state'))
        self.shell = self.config / 'quickshell/kos'
        self.settings = self.prefix / 'share/kos/settings'
        self.record = self.prefix / 'share/kos/release.json'
        for path in (self.shell, self.settings, self.config / 'kos', self.state / 'quickshell/kos'):
            path.mkdir(parents=True)
        (self.shell / 'old.qml').write_text('old runtime')
        (self.settings / 'removed-page.qml').write_text('removed page')
        (self.config / 'kos/window-appearance.json').write_text('{"radius":37}')
        (self.state / 'quickshell/kos/user.json').write_text('user state')
        self.record.write_text('{"version":"0.1.0"}')

    def test_upgrade_and_downgrade_do_not_overlay_old_runtime_files(self):
        first = runtime.prepare(self.prefix, self.config, self.state)
        self.assertEqual(list(self.shell.iterdir()), [])
        self.assertEqual(list(self.settings.iterdir()), [])
        (self.shell / 'new.qml').write_text('new version')
        (self.settings / 'new-page.qml').write_text('new page')
        second = runtime.prepare(self.prefix, self.config, self.state)
        self.assertNotEqual(first, second)
        self.assertFalse((self.shell / 'new.qml').exists())
        self.assertEqual((first / 'shell/old.qml').read_text(), 'old runtime')
        self.assertEqual((second / 'shell/new.qml').read_text(), 'new version')
        self.assertEqual(json.loads((first / 'release.json').read_text())['version'], '0.1.0')
        self.assertTrue(json.loads((first / 'backup.json').read_text())['complete'])
        self.assertFalse(self.record.exists())

    def test_personal_configuration_and_state_are_preserved(self):
        backup = runtime.prepare(self.prefix, self.config, self.state)
        self.assertEqual((self.config / 'kos/window-appearance.json').read_text(), '{"radius":37}')
        self.assertEqual((backup / 'config-kos/window-appearance.json').read_text(), '{"radius":37}')
        self.assertEqual((self.state / 'quickshell/kos/user.json').read_text(), 'user state')

    def test_backup_failure_does_not_delete_runtime_or_record(self):
        with patch.object(runtime.shutil, 'copytree', side_effect=OSError('simulated full disk')):
            with self.assertRaises(OSError):
                runtime.prepare(self.prefix, self.config, self.state)
        self.assertEqual((self.shell / 'old.qml').read_text(), 'old runtime')
        self.assertEqual((self.settings / 'removed-page.qml').read_text(), 'removed page')
        self.assertTrue(self.record.exists())

    def test_legacy_symlink_does_not_delete_checkout(self):
        checkout = self.root / 'checkout'
        checkout.mkdir()
        (checkout / 'shell.qml').write_text('source code')
        shutil.rmtree(self.shell)
        self.shell.symlink_to(checkout, target_is_directory=True)
        backup = runtime.prepare(self.prefix, self.config, self.state)
        self.assertTrue((backup / 'shell').is_symlink())
        self.assertFalse(self.shell.is_symlink())
        self.assertEqual((checkout / 'shell.qml').read_text(), 'source code')

    def test_backup_must_not_recurse_into_runtime(self):
        with self.assertRaisesRegex(ValueError, 'outside'):
            runtime.prepare(self.prefix, self.config, self.shell)
        self.assertTrue(self.record.exists())

    def test_first_install_creates_clean_runtime_without_backup(self):
        empty = self.root / 'empty'
        self.assertIsNone(runtime.prepare(empty / 'prefix', empty / 'config', empty / 'state'))
        self.assertTrue((empty / 'config/quickshell/kos').is_dir())


@unittest.skipUnless(shutil.which('cmake') and shutil.which('ninja'), 'CMake and Ninja required')
class VersionBuildTests(unittest.TestCase):
    def test_version_change_reconfigures_existing_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prologue = (ROOT / 'CMakeLists.txt').read_text().split('set(CMAKE_CXX_STANDARD 20)')[0]
            (root / 'CMakeLists.txt').write_text(prologue.replace('LANGUAGES CXX', 'LANGUAGES NONE'))
            (root / 'VERSION').write_text('0.1.0-rc.1\n')
            subprocess.run(['cmake', '-S', str(root), '-B', str(root / 'build'), '-G', 'Ninja'], check=True, capture_output=True)
            (root / 'VERSION').write_text('0.2.0-rc.1\n')
            subprocess.run(['cmake', '--build', str(root / 'build')], check=True, capture_output=True)
            self.assertIn('CMAKE_PROJECT_VERSION:STATIC=0.2.0', (root / 'build/CMakeCache.txt').read_text())


if __name__ == '__main__':
    unittest.main()
