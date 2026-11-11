#!/usr/bin/env python3
"""Exercise production takeover against a fake Fcitx/KWin on a private bus."""
import configparser
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

if '--serve' in sys.argv:
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
    DBusGMainLoop(set_as_default=True)
    root = Path(os.environ['KIMPANEL_FIXTURE'])
    addons = {'classicui': True, 'kimpanel': False}
    connection = owner = controller = None
    def record(item):
        with (root / 'trace').open('a') as f:
            f.write(json.dumps(item) + '\n')
    class Controller(dbus.service.Object):
        @dbus.service.method('org.fcitx.Fcitx.Controller1', out_signature='a(sssibb)')
        def GetAddons(self):
            if (root / 'fail-backup').exists():
                raise dbus.exceptions.DBusException('backup failed', name='org.test.Failed')
            # Configurability is deliberately different from enabled state.
            return [(name, name, '', 4, not enabled, enabled)
                    for name, enabled in addons.items()]
        @dbus.service.method('org.fcitx.Fcitx.Controller1', in_signature='a(sb)')
        def SetAddonsState(self, values):
            addons.update({str(k): bool(v) for k, v in values})
            record(dict(addons))
        @dbus.service.method('org.fcitx.Fcitx.Controller1')
        def ReloadConfig(self):
            pass
    def start():
        global connection, owner, controller
        connection = dbus.SessionBus(private=True)
        owner = dbus.service.BusName('org.fcitx.Fcitx5', connection)
        controller = Controller(connection, '/controller')
    def poll():
        global connection, owner, controller
        config = configparser.RawConfigParser()
        config.read(root / 'config/kwinrc')
        command = config.get('Wayland', 'InputMethod', fallback='')
        if not command and connection is not None:
            controller.remove_from_connection()
            owner = None
            connection.close()
            connection = owner = controller = None
        elif command and connection is None:
            start()
        return True
    start()
    (root / 'ready').touch()
    GLib.timeout_add(10, poll)
    GLib.MainLoop().run()
    sys.exit()

if '--session' not in sys.argv:
    subprocess.run(['dbus-run-session', '--', sys.executable, __file__,
                    sys.argv[1], '--session'], check=True)
    sys.exit()

with tempfile.TemporaryDirectory(prefix='kos-kimpanel-') as directory:
    root = Path(directory)
    (root / 'config').mkdir()
    desktop = root / 'fcitx.desktop'
    desktop.write_text('[Desktop Entry]\nType=Application\nExec=fcitx5\n')
    (root / 'config/kwinrc').write_text('[Wayland]\nInputMethod=' + str(desktop) + '\n')
    (root / 'trace').touch()
    env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'),
               KIMPANEL_FIXTURE=str(root), QT_QPA_PLATFORM='offscreen')
    fixture = subprocess.Popen([sys.executable, __file__, '--serve'], env=env)
    try:
        deadline = time.monotonic() + 5
        while not (root / 'ready').exists():
            assert time.monotonic() < deadline and fixture.poll() is None
            time.sleep(.01)
        def run(mode):
            subprocess.run([sys.argv[1], mode], env=env, check=True, timeout=20)
        def trace():
            return [json.loads(line) for line in (root / 'trace').read_text().splitlines()]
        def clear_choice():
            (root / 'config/kos/inputmethod.json').unlink(missing_ok=True)
        run('off')
        assert trace() == [], 'default-off destruction changed Fcitx'
        (root / 'fail-backup').touch()
        run('failure')
        assert trace() == [], 'failed backup changed Fcitx'
        (root / 'fail-backup').unlink()
        clear_choice()
        for mode in ('toggle', 'disconnect'):
            run(mode)
            assert trace()[-2:] == [dict(classicui=False, kimpanel=True),
                                   dict(classicui=True, kimpanel=False)]
            assert not (root / 'config/kos/inputmethod-recovery.json').exists()
            clear_choice()
        run('crash')
        assert (root / 'config/kos/inputmethod-recovery.json').exists()
        run('recover')
        assert trace()[-1] == dict(classicui=True, kimpanel=False)
        assert not (root / 'config/kos/inputmethod-recovery.json').exists()
        config = configparser.RawConfigParser()
        config.read(root / 'config/kwinrc')
        assert config['Wayland']['InputMethod'] == str(desktop)
        print('PASS: default-off, backup failure, toggle, Shell loss, crash recovery, original addon states')
    finally:
        fixture.terminate()
        fixture.wait(timeout=5)
