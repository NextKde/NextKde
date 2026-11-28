"""Exercise kosctl qdbus resolution and KWin plugin ABI mismatch checks."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'kosctl').read_text()


def function(name):
    return re.search(r'^' + name + r'\(\) \{.*?^\}', SOURCE, re.M | re.S).group()


class KosctlQdbusAndKWinAbiTests(unittest.TestCase):
    def test_resolve_qdbus_bin_prefers_qdbus6_then_qdbus_qt6(self):
        with tempfile.TemporaryDirectory() as directory:
            bin_dir = Path(directory) / 'bin'
            bin_dir.mkdir()
            qdbus_qt6 = bin_dir / 'qdbus-qt6'
            qdbus_qt6.write_text('#!/bin/sh\nexit 0\n')
            qdbus_qt6.chmod(0o755)

            bash = shutil.which('bash') or '/bin/bash'
            script = function('resolve_qdbus_bin') + '\nresolve_qdbus_bin\n'
            fedora_res = subprocess.run(
                [bash, '-euc', script], text=True, capture_output=True,
                env={'PATH': str(bin_dir)})
            self.assertEqual(fedora_res.returncode, 0, fedora_res.stderr)
            self.assertEqual(fedora_res.stdout.strip(), str(qdbus_qt6))

            qdbus6 = bin_dir / 'qdbus6'
            qdbus6.write_text('#!/bin/sh\nexit 0\n')
            qdbus6.chmod(0o755)
            arch_res = subprocess.run(
                [bash, '-euc', script], text=True, capture_output=True,
                env={'PATH': str(bin_dir)})
            self.assertEqual(arch_res.returncode, 0, arch_res.stderr)
            self.assertEqual(arch_res.stdout.strip(), str(qdbus6))

    def test_detect_running_kwin_version_and_header_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake_kwin = root / 'kwin_wayland'
            fake_kwin.write_text('#!/bin/sh\necho "kwin 6.8.3"\n')
            fake_kwin.chmod(0o755)
            header = root / 'config-kwin.h'
            header.write_text('#define KWIN_PLUGIN_VERSION_STRING "6.7.5"\n')

            script = '\n'.join([
                function('detect_kwin_header_version'),
                function('detect_running_kwin_version'),
                'detect_running_kwin_version',
            ])
            res = subprocess.run(
                ['bash', '-euc', script], text=True, capture_output=True,
                env={**os.environ, 'KOS_KWIN_WAYLAND_BIN': str(fake_kwin),
                     'KOS_KWIN_CONFIG_HEADER': str(header)})
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(res.stdout.strip(), '6.8.3')

            fallback_res = subprocess.run(
                ['bash', '-euc', script], text=True, capture_output=True,
                env={**os.environ, 'KOS_KWIN_WAYLAND_BIN': str(root / 'missing'),
                     'KOS_KWIN_CONFIG_HEADER': str(header)})
            self.assertEqual(fallback_res.returncode, 0, fallback_res.stderr)
            self.assertEqual(fallback_res.stdout.strip(), '6.7.5')

    def test_installed_kwin_plugin_abi_mismatches_detects_stale_and_clean(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plugins_dir = root / 'usr/lib64/qt6/plugins/kwin/effects/plugins'
            plugins_dir.mkdir(parents=True)
            glass = plugins_dir / 'glass.so'
            bridge = plugins_dir / 'kos_bridge.so'
            glass.write_bytes(b'\x7fELF\x00org.kde.kwin.EffectPluginFactory6.7.5\x00')
            bridge.write_bytes(b'\x7fELF\x00org.kde.kwin.EffectPluginFactory6.7.5\x00')
            manifest = root / 'kwin-system-files.manifest'
            manifest.write_text(f'{glass}\n{bridge}\n/usr/share/locale/pt_BR/LC_MESSAGES/kwin_effects_glass.mo\n')

            script = '\n'.join([
                f'kwin_manifest="{manifest}"',
                function('read_kwin_effect_plugin_abi'),
                function('installed_kwin_plugin_abi_mismatches'),
                'installed_kwin_plugin_abi_mismatches "$TARGET_KWIN"',
            ])
            mismatch = subprocess.run(
                ['bash', '-euc', script], text=True, capture_output=True,
                env={**os.environ, 'TARGET_KWIN': '6.8.3'})
            self.assertEqual(mismatch.returncode, 0, mismatch.stderr)
            self.assertEqual(mismatch.stdout.splitlines(), ['glass:6.7.5', 'kos_bridge:6.7.5'])

            clean = subprocess.run(
                ['bash', '-euc', script], text=True, capture_output=True,
                env={**os.environ, 'TARGET_KWIN': '6.7.5'})
            self.assertEqual(clean.returncode, 0, clean.stderr)
            self.assertEqual(clean.stdout.strip(), '')


if __name__ == '__main__':
    unittest.main()
