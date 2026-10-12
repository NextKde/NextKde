#!/usr/bin/env python3
"""Temporary filesystem + fake systemd/logind; NEVER mutate host services."""
import importlib.util
from importlib.machinery import SourceFileLoader
import fcntl
import threading
from types import SimpleNamespace
import json
import io
import shutil
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]

def load():
    spec = importlib.util.spec_from_file_location('switch_test', ROOT / 'tools/test-greeter.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module

class SwitchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.addCleanup(self.temporary.cleanup)
        self.module = load(); self.r = self.module.recovery
        self.r.LOCK = self.directory / 'lock'
        self.r.STATE = self.directory / 'state'; self.r.UNIT_DIR = self.directory / 'units'; self.r.UNIT_DIR.mkdir()
        self.actions = []; self.fail = None
        self.active = {'original.service': 'active', self.r.TEST: 'inactive', self.r.TIMER: 'inactive', 'getty@tty1.service': 'active'}
        self.services = {'baseline': 'login', 'new-test': 'greetd', 'unrelated': 'login'}
        self.data = {'version': 1, 'original': 'original.service', 'original_enabled': 'enabled', 'vt': 1,
                     'getty_active': True, 'sessions': ['baseline'], 'seconds': 600}
        # Only ownership is synthetic. Real filesystem/mode/content/remove operations run.
        def trusted(path, directory=False):
            if path.is_symlink() or (not path.is_dir() if directory else not path.is_file()):
                raise RuntimeError('Unsafe fixture path')
        self.r.trusted = trusted
        self.r.properties = self.properties
        self.r.systemctl = self.systemctl
        self.r.run = self.external
        self.r.sessions = lambda: list(self.services)
        self.r.session_service = lambda session: self.services.get(session, '')
        self.r.lock = lambda **kwargs: os.open(self.directory / 'lock', os.O_CREAT | os.O_RDWR, 0o600)
        self.persistent = self.directory / 'persistent-greetd.toml'; self.persistent.write_text('original config')

    def properties(self, unit):
        mask = self.r.UNIT_DIR / unit
        masked = mask.is_symlink() and os.readlink(mask) == '/dev/null'
        exists = unit == 'original.service' or unit.startswith('getty@') or mask.exists() or masked
        return {'Id': unit, 'LoadState': 'masked' if masked else ('loaded' if exists else 'not-found'),
                'ActiveState': self.active.get(unit, 'inactive'), 'UnitFileState': 'masked-runtime' if masked else 'enabled'}

    def systemctl(self, *args, check=True):
        self.actions.append(args)
        if self.fail == args[:2]:
            raise subprocess.CalledProcessError(1, args)
        if args[0] == 'mask':
            (self.r.UNIT_DIR / args[-1]).symlink_to('/dev/null')
        elif args[0] in ('start', 'stop'):
            self.active[args[1]] = 'active' if args[0] == 'start' else 'inactive'
            if args == ('start', self.r.TEST):
                self.active['getty@tty1.service'] = 'inactive'
        return subprocess.CompletedProcess(args, 0, '', '')

    def external(self, *args, check=True):
        self.actions.append(args)
        if args[0] != '/usr/bin/loginctl' or args[1] != 'terminate-session':
            raise AssertionError('Unexpected external command in sandboxed test: ' + repr(args))
        self.services.pop(args[2], None)
        return subprocess.CompletedProcess(args, 0, '', '')

    def stage(self):
        self.module.prepare(self.data)
        self.active[self.r.TIMER] = 'active'
        self.module.__file__ = str(self.r.STATE / 'private/test-greeter.py')

    def assert_restored(self):
        self.assertEqual(self.active['original.service'], 'active')
        self.assertEqual(self.active['getty@tty1.service'], 'active')
        self.assertEqual(self.active[self.r.TEST], 'inactive')
        self.assertEqual(self.active[self.r.TIMER], 'inactive')
        self.assertFalse(self.r.STATE.exists())
        self.assertEqual(list(self.r.UNIT_DIR.iterdir()), [])
        self.assertEqual(self.persistent.read_text(), 'original config')
        self.assertIn('baseline', self.services); self.assertIn('unrelated', self.services)
        self.assertNotIn('new-test', self.services)

    def test_t07_complete_bundle_and_preview_under_restrictive_umask(self):
        from PIL import Image
        out = io.BytesIO(); Image.new('RGB', (80, 60), '#345678').save(out, format='PNG')
        previous = os.umask(0o077)
        try: self.module.prepare(self.data, out.getvalue())
        finally: os.umask(previous)
        app = self.r.STATE / 'app'
        for relative in self.module.FILES:
            self.assertTrue((app / relative).is_file(), relative)
        self.assertTrue((app / 'wallpapers/themes/forest/assets/forest-cinematic.png').is_file())
        for path in (app / 'wallpapers').rglob('*'):
            self.assertFalse(path.is_symlink())
            self.assertEqual(path.stat().st_mode & 0o777, 0o755 if path.is_dir() else 0o644)
        image = app / 'config/preview-wallpaper.png'
        self.assertEqual(image.read_bytes(), out.getvalue())
        self.assertEqual(image.stat().st_mode & 0o777, 0o644)
        self.assertIn('temporary-preview', (app / 'shell.qml').read_text())
        self.assertNotIn(str(ROOT), (app / 'shell.qml').read_text())
        if shutil.which('qs'):
            source = (app / 'shell.qml').read_text()
            (app / 'shell.qml').write_text(source.rsplit('}', 1)[0] + '\n Timer { interval: 1200; running: true; onTriggered: { if (wallpaperSource.state.version !== "temporary-preview") throw new Error("preview missing"); console.info("PASS staged T07 frontend"); Qt.quit(); } }\n}\n')
            env = os.environ.copy()
            for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'WAYLAND_SOCKET', 'GREETD_SOCK'):
                env.pop(key, None)
            env['QT_QPA_PLATFORM'] = 'offscreen'
            result = subprocess.run(['qs', '--log-rules', '*.debug=false', '-p', str(app)], env=env, capture_output=True, text=True, timeout=8)
            logs = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, logs)
            self.assertIn('PASS staged T07 frontend', logs)
            self.assertNotIn('ERROR:', logs)
            self.assertNotIn('TypeError', logs)
        self.r.restore(); self.assert_restored()

    def test_preview_validation_and_symlink_rejection(self):
        from PIL import Image
        image = self.directory / 'selected.png'
        Image.new('RGB', (40, 30)).save(image)
        with patch.dict(self.module.os.environ, {}, clear=True):
            clean = self.module.preview_wallpaper(image)
            self.assertEqual(Image.open(io.BytesIO(clean)).size, (40, 30))
            link = self.directory / 'link.png'; link.symlink_to(image)
            with self.assertRaises(RuntimeError): self.module.preview_wallpaper(link)
            image.write_bytes(b'bad')
            with self.assertRaises(RuntimeError): self.module.preview_wallpaper(image)

    def test_sudo_preview_reader_drops_root_and_supplementary_groups(self):
        from PIL import Image
        out = io.BytesIO(); Image.new('RGB', (10, 10)).save(out, format='PNG')
        result = subprocess.CompletedProcess([], 0, out.getvalue(), b'')
        with patch.object(self.module.os, 'geteuid', return_value=0), patch.dict(self.module.os.environ, {'SUDO_UID': '1234'}, clear=True), patch.object(self.module.pwd, 'getpwuid', return_value=SimpleNamespace(pw_gid=4321)), patch.object(self.module.subprocess, 'run', return_value=result) as run:
            self.module.preview_wallpaper(self.directory/'selected.png')
            self.assertEqual(run.call_args.kwargs['user'], 1234)
            self.assertEqual(run.call_args.kwargs['group'], 4321)
            self.assertEqual(run.call_args.kwargs['extra_groups'], [])

    def test_kos_settings_publication_and_actual_frontend_decode(self):
        from PIL import Image
        import sys
        sys.path.insert(0, str(ROOT/'apps/greeter/companion'))
        from wallpaper import temporary_snapshot
        home = self.directory/'state-home'
        config = home/'quickshell/kos'; config.mkdir(parents=True)
        image = self.directory/'kos-selected.png'
        Image.new('RGB', (301, 203), '#6789ab').save(image)
        (config/'wallpaper.ini').write_text('[Wallpaper]\nmode=image\ntakeoverEnabled=true\nfitMode=fit\nimage='+str(image)+'\n')
        (config/'greeter-display.json').write_text(json.dumps(dict(schemaVersion=1,uid=os.getuid(),enabled=True,notice='所选壁纸将在认证前向这台机器的其他使用者展示。')))
        (config/'greeter-display.json').chmod(0o600)
        with patch.dict(self.module.os.environ, {'XDG_STATE_HOME': str(home)}, clear=True):
            kos = self.module.kos_wallpaper()
        self.module.prepare(self.data, kos=kos)
        app = self.r.STATE/'app'
        result = temporary_snapshot(app, -1, os.getuid())
        self.assertEqual(result['fit'], 'fit')
        self.assertTrue(result['source'].startswith('data:image/png;base64,'))
        self.assertEqual(temporary_snapshot(app, os.getuid()+1, os.getuid())['version'], 'default')
        image.unlink()  # Published bytes do not need the original home file.
        self.assertEqual(temporary_snapshot(app, -1, os.getuid())['sha256'], result['sha256'])
        if shutil.which('qs'):
            # Fixture adapter substitutes only root/location identity; all actual
            # manifest/hash/image validation and QML consumption still run.
            helper = app/'companion/wallpaper.py'
            text = helper.read_text().replace("app in (Path('/run/kos-greeter-test/app'), Path('/usr/local/lib/kos-greeter/app'))", 'app == Path('+repr(str(app))+')').replace('temporary_snapshot(app, uid)', 'temporary_snapshot(app, uid, os.getuid())')
            helper.write_text(text)
            source = (app/'shell.qml').read_text().replace('fitMode: wallpaperSource.state.fit', 'fitMode: wallpaperSource.state.fit\n            onDecoded: console.info("PASS published KOS image decoded")')
            source = source.rsplit('}',1)[0] + '\n Timer { interval: 3500; running: true; onTriggered: { if (wallpaperSource.state.fit !== "fit" || wallpaperSource.state.version === "default") throw new Error("KOS publication missing"); Qt.quit(); } }\n}\n'
            (app/'shell.qml').write_text(source)
            env = os.environ.copy()
            for key in ('DISPLAY','WAYLAND_DISPLAY','WAYLAND_SOCKET','GREETD_SOCK'):
                env.pop(key,None)
            env['QT_QPA_PLATFORM'] = 'offscreen'
            run = subprocess.run(['qs','--log-rules','*.debug=false','-p',str(app)],env=env,capture_output=True,text=True,timeout=8)
            logs=run.stdout+run.stderr
            self.assertEqual(run.returncode,0,logs)
            self.assertIn('PASS published KOS image decoded',logs)
            self.assertNotIn('ERROR:',logs)
        self.assertFalse(self.module.revoke_temporary_wallpaper(os.getuid()+1))
        self.assertNotEqual(temporary_snapshot(app, -1, os.getuid())['version'], 'default')
        self.module.revoke_temporary_wallpaper(os.getuid())
        self.assertEqual(temporary_snapshot(app, -1, os.getuid())['version'], 'default')
        self.assertEqual(list((app/'public-display'/str(os.getuid())).glob('v-*')), [])
        (config/'greeter-display.json').write_text(json.dumps(dict(schemaVersion=1,uid=os.getuid(),enabled=False,notice='所选壁纸将在认证前向这台机器的其他使用者展示。')))
        with patch.dict(self.module.os.environ, {'XDG_STATE_HOME': str(home)}, clear=True):
            self.assertIsNone(self.module.kos_wallpaper())
        self.r.restore(); self.assert_restored()

    def test_revoke_without_temporary_publication_does_not_touch_other_state(self):
        self.stage()
        self.assertFalse(self.module.revoke_temporary_wallpaper(os.getuid()))
        self.assertEqual(self.actions, [])
        self.assertTrue(self.r.STATE.exists())

    def test_world_accessible_consent_cannot_authorize_publication(self):
        import sys
        sys.path.insert(0, str(ROOT/'apps/greeter/companion'))
        from kos_wallpaper import current
        base=self.directory/'consent-test'
        path=base/'quickshell/kos'; path.mkdir(parents=True)
        file=path/'greeter-display.json'
        file.write_text(json.dumps(dict(schemaVersion=1,uid=os.getuid(),enabled=True,notice='所选壁纸将在认证前向这台机器的其他使用者展示。')))
        file.chmod(0o666)
        with self.assertRaises(ValueError): current(base,require_consent=True)
        file.chmod(0o600)
        other=path/'hardlink'; os.link(file,other)
        with self.assertRaises(ValueError): current(base,require_consent=True)

    def test_switch_and_full_idempotent_rollback(self):
        self.stage(); self.module.apply()
        self.assertEqual(self.active['original.service'], 'inactive')
        self.assertTrue((self.r.UNIT_DIR / 'original.service').is_symlink())
        self.assertEqual(self.active[self.r.TEST], 'active')
        self.r.restore(); self.assert_restored(); self.r.restore()

    def test_unarmed_timer_never_stops_manager(self):
        self.stage(); self.active[self.r.TIMER] = 'inactive'
        with self.assertRaises(RuntimeError): self.module.apply()
        self.assertNotIn(('stop', 'original.service'), self.actions)
        self.assert_restored()

    def test_start_failure_restores(self):
        self.stage(); self.fail = ('start', self.r.TEST)
        with self.assertRaises(subprocess.CalledProcessError): self.module.apply()
        self.assert_restored()

    def test_partial_prepare_failure_restores(self):
        original_write = self.module.write
        def fail_unit(path, *args, **kwargs):
            if path == self.r.UNIT_DIR / self.r.TEST:
                raise OSError('Injected unit write failure')
            return original_write(path, *args, **kwargs)
        with patch.object(self.module, 'write', side_effect=fail_unit):
            with self.assertRaises(OSError): self.module.prepare(self.data)
        self.r.restore(); self.assert_restored()

    def test_snapshot_write_failure_and_interrupt_leave_no_artifacts(self):
        for error in (OSError('disk full'), KeyboardInterrupt()):
            with patch.object(self.module, 'write', side_effect=error):
                with self.assertRaises(type(error)): self.module.prepare(self.data)
            self.assertFalse(self.r.STATE.exists())
            self.assertEqual(list(self.r.UNIT_DIR.iterdir()), [])
            self.assertEqual(self.active['original.service'], 'active')

    def test_timer_stop_failure_keeps_snapshot(self):
        self.stage(); self.module.apply(); self.fail = ('stop', self.r.TIMER)
        with self.assertRaises(subprocess.CalledProcessError): self.r.restore()
        self.assertTrue(self.r.STATE.exists())
        self.fail = None; self.r.restore(); self.assert_restored()

    def test_auto_lock_wait_and_bounded_retries(self):
        calls = []
        def locking(**kwargs):
            calls.append(kwargs)
            if len(calls) == 1: raise RuntimeError('Injected busy lock')
            return os.open(self.directory / 'lock', os.O_CREAT | os.O_RDWR, 0o600)
        self.r.lock = locking; self.r.LOCK = self.directory / 'lock'
        with patch.object(self.r.os, 'geteuid', return_value=0), patch.object(self.r.sys, 'argv', ['rollback', '--auto']), patch.object(self.r.time, 'sleep'):
            self.r.main()
        self.assertEqual(calls, [{'wait': True}, {'wait': True}])
        self.r.lock = lambda **kwargs: (_ for _ in ()).throw(RuntimeError('Persistent failure'))
        with patch.object(self.r.os, 'geteuid', return_value=0), patch.object(self.r.sys, 'argv', ['rollback', '--auto']), patch.object(self.r.time, 'sleep') as sleeping:
            with self.assertRaises(RuntimeError): self.r.main()
        self.assertEqual(sleeping.call_count, 2)

    def test_restore_failure_retains_recovery_and_timer(self):
        self.stage(); self.module.apply(); self.fail = ('start', 'original.service')
        with self.assertRaises(subprocess.CalledProcessError): self.r.restore()
        self.assertTrue((self.r.STATE / 'private/state.json').exists())
        self.assertTrue((self.r.UNIT_DIR / self.r.GUARD).exists())
        self.assertEqual(self.active[self.r.TIMER], 'active')
        self.fail = None; self.r.restore(); self.assert_restored()

    def test_concurrent_runtime_edit_is_not_overwritten(self):
        self.stage(); self.module.apply()
        mask = self.r.UNIT_DIR / 'original.service'; mask.unlink(); mask.write_text('administrator edit')
        with self.assertRaises(RuntimeError): self.r.restore()
        self.assertEqual(mask.read_text(), 'administrator edit')
        self.assertTrue(self.r.STATE.exists())

    def test_actual_lock_contention_waits_then_recovers(self):
        r = load().recovery; r.LOCK = self.directory / 'real-lock'
        holder = os.open(r.LOCK, os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(holder, fcntl.LOCK_EX)
        original_fstat = os.fstat
        def synthetic_owner(fd):
            info = original_fstat(fd)
            return SimpleNamespace(st_uid=0, st_mode=info.st_mode, st_ino=info.st_ino)
        timer = threading.Timer(0.03, lambda: fcntl.flock(holder, fcntl.LOCK_UN))
        try:
            with patch.object(r.os, 'fstat', side_effect=synthetic_owner):
                with self.assertRaises(RuntimeError): r.lock()
                timer.start()
                fd = r.lock(wait=True)
                os.close(fd)
        finally:
            if timer.ident: timer.join()
            os.close(holder)

    def test_readable_copy_even_under_restrictive_umask(self):
        previous = os.umask(0o077)
        try: self.stage()
        finally: os.umask(previous)
        for path in (self.r.STATE, self.r.STATE / 'app', self.r.STATE / 'app/bin'):
            self.assertEqual(path.stat().st_mode & 0o777, 0o755)
        self.assertEqual((self.r.STATE / 'app/bin/kos-greeter-ui').stat().st_mode & 0o777, 0o755)
        self.assertEqual((self.r.STATE / 'private/state.json').stat().st_mode & 0o777, 0o600)

    def test_session_wrapper_uses_independent_dbus(self):
        loader = SourceFileLoader('session_wrapper', str(ROOT / 'apps/greeter/bin/kos-greeter-session'))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        wrapper = importlib.util.module_from_spec(spec); loader.exec_module(wrapper)
        with patch.object(wrapper.sys, 'argv', ['session', '--temporary-seat']), patch.dict(wrapper.os.environ, {'GREETD_SOCK': '/fixture/socket'}, clear=True), patch.object(wrapper, 'check'), patch.object(wrapper.os, 'execv') as execute:
            wrapper.main()
        argv = execute.call_args.args
        self.assertEqual(argv[0], '/usr/bin/dbus-run-session')
        self.assertEqual(argv[1][:3], ['dbus-run-session', '--', '/usr/bin/kwin_wayland'])
        self.assertIn('--exit-with-session', argv[1])
        with patch.object(wrapper.sys, 'argv', ['session', '--temporary-seat']), patch.dict(wrapper.os.environ, {'GREETD_SOCK': '/fixture/socket', 'WAYLAND_DISPLAY': 'wayland-fixture'}, clear=True), patch.object(wrapper.os, 'execv') as execute:
            with self.assertRaises(SystemExit): wrapper.main()
            execute.assert_not_called()

    def test_console_detection_with_sudo_pty(self):
        cases = [
            ('/dev/tty3', {}, True),
            ('/dev/pts/7', {'SUDO_TTY': '/dev/tty3', 'SUDO_UID': '1000'}, True),
            ('/dev/pts/7', {'SUDO_TTY': '/dev/pts/4', 'SUDO_UID': '1000'}, False),
            ('/dev/pts/7', {}, False),
            ('/dev/pts/7', {'SUDO_TTY': '/dev/tty3'}, False),
            ('/dev/pts/7', {'SUDO_TTY': '/dev/tty1', 'SUDO_UID': '1000'}, False),
            ('/dev/pts/7', {'SUDO_TTY': '/dev/tty3', 'SUDO_UID': '1000', 'DISPLAY': ':0'}, False),
            ('/dev/tty3', {'WAYLAND_DISPLAY': 'wayland-0'}, False),
        ]
        for actual, environment, accepted in cases:
            with self.subTest(actual=actual, environment=environment), patch.dict(self.module.os.environ, environment, clear=True), patch.object(self.module.os, 'isatty', return_value=True), patch.object(self.module.os, 'ttyname', return_value=actual):
                if accepted: self.assertEqual(self.module.recovery_tty(1), '/dev/tty3')
                else:
                    with self.assertRaises(RuntimeError): self.module.recovery_tty(1)
        with patch.dict(self.module.os.environ, {'SUDO_TTY': '/dev/tty3', 'SUDO_UID': '1000'}, clear=True), patch.object(self.module.os, 'isatty', return_value=False):
            with self.assertRaises(RuntimeError): self.module.recovery_tty(1)
        self.assertEqual(self.actions, [])

    def test_refuse_graphical_or_recovery_vt(self):
        for tty in ('/dev/pts/2', '/dev/tty1'):
            with patch.dict(self.module.os.environ, {}, clear=True), patch.object(self.module.os, 'geteuid', return_value=0), patch.object(self.module.os, 'isatty', return_value=True), patch.object(self.module.os, 'ttyname', return_value=tty), patch.object(self.module.sys, 'argv', ['test', '--start']):
                with self.assertRaises(SystemExit): self.module.main()
        self.assertFalse(self.r.STATE.exists())
        self.assertEqual(self.actions, [])

unittest.main()
