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
    connection = owner = controller = panel_owner = panel = None
    def record(item):
        with (root / 'trace').open('a') as f:
            f.write(json.dumps(item) + '\n')
    class Controller(dbus.service.Object):
        @dbus.service.method('org.fcitx.Fcitx.Controller1', in_signature='a(sb)')
        def SetAddonsState(self, values):
            addons.update({str(k): bool(v) for k, v in values})
            record(dict(addons))
        @dbus.service.method('org.fcitx.Fcitx.Controller1')
        def ReloadConfig(self):
            pass
    class Panel(dbus.service.Object):
        @dbus.service.method('org.nextkde.FcitxPanel1', out_signature='u')
        def Version(self):
            return 2 if (root / 'wrong-version').exists() else 3
        @dbus.service.method('org.nextkde.FcitxPanel1', out_signature='b')
        def NativeUiAvailable(self):
            return True
        @dbus.service.method('org.nextkde.FcitxPanel1', out_signature='b')
        def Active(self):
            return connection.name_has_owner('org.nextkde.InputPanel')
    def start():
        global connection, owner, controller, panel_owner, panel
        connection = dbus.SessionBus(private=True)
        owner = dbus.service.BusName('org.fcitx.Fcitx5', connection)
        controller = Controller(connection, '/controller')
        if not (root / 'missing-adapter').exists():
            panel_owner = dbus.service.BusName('org.nextkde.FcitxPanel', connection)
            panel = Panel(connection, '/org/nextkde/FcitxPanel')
    def poll():
        global connection, owner, controller, panel_owner, panel
        config = configparser.RawConfigParser()
        config.read(root / 'config/kwinrc')
        command = config.get('Wayland', 'InputMethod', fallback='')
        if not command and connection is not None:
            controller.remove_from_connection()
            if panel is not None:
                panel.remove_from_connection()
            panel_owner = panel = None
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
        assert trace() == [], 'default-off construction changed Fcitx'
        for problem in ('missing-adapter', 'wrong-version'):
            (root / problem).touch()
            run('failure')
            assert trace() == [], 'failed adapter negotiation changed Fcitx addons'
            assert not (root / 'config/kos/inputmethod-recovery.json').exists()
            (root / problem).unlink()
            clear_choice()
        for mode in ('toggle', 'disconnect'):
            run(mode)
            assert trace() == [], 'lease takeover must not rewrite Fcitx addons'
            assert not (root / 'config/kos/inputmethod-recovery.json').exists()
            clear_choice()
        run('crash')
        assert not (root / 'config/kos/inputmethod-recovery.json').exists(), \
            'takeover must not persist addon state'
        run('recover')
        assert trace() == [], 'recovery without a legacy record changed Fcitx'
        assert not (root / 'config/kos/inputmethod-recovery.json').exists()
        clear_choice()
        (root / 'config/kos').mkdir(parents=True, exist_ok=True)
        (root / 'config/kos/inputmethod-recovery.json').write_text(json.dumps({
            'classicui': True, 'kimpanel': False,
            'kwinInputMethod': str(desktop)}))
        run('off')
        assert trace() == [dict(classicui=True, kimpanel=False)], \
            'legacy recovery record was not applied exactly once'
        assert not (root / 'config/kos/inputmethod-recovery.json').exists()
        config = configparser.RawConfigParser()
        config.read(root / 'config/kwinrc')
        assert config['Wayland']['InputMethod'] == str(desktop)
        print('PASS: default-off, incompatible adapter rollback, lease-only toggle, Shell loss, no crash residue, one-shot legacy addon recovery')
    finally:
        fixture.terminate()
        fixture.wait(timeout=5)
