#!/usr/bin/env python3
"""Brightness IPC regressions on a private bus with fake hardware only."""
import json
import os
from pathlib import Path
import socket
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
    bus = dbus.SessionBus()
    names = [dbus.service.BusName(name, bus) for name in
             ('org.kde.ScreenBrightness', 'org.kde.Solid.PowerManagement')]
    root = Path(os.environ['BRIGHTNESS_FIXTURE'])
    def mode():
        return (root / 'mode').read_text()
    def record(*args):
        with (root / 'trace').open('a') as f:
            f.write(json.dumps(args) + '\n')
    class Manager(dbus.service.Object):
        @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='ss', out_signature='v')
        def Get(self, interface, prop):
            assert interface == 'org.kde.ScreenBrightness' and prop == 'DisplaysDBusNames'
            record('enumerate')
            return dbus.Array([] if mode() in ('solid', 'legacy') else ['internal', 'external'], signature='s')
    class Display(dbus.service.Object):
        def __init__(self, ident):
            super().__init__(bus, '/org/kde/ScreenBrightness/' + ident)
            self.ident = ident
        @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='ss', out_signature='v')
        def Get(self, interface, prop):
            assert interface == 'org.kde.ScreenBrightness.Display' and prop == 'MaxBrightness'
            record('maximum', self.ident)
            return dbus.Int32(200 if self.ident == 'external' else 100)
        @dbus.service.method('org.kde.ScreenBrightness.Display', in_signature='iu', out_signature='',
                             async_callbacks=('done', 'failed'))
        def SetBrightness(self, value, flags, done, failed):
            record('set', self.ident, int(value))
            state = mode()
            if state == 'hang' and self.ident == 'external':
                return
            if state == 'fail-all' or (state == 'partial' and self.ident == 'external'):
                failed(dbus.exceptions.DBusException('fixture failure', name='org.test.Failed'))
                return
            if state == 'delayed':
                GLib.timeout_add(800, lambda: (done(), False)[1])
            else:
                done()
    class Solid(dbus.service.Object):
        @dbus.service.method('org.kde.Solid.PowerManagement.Actions.BrightnessControl', out_signature='i')
        def brightnessMax(self):
            record('solid-max')
            return 0 if mode() == 'legacy' else 1000
        @dbus.service.method('org.kde.Solid.PowerManagement.Actions.BrightnessControl', in_signature='i')
        def setBrightness(self, value):
            record('solid-set', int(value))
    objects = [Manager(bus, '/org/kde/ScreenBrightness'), Display('internal'), Display('external'),
               Solid(bus, '/org/kde/Solid/PowerManagement/Actions/BrightnessControl')]
    (root / 'ready').touch()
    GLib.MainLoop().run()
    sys.exit()

if '--session' not in sys.argv:
    subprocess.run(['dbus-run-session', '--', sys.executable, __file__, sys.argv[1], '--session'], check=True)
    sys.exit()

