#!/usr/bin/env python3
"""Verify actual Animator endpoints and ShaderEffect pixels on Wayland."""
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parent
repo = source.parents[1]
artifacts = repo / '.build/launcher-reveal-prototype'
artifacts.mkdir(parents=True, exist_ok=True)
subprocess.run(['bash', str(source / 'compile.sh')], check=True)
flags = shlex.split(subprocess.check_output(['pkg-config', '--cflags', '--libs', 'Qt6Gui'], text=True))
checker = artifacts / 'check-pixels'
subprocess.run(['c++', '-std=c++20', '-fPIC', str(source / 'check_pixels.cpp'), '-o', str(checker), *flags], check=True)
with tempfile.TemporaryDirectory(prefix='kos-launcher-prototype-') as directory:
    stage = Path(directory)
    for path in source.iterdir():
        if path.suffix in ['.qml', '.qsb']:
            shutil.copy2(path, stage / path.name)
    env = {**os.environ, 'QS_DISABLE_FILE_WATCHER': '1', 'QT_QPA_PLATFORM': 'wayland'}
    result = subprocess.run(['quickshell', '--path', str(stage / 'verify.qml'), '--no-color'],
                            env=env, capture_output=True, text=True, timeout=12)
    log = result.stdout + result.stderr
    (artifacts / 'verify.log').write_text(log)
    assert result.returncode == 0 and 'PROTOTYPE_PASS' in log, log[-3000:]
    assert not re.search(r'PROTOTYPE_FAIL|SDF_SHADER_ERROR|ReferenceError|TypeError|Binding loop|Cannot assign', log), log[-3000:]
    for name in ['closed', 'half', 'open', 'animated']:
        shutil.copy2(stage / (name + '.png'), artifacts / (name + '.png'))
    subprocess.run([str(checker), str(artifacts)], check=True)
print('PASS: 50 fixed cells; bounded 20% spread; open/close/reversal; fixed-size GPU SDF')
print('Artifacts:', artifacts)
