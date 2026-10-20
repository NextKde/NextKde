#!/usr/bin/env python3
"""Exercise real control-center components on a private virtual KWin session."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[2]


def main():
    if '--private-bus' not in sys.argv:
        with tempfile.TemporaryDirectory(prefix='kos-control-center-bus-') as directory:
            config = Path(directory) / 'bus.conf'
            config.write_text('<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>'
                '<policy context="default"><allow send_destination="*"/>'
                '<allow receive_sender="*"/><allow own="*"/></policy></busconfig>')
            subprocess.run(['dbus-run-session', '--config-file=' + str(config), '--',
                            sys.executable, __file__, '--private-bus'], check=True)
        return

    with tempfile.TemporaryDirectory(prefix='kos-control-center-') as directory:
        root = Path(directory)
        for name in ['runtime', 'config', 'state', 'cache', 'data']:
            (root / name).mkdir(mode=0o700)
        for name in ['desktop', 'Kos', 'shared']:
            (root / name).symlink_to(REPO / 'shell' / name, target_is_directory=True)
        shutil.copy(Path(__file__).with_name('shell.qml'), root / 'shell.qml')
        qml_path = os.environ.get('QML_IMPORT_PATH', str(REPO / 'build/qml'))
        env = dict(os.environ, XDG_RUNTIME_DIR=str(root / 'runtime'),
            XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
            XDG_CACHE_HOME=str(root / 'cache'), XDG_DATA_HOME=str(root / 'data'),
            KOS_PLATFORM_SOCKET=str(root / 'no-platform.sock'),
            KOS_DATA_SOCKET=str(root / 'no-data.sock'), WAYLAND_DISPLAY='control-center-test',
            DISPLAY='', QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software',
            QML_IMPORT_PATH=qml_path, QML2_IMPORT_PATH=qml_path)
        with (root / 'kwin.log').open('w+') as log:
            compositor = subprocess.Popen(['kwin_wayland', '--virtual', '--width', '1280',
                '--height', '900', '--no-lockscreen', '--no-global-shortcuts', '--no-kactivities',
                '--socket', 'control-center-test'],
                env=dict(env, QT_QPA_PLATFORM='offscreen', KWIN_COMPOSE='Q'), stdout=log, stderr=log)
            try:
                for _ in range(100):
                    if (root / 'runtime/control-center-test').exists():
                        break
                    if compositor.poll() is not None:
                        log.seek(0)
                        raise AssertionError(log.read())
                    time.sleep(0.05)
                result = subprocess.run(['quickshell', '--path', str(root), '--no-color'],
                    env=env, capture_output=True, text=True, timeout=25)
            finally:
                compositor.terminate()
                try:
                    compositor.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    compositor.kill()
                    compositor.wait()
        output = result.stdout + result.stderr
        assert result.returncode == 0 and 'CONTROL_CENTER_MODULES_PASS' in output, output
        assert not re.search(r'CONTROL_CENTER_MODULES_FAIL|ReferenceError|TypeError|'
            r'Cannot assign|Unable to assign|Binding loop|is not a type|is not a function', output), output
        count = re.search(r'CONTROL_CENTER_MODULES_PASS (\d+) checks', output).group(1)
        print(f'PASS: {count} checks: injected card services, Wi-Fi credential routing, shared volume preview/commit, '
              'session confirmation cancellation, submenu navigation, close/reopen and Dock placement')


if __name__ == '__main__':
    main()
