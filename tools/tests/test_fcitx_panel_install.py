"""Fcitx adapter deployment. Run only in a VM or hosted CI."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('panel_install', ROOT / 'tools/deploy/deploy-fcitx-panel.py')
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class PanelInstallTests(unittest.TestCase):
    def test_custom_prefix_and_replacement_preserve_a_mapped_old_library(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'adapter.so'
            source.write_bytes(b'new-library')
            prefix = root / 'custom prefix'
            addon_dir = root / 'custom data/fcitx5/addon'
            target = prefix / 'lib/fcitx5/libnextkde-inputpanel.so'
            target.parent.mkdir(parents=True)
            target.write_bytes(b'old-library')
            with target.open('rb') as mapped:
                deploy.install(source, ROOT / 'platform/fcitx-panel/nextkde-inputpanel.conf', prefix, addon_dir)
                self.assertEqual(mapped.read(), b'old-library')
            self.assertEqual(target.read_bytes(), b'new-library')
            self.assertIn('Library=' + str(target)[:-3] + '\n',
                          (addon_dir / 'nextkde-inputpanel.conf').read_text())
            self.assertEqual(target.stat().st_mode & 0o777, 0o755)
            self.assertFalse(list(addon_dir.glob('.nextkde-panel-*')))

    def test_missing_library_and_unrepresentable_path_leave_existing_install_untouched(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'adapter.so'
            addon_dir = root / 'addon'
            addon_dir.mkdir()
            config = addon_dir / 'nextkde-inputpanel.conf'
            config.write_text('previous-config')
            template = ROOT / 'platform/fcitx-panel/nextkde-inputpanel.conf'
            with self.assertRaises(FileNotFoundError):
                deploy.install(source, template, root / 'prefix', addon_dir)
            source.write_bytes(b'new-library')
            with self.assertRaises(ValueError):
                deploy.install(source, template, root / 'invalid;prefix', addon_dir)
            self.assertEqual(config.read_text(), 'previous-config')
            self.assertFalse((root / 'prefix').exists())


if __name__ == '__main__':
    unittest.main()
