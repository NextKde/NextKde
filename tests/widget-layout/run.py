#!/usr/bin/env python3
"""Exercise real widget edit gestures; keep settings/platform isolated."""
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import threading

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('widget_fixture', REPO / 'tests/widget-experience/run.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)

runtime = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
wayland = os.environ.get('WAYLAND_DISPLAY', 'wayland-0')
with tempfile.TemporaryDirectory(prefix='kos-widget-layout-') as directory:
    root = Path(directory)
    for name in ['config', 'state', 'runtime']:
        (root / name).mkdir(mode=0o700)
    (root / 'runtime' / wayland).symlink_to(runtime / wayland)
    for name in ['desktop', 'Kos']:
        (root / name).symlink_to(REPO / 'shell' / name, target_is_directory=True)
    shutil.copy(Path(__file__).with_name('shell.qml'), root / 'shell.qml')
    with fixture.Server(str(root / 'platform.sock'), fixture.Platform) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        env = dict(os.environ, XDG_CONFIG_HOME=str(root/'config'), XDG_STATE_HOME=str(root/'state'),
                   XDG_RUNTIME_DIR=str(root/'runtime'), KOS_PLATFORM_SOCKET=str(root/'platform.sock'),
                   KOS_DATA_SOCKET=str(root/'absent-data.sock'), QT_QPA_PLATFORM='wayland')
        for saved in ['0', '1']:
            result = subprocess.run(['quickshell', '--path', str(root), '--no-color'],
                                    env=dict(env, VERIFY_SAVED=saved), capture_output=True, text=True, timeout=20)
            output = result.stdout + result.stderr
            assert result.returncode == 0, output
            assert not re.search(r'WIDGET_LAYOUT_FAIL|ReferenceError|TypeError|Cannot assign|Unable to assign|is not a type|Binding loop', output), output
            marker = 'WIDGET_LAYOUT_SAVED_PASS' if saved == '1' else 'WIDGET_LAYOUT_PASS:'
            assert marker in output, output
            if saved == '0': assert 'WIDGET_FREE_RESIZE_PASS' in output, output
            print('\n'.join(line for line in output.splitlines() if marker in line or 'WIDGET_FREE_RESIZE_PASS' in line))
        server.shutdown()
