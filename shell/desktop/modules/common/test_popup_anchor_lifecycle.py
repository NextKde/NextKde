#!/usr/bin/env python3
"""Exercise the production binding without importing desktop singletons."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix='kos-popup-anchor-') as directory:
    root = Path(directory)
    for name in ('PopupAnchorBinding.qml', 'test_popup_anchor_lifecycle.qml'):
        shutil.copyfile(source / name, root / name)
    runtime = root / 'runtime'
    runtime.mkdir(mode=0o700)
    env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM='offscreen',
               QT_QUICK_BACKEND='software', QS_DISABLE_FILE_WATCHER='1')
    try:
        result = subprocess.run(['qs', '--log-rules', '*.debug=false', '-p',
                                 str(root / 'test_popup_anchor_lifecycle.qml')],
                                env=env, capture_output=True, text=True, timeout=10)
    except subprocess.TimeoutExpired as error:
        print(error.stdout, error.stderr)
        raise SystemExit('Popup anchor lifecycle timed out')
    output = result.stdout + result.stderr
    print(output)
    if result.returncode or 'PASS popup anchor null, replacement and destruction' not in output:
        raise SystemExit('Popup anchor lifecycle failed')
