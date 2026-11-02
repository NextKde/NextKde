#!/usr/bin/env python3
"""Exercise production tray menus against real, delayed D-Bus peers in private KWin."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('fixture', REPO / 'tests/widget-experience/run.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)

def run(base_env=None):
    env = dict(os.environ if base_env is None else base_env)
    with tempfile.TemporaryDirectory(prefix='kos-tray-menu-') as directory:
        root = Path(directory)
        for name in ['desktop', 'Kos', 'shared']:
            (root / name).symlink_to(REPO / 'shell' / name, target_is_directory=True)
        shutil.copy(Path(__file__).with_name('shell.qml'), root / 'shell.qml')
        env.update(KOS_PLATFORM_SOCKET=str(root / 'platform.sock'), KOS_DATA_SOCKET=str(root / 'absent.sock'),
                   TRAY_MENU_EVENTS=str(root / 'events'), QT_QPA_PLATFORM='wayland')
        with fixture.Server(str(root / 'platform.sock'), fixture.Platform) as server:
            threading.Thread(target=server.serve_forever, daemon=True).start()
            with (root / 'provider.log').open('w+') as provider_log:
                provider = subprocess.Popen(['python3', str(Path(__file__).with_name('provider.py'))], env=env,
                    stdout=provider_log, stderr=subprocess.STDOUT)
                try:
                    result = subprocess.run(['quickshell', '--path', str(root), '--no-color'], env=env,
                                            capture_output=True, text=True, timeout=30)
                    output = result.stdout + result.stderr
                    print(output, flush=True)
                    provider_log.seek(0)
                    diagnostics = provider_log.read()
                    assert result.returncode == 0 and 'TRAY_MENU_PASS' in output, output + diagnostics
                    assert not any(error in output for error in ['ReferenceError', 'TypeError', 'Cannot assign', 'Binding loop']), output
                    assert (root / 'events').read_text().splitlines() == ['slow'], 'wrong application action dispatched'
                finally:
                    provider.terminate()
                    provider.wait(timeout=5)
                    server.shutdown()

fixture.run = run
fixture.__file__ = __file__
if __name__ == '__main__':
    fixture.main()