with tempfile.TemporaryDirectory(prefix='kos-brightness-', dir='/tmp') as directory:
    root = Path(directory)
    for name in ('runtime', 'config', 'state', 'bin'):
        (root / name).mkdir(mode=0o700)
    (root / 'mode').write_text('normal')
    (root / 'trace').touch()
    stub = root / 'bin/brightnessctl'
    stub.write_text('#!/bin/sh\nprintf "legacy\\n" >> "$BRIGHTNESS_FIXTURE/legacy"\n')
    stub.chmod(0o700)
    env = dict(os.environ, BRIGHTNESS_FIXTURE=str(root), HOME=str(root),
               XDG_RUNTIME_DIR=str(root / 'runtime'), XDG_CONFIG_HOME=str(root / 'config'),
               XDG_STATE_HOME=str(root / 'state'), KOS_PLATFORM_SOCKET=str(root / 'runtime/socket'),
               PATH=str(root / 'bin') + os.pathsep + os.environ['PATH'],
               QT_QPA_PLATFORM='offscreen', DISPLAY='', WAYLAND_DISPLAY='',
               DBUS_SYSTEM_BUS_ADDRESS=os.environ['DBUS_SESSION_BUS_ADDRESS'])
    processes = []
    with (root / 'log').open('w+') as log:
        def wait_for(predicate):
            deadline = time.monotonic() + 15
            while not predicate():
                if time.monotonic() >= deadline or any(p.poll() is not None for p in processes):
                    log.seek(0)
                    raise AssertionError(log.read())
                time.sleep(.01)
        def trace():
            return [json.loads(line) for line in (root / 'trace').read_text().splitlines()]
        def scenario(name):
            (root / 'mode').write_text(name)
            (root / 'trace').write_text('')
        try:
            processes.append(subprocess.Popen([sys.executable, __file__, '--serve'], env=env, stdout=log, stderr=log))
            wait_for((root / 'ready').exists)
            processes.append(subprocess.Popen([sys.argv[1], 'daemon'], env=env, stdout=log, stderr=log))
            wait_for((root / 'runtime/socket').exists)
            with socket.socket(socket.AF_UNIX) as client:
                client.settimeout(10)
                client.connect(str(root / 'runtime/socket'))
                stream = client.makefile('r')
                def send(ident, percent=60, display=None, top=False, op='display.brightness.set'):
                    req = dict(version=1, requestId=ident, operation=op, payload={})
                    (req if top else req['payload'])['percent'] = percent
                    if display is not None: req['payload']['displayId'] = display
                    client.sendall((json.dumps(req) + '\n').encode())
                def receive(ident):
                    while True:
                        line = stream.readline()
                        assert line, 'daemon disconnected'
                        response = json.loads(line)
                        if 'requestId' in response:
                            assert response['requestId'] == ident, response
                            return response
                send('all')
                assert receive('all')['ok']
                assert sorted(trace()) == sorted([['enumerate'], ['maximum', 'internal'], ['maximum', 'external'],
                                                  ['set', 'internal', 60], ['set', 'external', 120]])
                scenario('normal')
                send('single', display='external')
                assert receive('single')['ok']
                assert ['set', 'external', 120] in trace() and ['maximum', 'internal'] not in trace()
                scenario('normal')
                send('missing', display='missing')
                assert not receive('missing')['ok']
                assert trace() == [['enumerate']]
                for percent, expected in ((-20, 0), (150, 100)):
                    scenario('normal')
                    send('clamp', percent, top=True)
                    assert receive('clamp')['result']['percent'] == expected
                    assert ['set', 'external', expected * 2] in trace()
                for state, code in (('partial', 'brightness-partial-failure'),
                                    ('fail-all', 'brightness-display-set-failed'),
                                    ('hang', 'brightness-partial-failure')):
                    scenario(state)
                    send('failure')
                    response = receive('failure')
                    assert not response['ok'] and response['error']['code'] == code, response
                    results = response['error']['details']['displays']
                    assert len(results) == 2 and any(not r['ok'] for r in results)
                    assert not any(row[0].startswith('solid') for row in trace())
                    assert not (root / 'legacy').exists()
                scenario('delayed')
                send('slow')
                wait_for(lambda: len([r for r in trace() if r[0] == 'set']) == 2)
                send('fast', op='platform.ping')
                assert receive('fast')['ok'], 'slow brightness blocked unrelated IPC'
                assert receive('slow')['ok']
                scenario('solid')
                send('solid', 37)
                assert receive('solid')['ok']
                assert trace() == [['enumerate'], ['enumerate'], ['solid-max'], ['solid-set', 370]]
                scenario('legacy')
                send('legacy')
                assert receive('legacy')['ok']
                assert (root / 'legacy').read_text() == 'legacy\n'
                assert ['solid-set', 600] not in trace()
                print('Brightness: targeting, parallel writes, partial failure, timeout, fallbacks and clamping passed')
        finally:
            for process in reversed(processes):
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
