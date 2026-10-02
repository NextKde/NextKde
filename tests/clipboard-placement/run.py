#!/usr/bin/env python3
"""Exercise shipping controller/window on an isolated bus and fake platform.

No input, clipboard contents or configuration reaches the user's session.
"""
import json
import os
from pathlib import Path
import re
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
import time

sys.dont_write_bytecode = True

REPO = Path(__file__).resolve().parents[2]


class Platform(socketserver.StreamRequestHandler):
    def handle(self):
        anchor = {}
        delay = 0
        paste_count = 0
        lock = threading.Lock()

        def reply(request, result):
            data = dict(version=1, requestId=request['requestId'], ok=True, result=result)
            try:
                with lock:
                    self.wfile.write((json.dumps(data) + '\n').encode())
                    self.wfile.flush()
            except (OSError, ValueError):
                pass

        try:
            for line in self.rfile:
                request = json.loads(line)
                op = request['operation']
                result = {}
                if op == 'test.configure-anchor':
                    anchor = request['payload']['anchor']
                    delay = request['payload'].get('delay', 0)
                elif op == 'input.clipboard-anchor':
                    timer = threading.Timer(delay / 1000, reply, args=(request, dict(anchor)))
                    timer.daemon = True
                    timer.start()
                    continue
                elif op == 'state.read':
                    result = {'exists': False}
                elif op == 'clipboard.history.list':
                    result = {'stdout': '1\tClipboard positioning fixture\n2\tSecond entry\n'}
                elif op == 'platform.ping':
                    result = {'capabilities': ['input.clipboard-anchor']}
                elif op == 'input.paste':
                    assert request['payload']['expectedWindowId'] == '{11111111-1111-1111-1111-111111111111}'
                    paste_count += 1
                elif op == 'test.paste-count':
                    result = {'count': paste_count}
                reply(request, result)
        except ConnectionResetError:
            pass


class Server(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True


def main():
    if '--private-bus' not in sys.argv:
        # No activation directories: a fixture must never start portals or
        # other services using the user's real runtime directory.
        with tempfile.NamedTemporaryFile(mode='w', suffix='.conf') as config:
            config.write('<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>'
                         '<policy context="default"><allow send_destination="*"/>'
                         '<allow receive_sender="*"/><allow own="*"/></policy></busconfig>')
            config.flush()
            subprocess.run(['dbus-run-session', '--config-file=' + config.name, '--',
                            sys.executable, __file__, '--private-bus'], check=True)
        return
    with tempfile.TemporaryDirectory(prefix='kos-clipboard-') as directory:
        root = Path(directory)
        for name in ['config', 'state', 'runtime']:
            (root / name).mkdir(mode=0o700)
        for name in ['desktop', 'Kos']:
            (root / name).symlink_to(REPO / 'shell' / name, target_is_directory=True)
        shutil.copy(Path(__file__).with_name('shell.qml'), root / 'shell.qml')
        with Server(str(root / 'platform.sock'), Platform) as server:
            threading.Thread(target=server.serve_forever, daemon=True).start()
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(root / 'runtime'),
                       KOS_PLATFORM_SOCKET=str(root / 'platform.sock'),
                       KOS_DATA_SOCKET=str(root / 'absent-data.sock'), QT_QPA_PLATFORM='wayland',
                       QT_QUICK_BACKEND='software', WAYLAND_DISPLAY='clipboard-test', DISPLAY='')
            effect = os.environ.get('KOS_TEST_INPUT_EFFECT')
            if effect:
                plugin_dir = root / 'plugins' / 'kwin' / 'effects' / 'plugins'
                plugin_dir.mkdir(parents=True)
                (plugin_dir / 'kos_context_menu_input.so').symlink_to(Path(effect).resolve())
                env['QT_PLUGIN_PATH'] = str(root / 'plugins')
            # Native layer surfaces need a compositor. This virtual KWin has
            # no desktop window, physical input, real session bus or user config.
            with (root / 'kwin.log').open('w+') as log:
                compositor = subprocess.Popen(['kwin_wayland', '--virtual', '--width', '800',
                    '--height', '600', '--no-lockscreen', '--no-global-shortcuts',
                    '--no-kactivities', '--socket', 'clipboard-test'],
                    env=dict(env, QT_QPA_PLATFORM='offscreen', KWIN_COMPOSE='Q',
                             QT_LOGGING_RULES='kwin_scripting.debug=true'),
                    stdout=log, stderr=log)
                try:
                    for _ in range(100):
                        if (root / 'runtime' / 'clipboard-test').exists():
                            break
                        if compositor.poll() is not None:
                            log.seek(0)
                            raise AssertionError(log.read())
                        time.sleep(0.05)
                    if effect:
                        from compositor_probe import probe
                        probe(root, env, log)
                    result = subprocess.run(['quickshell', '-p', str(root)], env=env,
                                            capture_output=True, text=True, timeout=20)
                finally:
                    compositor.terminate()
                    try:
                        compositor.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        compositor.kill()
                        compositor.wait()
            output = result.stdout + result.stderr
            assert result.returncode == 0 and 'CLIPBOARD_PLACEMENT_PASS' in output, output
            assert not re.search(r'PLACEMENT_FAIL|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign|is not a type', output), output
            server.shutdown()
            print('PASS: real QML placement, reserved bar, refreshed snapshots, repeat toggle, mode change, timeout, late replies, output loss and guarded paste')


if __name__ == '__main__':
    main()
