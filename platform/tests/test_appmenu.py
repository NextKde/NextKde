#!/usr/bin/env python3
"""Real daemon + fake dbusmenu on a private bus; no desktop applications."""
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
    name = dbus.service.BusName('org.kos.TestMenu', bus)
    trace = Path(os.environ['KOS_MENU_TRACE'])
    def record(value):
        with trace.open('a') as f:
            f.write(value + '\n')
    class Menu(dbus.service.Object):
        @dbus.service.method('com.canonical.dbusmenu', in_signature='i', out_signature='b')
        def AboutToShow(self, item):
            record('prepare:' + str(item))
            return True
        @dbus.service.method('com.canonical.dbusmenu', in_signature='iias', out_signature='u(ia{sv}av)')
        def GetLayout(self, item, depth, properties):
            record('layout:' + str(item))
            # Children travel inside variants; their nested dictionary must keep
            # a{sv} explicitly rather than letting dbus-python infer a{ss}.
            child = dbus.Struct((dbus.Int32(11), dbus.Dictionary({'label': 'Copy'}, signature='sv'), dbus.Array([], signature='v')), signature='ia{sv}av', variant_level=1)
            return 1, (item, {'label': 'Edit'}, dbus.Array([child], signature='v'))
        @dbus.service.method('com.canonical.dbusmenu', in_signature='isvu', out_signature='', async_callbacks=('done', 'failed'))
        def Event(self, item, event, data, timestamp, done, failed):
            record('event:' + str(event))
            GLib.timeout_add(800, lambda: (done(), False)[1])
    menu = Menu(bus, '/Menu')
    Path(os.environ['KOS_MENU_READY']).touch()
    GLib.MainLoop().run()
    sys.exit()

if '--session' not in sys.argv:
    subprocess.run(['dbus-run-session', '--', sys.executable, __file__, sys.argv[1], '--session'], check=True)
    sys.exit()

with tempfile.TemporaryDirectory(prefix='kos-menu-', dir='/tmp') as directory:
    root = Path(directory)
    runtime = root / 'runtime'
    runtime.mkdir(mode=0o700)
    trace = root / 'trace'
    ready = root / 'ready'
    env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM='offscreen',
               DBUS_SYSTEM_BUS_ADDRESS=os.environ['DBUS_SESSION_BUS_ADDRESS'],
               KOS_MENU_TRACE=str(trace), KOS_MENU_READY=str(ready))
    processes = []
    with (root / 'log').open('w+') as log:
        def wait_for(predicate):
            deadline = time.monotonic() + 15
            while not predicate():
                if time.monotonic() >= deadline or any(p.poll() is not None for p in processes):
                    log.seek(0)
                    raise AssertionError(log.read())
                time.sleep(.01)
        try:
            processes.append(subprocess.Popen([sys.executable, __file__, '--serve'], env=env, stdout=log, stderr=log))
            wait_for(ready.exists)
            processes.append(subprocess.Popen([sys.argv[1], 'daemon'], env=env, stdout=log, stderr=log))
            path = runtime / 'kos-platform.sock'
            wait_for(path.exists)
            with socket.socket(socket.AF_UNIX) as client:
                client.settimeout(10)
                client.connect(str(path))
                stream = client.makefile('r')
                def send(ident, op, **payload):
                    payload.update(service='org.kos.TestMenu', path='/Menu')
                    client.sendall((json.dumps(dict(version=1, requestId=ident, operation=op, payload=payload))+'\n').encode())
                def receive():
                    while True:
                        line = stream.readline()
                        if not line:
                            log.flush()
                            log.seek(0)
                            raise AssertionError('daemon disconnected; exits=' + str([p.poll() for p in processes])
                                                 + '\ntrace: ' + trace.read_text() + '\n' + log.read())
                        reply = json.loads(line)
                        if 'requestId' in reply:
                            return reply
                send('root', 'appmenu.layout', id=0, depth=2)
                assert receive()['ok']
                assert trace.read_text().splitlines() == ['layout:0']
                send('open', 'appmenu.open', id=10)
                wait_for(lambda: 'event:opened' in trace.read_text())
                send('fast', 'test.unknown')
                assert receive()['requestId'] == 'fast', 'opened Event blocked the daemon'
                assert receive()['requestId'] == 'open'
                send('child', 'appmenu.layout', id=10, depth=2)
                reply = receive()
                assert reply['ok'] and reply['result']['items'][0]['label'] == 'Copy', reply
                assert trace.read_text().splitlines() == ['layout:0', 'event:opened', 'prepare:10', 'layout:10']
                print('Appmenu: one preparation before layout, root bypass and nonblocking Event passed')
        finally:
            for process in reversed(processes):
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
