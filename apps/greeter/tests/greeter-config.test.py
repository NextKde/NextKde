#!/usr/bin/env python3
"""No compositor, seat, D-Bus or authentication socket is contacted."""
import configparser
import importlib.util
from importlib.machinery import SourceFileLoader
import os
from pathlib import Path
import shutil
import tempfile
import subprocess
from unittest import mock
import unittest

from entry_launch_guard import block_real_launch

APP = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('greeter_config', APP/'companion/greeter_config.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)


class Isolation(unittest.TestCase):
    def setUp(self):
        # Private non-sticky ancestor is intentional: production rejects /tmp.
        self.temp = tempfile.TemporaryDirectory(dir=APP)
        self.root = Path(self.temp.name)
        self.root.chmod(0o700)
        self.environment = dict(XDG_RUNTIME_DIR=str(self.root), XDG_CONFIG_HOME='/unreadable/user/config',
                                XDG_CONFIG_DIRS='/unreadable/global', XDG_CACHE_HOME='/unreadable/user/cache',
                                KDEHOME='/unreadable/legacy', GREETD_SOCK='/fixture/not-contacted',
                                XDG_DATA_DIRS='/usr/local/share:/usr/share', HOME='/')
    def tearDown(self): self.temp.cleanup()
    def test_private_and_explicit_effects(self):
        result = m.prepare(self.environment)
        config = Path(result['XDG_CONFIG_HOME'])
        parser = configparser.ConfigParser(); parser.optionxform = str
        parser.read(config/'kwinrc')
        for effect in m.DISABLED_EFFECTS:
            self.assertFalse(parser.getboolean('Plugins', effect+'Enabled'))
        self.assertNotIn('blurEnabled', parser['Plugins'])
        for key in ('XDG_CONFIG_HOME', 'XDG_CONFIG_DIRS', 'XDG_CACHE_HOME', 'XDG_DATA_HOME'):
            metadata = Path(result[key]).stat()
            self.assertEqual(metadata.st_mode & 0o777, 0o700)
            self.assertEqual(metadata.st_uid, os.geteuid())
        self.assertEqual((config/'kwinrc').stat().st_mode & 0o777, 0o600)
        self.assertFalse(list(Path(result['XDG_CONFIG_DIRS']).iterdir()))
    def test_environment_not_mutated_and_system_assets_retained(self):
        before = dict(self.environment); result = m.prepare(self.environment)
        self.assertEqual(self.environment, before)
        self.assertNotIn('KDEHOME', result)
        self.assertEqual(result['GREETD_SOCK'], before['GREETD_SOCK'])
        self.assertEqual(result['XDG_DATA_DIRS'], before['XDG_DATA_DIRS'])
        self.assertEqual(result['HOME'], '/')
    def test_distinct_starts(self):
        self.assertNotEqual(m.prepare(self.environment)['XDG_CONFIG_HOME'],
                            m.prepare(self.environment)['XDG_CONFIG_HOME'])
    def test_symlink_runtime_rejected(self):
        link = self.root/'link'; link.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises((ValueError, OSError)): m.prepare(dict(self.environment, XDG_RUNTIME_DIR=str(link)))
    def test_nonprivate_runtime_rejected(self):
        self.root.chmod(0o750)
        with self.assertRaises(ValueError): m.prepare(self.environment)
    def test_writable_ancestor_rejected(self):
        child = self.root/'child'; child.mkdir(mode=0o700); self.root.chmod(0o770)
        with self.assertRaises(ValueError): m.prepare(dict(self.environment, XDG_RUNTIME_DIR=str(child)))
    def test_relative_and_missing_runtime_rejected(self):
        for value in ('relative', str(self.root/'missing')):
            with self.assertRaises((ValueError, OSError)):
                m.prepare(dict(self.environment, XDG_RUNTIME_DIR=value))
    def test_wrong_owner_rejected(self):
        with mock.patch.object(m.os, 'geteuid', return_value=987654):
            with self.assertRaises(ValueError): m.prepare(self.environment)
    @unittest.skipUnless(shutil.which('kreadconfig6'), 'KConfig command unavailable')
    def test_actual_kconfig_lookup_ignores_inherited_config(self):
        desktop = self.root/'desktop'; desktop.mkdir(mode=0o700)
        (desktop/'kwinrc').write_text('[Plugins]\nkos_bridgeEnabled=true\nscaleEnabled=true\n')
        environment = dict(os.environ, **self.environment)
        environment['XDG_CONFIG_HOME'] = str(desktop)
        environment['XDG_CONFIG_DIRS'] = str(desktop)
        result = m.prepare(environment)
        for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'GREETD_SOCK', 'DBUS_SESSION_BUS_ADDRESS'):
            result.pop(key, None)
        for effect in m.DISABLED_EFFECTS:
            process = subprocess.run(['kreadconfig6', '--file', 'kwinrc', '--group', 'Plugins',
                                      '--key', effect+'Enabled', '--default', 'MISSING'],
                                     env=result, capture_output=True, text=True, timeout=5, check=True)
            self.assertEqual(process.stdout.strip(), 'false')
        self.assertIn('scaleEnabled=true', (desktop/'kwinrc').read_text())
    def test_launch_guard_hard_fails_unreviewed_launches(self):
        with block_real_launch():
            for name in ('execv', 'execve', 'execvp', 'execvpe'):
                with self.assertRaises(AssertionError): getattr(os, name)('/fixture/never-run', ['fixture'])
            with self.assertRaises(AssertionError): subprocess.Popen(['/fixture/never-run'])
    def entry_module(self):
        loader = SourceFileLoader('config_entry_fixture', str(APP/'bin/kos-greeter-session'))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        entry = importlib.util.module_from_spec(spec); loader.exec_module(entry)
        return entry
    def test_check_never_creates_runtime_configuration(self):
        entry = self.entry_module()
        with block_real_launch(), mock.patch.object(entry.sys, 'argv', ['entry', '--check']), \
             mock.patch.object(entry, 'check') as check, \
             mock.patch.object(entry, 'prepare_greeter_config') as prepare:
            entry.main()
        check.assert_called_once_with(); prepare.assert_not_called()
        self.assertEqual(list(self.root.iterdir()), [])
    def test_entry_passes_private_environment_only_to_greeter_exec(self):
        entry = self.entry_module()
        with block_real_launch(), mock.patch.dict(entry.os.environ, self.environment, clear=True), \
             mock.patch.object(entry.sys, 'argv', ['entry', '--isolated-seat']), \
             mock.patch.object(entry, 'check'), \
             mock.patch.object(entry, 'prepare_session_output'), \
             mock.patch.object(entry, 'phase'), \
             mock.patch.object(entry.os, 'execve') as execute:
            before = dict(entry.os.environ)
            entry.main()
            self.assertEqual(dict(entry.os.environ), before)
            environment = execute.call_args.args[2]
            self.assertEqual(environment['KOS_GREETER_OUTPUT_APPLY'], '1')
            self.assertNotEqual(environment['XDG_CONFIG_HOME'], before['XDG_CONFIG_HOME'])
            self.assertEqual(execute.call_args.args[0], '/usr/bin/dbus-run-session')
    def test_entry_refuses_unisolated_fallback(self):
        entry = self.entry_module()
        with block_real_launch(), mock.patch.dict(entry.os.environ, dict(self.environment, XDG_RUNTIME_DIR=str(self.root/'missing')), clear=True), \
             mock.patch.object(entry.sys, 'argv', ['entry', '--isolated-seat']), \
             mock.patch.object(entry, 'check'), \
             mock.patch.object(entry, 'prepare_session_output'), \
             mock.patch.object(entry, 'diagnostic'), \
             mock.patch.object(entry.os, 'execve') as execute:
            with self.assertRaises(SystemExit) as exception: entry.main()
            self.assertEqual(exception.exception.code, 70)
            execute.assert_not_called()
    def test_packaging_lists_helper(self):
        source = (APP.parents[1]/'tools/test-greeter.py').read_text()
        self.assertIn("'companion/greeter_config.py'", source)
        self.assertIn("'app/companion/greeter_config.py'",
                      (APP.parents[1]/'tools/greeter-install.py').read_text())
    def test_copied_helper_has_no_source_tree_dependency(self):
        destination = self.root/'copy.py'; shutil.copyfile(APP/'companion/greeter_config.py', destination)
        spec = importlib.util.spec_from_file_location('copied_config', destination)
        copied = importlib.util.module_from_spec(spec); spec.loader.exec_module(copied)
        self.assertEqual((Path(copied.prepare(self.environment)['XDG_CONFIG_HOME'])/'kwinrc').read_bytes(), m.KWINRC)


if __name__ == '__main__': unittest.main()
