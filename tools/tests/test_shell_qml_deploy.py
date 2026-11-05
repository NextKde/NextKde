"""Installer regressions: real file copies in temporary trees, no Shell launch."""
import importlib.util
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('deploy_shell', ROOT / 'tools/deploy-shell-qml.py')
DEPLOY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DEPLOY)
KOSCTL = (ROOT / 'tools/kosctl').read_text()
ALIASES = [Path('shared/qml') / n for n in ('controls', 'foundation', 'i18n')]
ALIASES += [Path('Kos/Ui') / n for n in DEPLOY.MODULES]


def function(name):
    return re.search(r'^' + name + r'\(\) \{.*?^\}', KOSCTL, re.M | re.S).group()


class ShellDeployment(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / 'source'
        self.shell = self.project / 'shell'
        self.shared = self.project / 'shared/qml'
        self.output = self.root / 'installed'
        shutil.copytree(ROOT / 'shell', self.shell, symlinks=True)
        shutil.copytree(ROOT / 'shared/qml', self.shared)

    def damage_aliases(self, kind):
        for alias in ALIASES:
            target = self.shell / alias
            if target.is_symlink() or target.is_file():
                target.unlink()
            elif target.exists():
                shutil.rmtree(target)
            if kind == 'directory':
                target.mkdir()
            elif kind == 'file':
                target.write_text('../../../shared/qml/' + target.name)
            elif kind == 'dangling':
                target.symlink_to('/nonexistent/kos-fixture')

    def assert_materialized(self):
        DEPLOY.check_installed(self.output)
        for name in DEPLOY.MODULES:
            for base in (self.output / 'shared/qml', self.output / 'Kos/Ui'):
                self.assertFalse((base / name).is_symlink())
                self.assertEqual((base / name / 'qmldir').read_bytes(),
                                 (self.shared / name / 'qmldir').read_bytes())
        for name in ('I18n.qml', 'ZhCatalog.mjs', 'PtBrCatalog.mjs', 'SystemLanguage.mjs'):
            self.assertEqual((self.output / 'shared/qml/i18n' / name).read_bytes(),
                             (self.shared / 'i18n' / name).read_bytes())

    def test_source_alias_variants(self):
        for kind in ('original', 'directory', 'file', 'dangling', 'missing'):
            with self.subTest(kind=kind):
                if kind != 'original':
                    self.damage_aliases(kind)
                DEPLOY.deploy(self.shell, self.shared, self.output)
                self.assert_materialized()

    def test_packaged_real_directories_and_new_module(self):
        self.damage_aliases('directory')
        extra = self.shared / 'future'
        extra.mkdir()
        (extra / 'Extra.qml').write_text('import QtQuick\nItem {}\n')
        (extra / 'qmldir').write_text('Extra 1.0 Extra.qml\n')
        DEPLOY.deploy(self.shell, self.shared, self.output)
        self.assert_materialized()
        self.assertTrue((self.output / 'shared/qml/future/Extra.qml').is_file())

    def test_readonly_packaged_input(self):
        for path in [self.shell, *self.shell.rglob('*')]:
            if not path.is_symlink():
                path.chmod(0o555 if path.is_dir() else 0o444)
        try:
            DEPLOY.deploy(self.shell, self.shared, self.output)
            self.assert_materialized()
        finally:
            for path in [self.shell, *self.shell.rglob('*')]:
                if not path.is_symlink():
                    path.chmod(0o755 if path.is_dir() else 0o644)

    def test_missing_canonical_files_preserves_previous_installation(self):
        self.output.mkdir()
        sentinel = self.output / 'old-runtime'
        sentinel.write_text('preserve')
        for relative in ('i18n/qmldir', 'i18n/I18n.qml', 'i18n/ZhCatalog.mjs', 'foundation/KosButton.qml'):
            with self.subTest(relative=relative):
                target = self.shared / relative
                data = target.read_bytes()
                target.unlink()
                with self.assertRaises(ValueError):
                    DEPLOY.deploy(self.shell, self.shared, self.output)
                self.assertEqual(sentinel.read_text(), 'preserve')
                target.write_bytes(data)

    def test_post_copy_check_precedes_destination_replacement(self):
        self.output.mkdir()
        (self.output / 'old-runtime').write_text('preserve')
        with patch.object(DEPLOY, 'check_installed', side_effect=ValueError('copy incomplete')):
            with self.assertRaises(ValueError):
                DEPLOY.deploy(self.shell, self.shared, self.output)
        self.assertTrue((self.output / 'old-runtime').is_file())

    def test_preflight_precedes_runtime_cleanup(self):
        tools = self.project / 'tools'
        tools.mkdir()
        shutil.copy2(ROOT / 'tools/deploy-shell-qml.py', tools)
        build = self.root / 'build'
        for name in ('platform/kos-platform', 'bin/kos-data-service', 'apps/settings/kos-settings',
                     'apps/settings/kos-apps', 'apps/settings/gtk-module/libkos-gtk-window-controls.so'):
            path = build / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture')
            path.chmod(0o755)
        (self.shared / 'i18n/I18n.qml').unlink()
        script = function('deploy_artifacts') + '\nspatial_built() { return 1; }\n'
        script += 'project_dir="$1"; prefix="$2"; config_dir="$3"; deploy_artifacts "$4"\n'
        result = subprocess.run(['bash', '-euc', script, 'fixture', str(self.project),
                                 str(self.root / 'prefix'), str(self.root / 'config'), str(build)],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Missing or empty QML runtime file', result.stderr)
        self.assertNotIn('deploy-runtime.py', result.stderr)
        self.assertFalse((self.root / 'prefix').exists())

    def test_failed_deployment_never_takes_over_desktop(self):
        script = function('install_all') + '''
is_nixos() { return 1; }
ensure_build_dependencies() { :; }
build() { :; }
deploy_artifacts() { return 1; }
install_kwin_plugins() { echo unexpected; }
take_over_plasma_desktop() { echo unexpected; }
warn_notification_claimers() { echo unexpected; }
print_install_summary() { echo unexpected; }
build_dir=fixture
install_all
echo unexpected
'''
        result = subprocess.run(['bash', '-euc', script], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, '')


if __name__ == '__main__':
    unittest.main()
