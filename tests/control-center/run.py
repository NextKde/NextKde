#!/usr/bin/env python3
"""Exercise real control-center components on a private virtual KWin session."""
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

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
        session = root / 'session.sh'
        session.write_text('#!/bin/sh\nexec ' + shlex.join([
            'env', 'QT_QPA_PLATFORM=wayland', 'quickshell', '--path', str(root), '--no-color'
        ]) + ' > ' + shlex.quote(str(root / 'quickshell.log')) + ' 2>&1\n')
        session.chmod(0o755)
        with (root / 'kwin.log').open('w+') as log:
            compositor = subprocess.Popen(['kwin_wayland', '--virtual', '--width', '1280',
                '--height', '900', '--no-lockscreen', '--no-global-shortcuts', '--no-kactivities',
                '--socket', 'control-center-test', '--exit-with-session', str(session)],
                env=dict(env, QT_QPA_PLATFORM='offscreen', KWIN_COMPOSE='Q'), stdout=log, stderr=log)
            try:
                compositor.wait(timeout=30)
            finally:
                if compositor.poll() is None:
                    compositor.terminate()
                    try:
                        compositor.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        compositor.kill()
                        compositor.wait()
        qml_log = root / 'quickshell.log'
        output = qml_log.read_text() if qml_log.exists() else 'Quickshell was not started'
        compositor_log = (root / 'kwin.log').read_text()
        if os.environ.get('KOS_CONTROL_CENTER_QA'):
            qa = Path(os.environ['KOS_CONTROL_CENTER_QA'])
            qa.mkdir(parents=True, exist_ok=True)
            for path in root.glob('*.log'):
                shutil.copy(path, qa / path.name)
        assert compositor.returncode == 0 and 'CONTROL_CENTER_MODULES_PASS' in output, output + '\nKWin:\n' + compositor_log
        assert not re.search(r'CONTROL_CENTER_MODULES_FAIL|ReferenceError|TypeError|'
            r'Cannot assign|Unable to assign|Binding loop|is not a type|is not a function', output), output
        count = re.search(r'CONTROL_CENTER_MODULES_PASS (\d+) checks', output).group(1)
        print(f'PASS: {count} checks: injected card services, Wi-Fi credential routing, shared volume preview/commit, '
              'session confirmation cancellation, submenu navigation, close/reopen and Dock placement')


if __name__ == '__main__':
    main()
