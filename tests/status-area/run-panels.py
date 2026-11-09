#!/usr/bin/env python3
"""Exercise real status panels with GPU-backed QML panel surfaces."""
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
    opengl = '--opengl' in sys.argv
    vulkan = '--vulkan' in sys.argv
    if '--private-bus' not in sys.argv:
        with tempfile.TemporaryDirectory(prefix='kos-status-panels-bus-') as directory:
            config = Path(directory) / 'bus.conf'
            config.write_text('<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>'
                '<policy context="default"><allow send_destination="*"/>'
                '<allow receive_sender="*"/><allow own="*"/></policy></busconfig>')
            subprocess.run(['dbus-run-session', '--config-file=' + str(config), '--',
                            sys.executable, __file__, *sys.argv[1:], '--private-bus'], check=True)
        return

    with tempfile.TemporaryDirectory(prefix='kos-status-panels-') as directory:
        root = Path(directory)
        for name in ['runtime', 'config', 'state', 'cache', 'data']:
            (root / name).mkdir(mode=0o700)
        for name in ['Kos', 'shared']:
            (root / name).symlink_to(REPO / 'shell' / name, target_is_directory=True)
        shutil.copytree(REPO / 'shell/desktop', root / 'desktop', symlinks=True)
        shutil.copy(Path(__file__).with_name('panels.qml'), root / 'shell.qml')
        shutil.copy(Path(__file__).with_name('PlatformFixture.qml'),
            root / 'desktop/modules/platform/PlatformClient.qml')
        qml_path = os.environ.get('QML_IMPORT_PATH', str(REPO / '.build/kosctl/qml'))
        env = dict(os.environ, XDG_RUNTIME_DIR=str(root / 'runtime'),
            XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
            XDG_CACHE_HOME=str(root / 'cache'), XDG_DATA_HOME=str(root / 'data'),
            KOS_PLATFORM_SOCKET=str(root / 'no-platform.sock'),
            KOS_DATA_SOCKET=str(root / 'no-data.sock'), WAYLAND_DISPLAY='status-panels-test',
            DISPLAY='', QT_QPA_PLATFORM='wayland', QT_FORCE_STDERR_LOGGING='1',
            QML_IMPORT_PATH=qml_path, QML2_IMPORT_PATH=qml_path)
        env.pop('QT_QUICK_BACKEND', None)
        env['QSG_RHI_BACKEND'] = 'vulkan' if vulkan else 'opengl'
        env['QSG_RENDER_LOOP'] = 'threaded'
        if '--scale-2' in sys.argv:
            env['QT_SCALE_FACTOR'] = '2'
        with (root / 'kwin.log').open('w+') as log:
            compositor = subprocess.Popen(['kwin_wayland', '--virtual', '--width', '1280',
                '--height', '900', '--output-count', '2', '--no-lockscreen', '--no-global-shortcuts', '--no-kactivities',
                '--socket', 'status-panels-test'],
                env=dict(env, QT_QPA_PLATFORM='offscreen', KWIN_COMPOSE='O2'), stdout=log, stderr=log)
            try:
                for _ in range(100):
                    if (root / 'runtime/status-panels-test').exists():
                        break
                    if compositor.poll() is not None:
                        log.seek(0)
                        raise AssertionError(log.read())
                    time.sleep(0.05)
                try:
                    result = subprocess.run(['quickshell', '--path', str(root), '--no-color'],
                        env=env, capture_output=True, text=True, timeout=25)
                except subprocess.TimeoutExpired as error:
                    print((error.stdout or b'').decode(errors='replace'), file=sys.stderr)
                    print((error.stderr or b'').decode(errors='replace'), file=sys.stderr)
                    raise
            finally:
                compositor.terminate()
                try:
                    compositor.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    compositor.kill()
                    compositor.wait()
        output = result.stdout + result.stderr
        assert result.returncode == 0 and 'STATUS_PANELS_PASS' in output, output
        assert not re.search(r'STATUS_PANELS_FAIL|ReferenceError|TypeError|'
            r'Cannot assign|Unable to assign|Binding loop|is not a type|is not a function', output), output
        count = re.search(r'STATUS_PANELS_PASS (\d+) checks', output).group(1)
        backend = 'Vulkan' if vulkan else 'OpenGL'
        print(f'PASS ({backend}): {count} checks: traffic summary/details/collapse, battery dashboard/states/telemetry, stable surfaces, secondary-screen placement and all three power modes')


if __name__ == '__main__':
    main()
