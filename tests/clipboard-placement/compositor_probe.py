"""Optional real KWin probe; requires python-dbus and a built input effect."""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import time


def probe(root, env, log):
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    class Reporter(dbus.service.Object):
        window_id = ''

        @dbus.service.method('org.kos.AnchorTest', in_signature='s', out_signature='')
        def windowId(self, value):
            self.window_id = str(value)

    reporter = Reporter(dbus.service.BusName('org.kos.AnchorTest', bus), '/Test')
    effects = dbus.Interface(bus.get_object('org.kde.KWin', '/Effects'), 'org.kde.kwin.Effects')
    assert effects.loadEffect('kos_context_menu_input'), 'built effect did not load'
    bridge = dbus.Interface(bus.get_object('org.kde.KWin', '/KOSContextMenuInput'), 'org.kos.KWin.ContextMenuInput')
    pointer = dict(bridge.clipboardAnchor(''))
    assert pointer['available'] and pointer['source'] == 'pointer', pointer
    editor = root / 'editor'
    editor.mkdir()
    shutil.copy(Path(__file__).with_name('editor.qml'), editor / 'shell.qml')
    with (root / 'editor.log').open('w+') as editor_log:
        app = subprocess.Popen(['quickshell', '-p', str(editor)],
            env=dict(env, QT_IM_MODULE='wayland', QT_IM_MODULES='wayland'),
            stdout=editor_log, stderr=editor_log)
        daemon = None
        try:
            time.sleep(0.8)
            script = root / 'window-id.js'
            script.write_text('callDBus("org.kos.AnchorTest", "/Test", "org.kos.AnchorTest",'
                              '"windowId", workspace.activeWindow.internalId.toString());')
            scripting = dbus.Interface(bus.get_object('org.kde.KWin', '/Scripting'), 'org.kde.kwin.Scripting')
            assert scripting.loadScript(str(script), 'anchor-test', signature='ss') >= 0
            scripting.start()
            for _ in range(40):
                while GLib.MainContext.default().iteration(False):
                    pass
                if reporter.window_id:
                    break
                time.sleep(0.05)
            window_id = reporter.window_id
            assert window_id, 'fixture window ID not reported'
            first = dict(bridge.clipboardAnchor(window_id))
            assert first['source'] == 'caret' and first['height'] > 0, first
            assert dict(bridge.clipboardAnchor('{11111111-1111-1111-1111-111111111111}'))['source'] == 'pointer'
            move_reply = subprocess.run(['quickshell', '-p', str(editor), 'ipc', 'call', 'fixture', 'move'],
                           env=env, check=True, capture_output=True, text=True)
            expected = json.loads(move_reply.stdout)
            for _ in range(40):
                moved = dict(bridge.clipboardAnchor(window_id))
                if moved['x'] != first['x']:
                    break
                time.sleep(0.05)
            assert moved['source'] == 'caret', moved
            assert expected['dx'] != 0 and abs(moved['x'] - first['x'] - expected['dx']) < 1, (expected, moved)
            assert moved['y'] == first['y'], (first, moved)

            # If supplied, exercise the actual daemon's JSONL -> D-Bus path too.
            binary = os.environ.get('KOS_TEST_PLATFORM_BINARY')
            if binary:
                daemon_env = dict(env, KOS_PLATFORM_SOCKET=str(root / 'real-platform.sock'),
                                  KOS_PLATFORM_KWIN_SCRIPT='')
                daemon = subprocess.Popen([binary, 'daemon'], env=daemon_env,
                                          stdout=editor_log, stderr=editor_log)
                for _ in range(100):
                    if (root / 'real-platform.sock').exists():
                        break
                    time.sleep(0.05)
                def request():
                    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                        client.settimeout(3)
                        client.connect(str(root / 'real-platform.sock'))
                        client.sendall((json.dumps(dict(version=1, requestId='probe',
                            operation='input.clipboard-anchor', payload=dict(expectedWindowId=window_id))) + '\n').encode())
                        with client.makefile('rb') as stream:
                            return json.loads(stream.readline())
                response = request()
                assert response['ok'] and response['result']['source'] == 'caret', response
                assert abs(response['result']['x'] - moved['x']) < 1, response

            subprocess.run(['quickshell', '-p', str(editor), 'ipc', 'call', 'fixture', 'disable'],
                           env=env, check=True, capture_output=True)
            for _ in range(40):
                fallback = dict(bridge.clipboardAnchor(window_id))
                if fallback['source'] == 'pointer':
                    break
                time.sleep(0.05)
            assert fallback['source'] == 'pointer', fallback
            if binary:
                assert request()['result']['source'] == 'pointer', 'daemon must not cache the caret'
            print('PASS: real Wayland caret, moved caret, wrong target, non-text pointer fallback'
                  + (' and daemon forwarding' if binary else ''))
        except Exception:
            editor_log.seek(0)
            print(editor_log.read())
            print(Path(log.name).read_text())
            raise
        finally:
            for process in [daemon, app]:
                if process is not None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
