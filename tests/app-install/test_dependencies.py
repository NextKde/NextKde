#!/usr/bin/env python3
"""Check distribution guidance and preflight failures without installing packages."""
import contextlib
import importlib.util
import io
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('dependencies', ROOT / 'tools/check-apps-dependencies.py')
deps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deps)

class DependencyTests(unittest.TestCase):
    def check(self, family, missing=(), qt='6.10.2', markers='', go='1.26.0', sdk=False, absent=()):
        calls = []
        def command(args):
            calls.append(args)
            if args[:2] == ['cmake', '--version']: output = 'cmake version 3.31.0'
            elif args[:2] == ['go', 'version']: output = 'go version go' + go + ' linux/arm64'
            elif args[:2] == ['pkg-config', '--modversion']: output = qt
            elif args[:2] == ['pkg-config', '--exists']:
                return SimpleNamespace(returncode=int(args[2] in missing), stdout='')
            else: output = markers
            return SimpleNamespace(returncode=0, stdout=output)
        output = io.StringIO()
        with patch.object(deps, 'distribution', return_value=family), patch.object(deps.shutil, 'which', side_effect=lambda name: None if name in absent else '/usr/bin/tool'), patch.object(deps, 'run', side_effect=command), patch('sys.argv', ['check'] + (['--sdk-only'] if sdk else [])), contextlib.redirect_stdout(output):
            result = deps.main()
        return result, output.getvalue(), calls

    def test_missing_build_tools_fail_before_cmake(self):
        result, output, calls = self.check('ubuntu', absent=['cmake', 'pkg-config'])
        self.assertEqual(result, 1)
        self.assertIn('sudo apt install cmake pkg-config', output)
        self.assertFalse(any(call[0] in ('cmake', 'pkg-config') for call in calls))

    def test_arch_missing_audio(self):
        result, output, _ = self.check('arch', missing=['libpulse', 'libavcodec'])
        self.assertEqual(result, 1)
        self.assertIn('sudo pacman -S --needed ffmpeg libpulse', output)

    def test_ubuntu_development_packages(self):
        result, output, _ = self.check('ubuntu', missing=['Qt6WebEngineWidgets', 'libavcodec'])
        self.assertEqual(result, 1)
        self.assertIn('sudo apt update && sudo apt install libavcodec-dev qt6-webengine-dev', output)

    def test_ubuntu_old_qt_explicit_version(self):
        result, output, _ = self.check('ubuntu', missing=['Qt6Core >= 6.10'], qt='6.4.2')
        self.assertEqual(result, 1)
        self.assertIn('ListenFree requires Qt >= 6.10', output)
        self.assertIn('Ubuntu 26.04+', output)

    def test_split_runtime_and_framework_packages(self):
        result, output, _ = self.check('ubuntu', markers='KOS_MISSING:Qml_QtQuick_Effects\nKOS_MISSING:KF6CalendarCore\nKOS_MISSING:SQLiteDriver')
        self.assertEqual(result, 1)
        self.assertIn('libkf6calendarcore-dev libqt6sql6-sqlite qml6-module-qtquick-effects', output)

    def test_old_taglib_selects_private_build(self):
        result, _, calls = self.check('ubuntu', missing=['taglib >= 2.3.1'])
        self.assertEqual(result, 0)
        self.assertTrue(any('-DKOS_BUILD_TAGLIB=ON' in call for call in calls))

    def test_private_taglib_missing_utfcpp(self):
        result, output, _ = self.check('ubuntu', missing=['taglib >= 2.3.1'], markers='KOS_MISSING:Utf8Cpp')
        self.assertEqual(result, 1)
        self.assertIn('sudo apt install libutfcpp-dev', output)

    def test_old_go(self):
        result, output, _ = self.check('ubuntu', go='1.22.0')
        self.assertEqual(result, 1)
        self.assertIn('Go >= 1.26', output)

    def test_sdk_does_not_require_go(self):
        result, _, calls = self.check('arch', go='1.22.0', sdk=True)
        self.assertEqual(result, 0)
        self.assertNotIn(['go', 'version'], calls)

    def test_distribution_derivatives(self):
        with tempfile.TemporaryDirectory() as directory:
            release = Path(directory) / 'os-release'
            release.write_text('ID=manjaro\nID_LIKE="arch"\n')
            self.assertEqual(deps.distribution(release), 'arch')
            release.write_text('ID=linuxmint\nID_LIKE="ubuntu debian"\n')
            self.assertEqual(deps.distribution(release), 'ubuntu')

if __name__ == '__main__':
    unittest.main()
