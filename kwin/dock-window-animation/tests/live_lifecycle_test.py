#!/usr/bin/env python3
"""VM-only: close a real Wayland window, unload the effect and exit mid-animation."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import time


def call(*args):
    return subprocess.run(args, capture_output=True, text=True, timeout=5, check=True).stdout.strip()


def drive(root, mode):
    effect = 'kos_dock_window_animation'
    call('qdbus6', 'org.kde.KWin', '/Effects', 'org.kde.kwin.Effects.loadEffect', effect)
    targets = dict(targets=[dict(appId=name, x=20, y=700, width=48, height=48)
                           for name in ('org.quickshell', 'quickshell', 'qs')])
    call('qdbus6', 'org.kde.KWin', '/KOSDockWindowAnimation', 'updateTargets', json.dumps(targets))
    client = subprocess.Popen(['qs', '--log-rules', '*.debug=false', '-p', str(root / 'client.qml')],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    (root / 'client.pid').write_text(str(client.pid))
    try:
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            try:
                if call('qs', '-p', str(root / 'client.qml'), 'ipc', 'call', 'lifecycle', 'ready') == 'ready':
                    break
            except subprocess.CalledProcessError:
                pass
            time.sleep(.1)
        else:
            raise RuntimeError('Client window did not map')
        call('qs', '-p', str(root / 'client.qml'), 'ipc', 'call', 'lifecycle', 'closeWindow')
        deadline = time.monotonic() + 1
        while time.monotonic() < deadline:
            state = json.loads(call('qdbus6', 'org.kde.KWin', '/KOSDockWindowAnimation', 'status'))
            if state['closeAnimationCount'] > 0 and state['animatingWindows'] > 0:
                break
            time.sleep(.01)
        else:
            raise RuntimeError('No active closing animation; teardown was not exercised')
        print('ACTIVE_CLOSE', mode, state['animatingWindows'], flush=True)
        if mode == 'unload':
            call('qdbus6', 'org.kde.KWin', '/Effects', 'org.kde.kwin.Effects.unloadEffect', effect)
            call('qdbus6', 'org.kde.KWin', '/KWin', 'supportInformation')
            print('PASS effect unload with active close', flush=True)
        else:
            print('EXIT_WITH_ACTIVE_CLOSE', flush=True)
    finally:
        # Exit the session driver immediately in the exit case. Waiting for the
        # client here could let the close animation finish before KWin teardown.
        if mode == 'unload':
            client.terminate()
            try:
                client.wait(timeout=2)
            except subprocess.TimeoutExpired:
                client.kill(); client.wait()


def main():
    if sys.argv[1:2] == ['--drive']:
        drive(Path(sys.argv[2]), sys.argv[3])
        return
    subprocess.run(['systemd-detect-virt', '--vm'], check=True, stdout=subprocess.DEVNULL)
    for mode in ('unload', 'exit'):
        with tempfile.TemporaryDirectory(prefix='kos-dock-lifecycle-') as directory:
            root = Path(directory)
            for name in ('runtime', 'config', 'data', 'cache'):
                (root / name).mkdir(mode=0o700)
            (root / 'config/kwinrc').write_text(
                '[Plugins]\nkos_bridgeEnabled=false\nkos_dock_window_animationEnabled=false\n'
                'scaleEnabled=false\nsquashEnabled=false\nfadeEnabled=false\n'
                '[Effect-kos_dock_window_animation]\nCloseDuration=1200\nCloseAnimation=scale\n')
            (root / 'client.qml').write_text('''import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
ShellRoot {
 id: root
 property int frames: 0
 FloatingWindow { id: window; visible: true; implicitWidth: 160; implicitHeight: 120
  Rectangle { anchors.fill: parent; color: "#345678" }
 }
 Connections { target: window.contentItem.Window.window; function onFrameSwapped() { root.frames++; } }
 IpcHandler { target: "lifecycle"
  function ready(): string { return root.frames > 0 ? "ready" : "waiting"; }
  function closeWindow(): string { window.visible = false; return "closed"; }
 }
}''')
            env = dict(os.environ, XDG_RUNTIME_DIR=str(root / 'runtime'),
                       XDG_CONFIG_HOME=str(root / 'config'), XDG_DATA_HOME=str(root / 'data'),
                       XDG_CACHE_HOME=str(root / 'cache'))
            for name in ('DISPLAY', 'WAYLAND_DISPLAY', 'WAYLAND_SOCKET', 'GREETD_SOCK', 'QT_QPA_PLATFORM'):
                env.pop(name, None)
            session = shlex.join([sys.executable, str(Path(__file__).resolve()), '--drive', str(root), mode])
            command = ['dbus-run-session', '--', 'kwin_wayland', '--virtual', '--output-count', '1',
                       '--width', '1024', '--height', '768', '--no-lockscreen', '--no-global-shortcuts',
                       '--no-kactivities', '--exit-with-session', session]
            try:
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=25)
            except subprocess.TimeoutExpired as error:
                print((error.stdout or b'').decode(errors='replace'))
                print((error.stderr or b'').decode(errors='replace'))
                raise
            finally:
                # KWin normally disconnects the client. Clean up a surviving
                # test client only after compositor teardown, checking its argv.
                pid_file = root / 'client.pid'
                if pid_file.exists():
                    pid = int(pid_file.read_text())
                    try:
                        argv = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
                        if os.fsencode(root / 'client.qml') in argv:
                            os.kill(pid, 15)
                    except ProcessLookupError:
                        pass
                    except FileNotFoundError:
                        pass
            print(result.stdout + result.stderr)
            required = 'PASS effect unload with active close' if mode == 'unload' else 'EXIT_WITH_ACTIVE_CLOSE'
            if result.returncode or required not in result.stdout:
                raise SystemExit('Dock ' + mode + ' lifecycle failed: exit ' + str(result.returncode))
    print('PASS real KWin unload and compositor exit with closing-window references')


if __name__ == '__main__':
    main()
