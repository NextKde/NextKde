#!/usr/bin/env python3
"""Run the built effect in a private virtual KWin, without touching the desktop."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
build = repo / '.build/kosctl'
with tempfile.TemporaryDirectory(prefix='kos-fixed-glass-') as directory:
    stage = Path(directory)
    plugins = stage / 'plugins/kwin/effects/plugins'
    plugins.mkdir(parents=True)
    shutil.copy2(build / 'kwin-effects-glass/src/glass.so', plugins / 'glass.so')
    config = stage / 'config'
    config.mkdir()
    (config / 'kwinrc').write_text('[Plugins]\nglassEnabled=true\nblurEnabled=false\nscaleEnabled=false\nfadeEnabled=false\nfadingpopupsEnabled=false\nslidingpopupsEnabled=false\nsquashEnabled=false\n[Compositing]\nAnimationSpeed=1\n')
    (config / 'kdeglobals').write_text('[KDE]\nAnimationDurationFactor=0\n')
    session = stage / 'session'
    session.write_text('#!/bin/sh\nexec quickshell --path "' + str(Path(__file__).parent) + '" --no-color\n')
    session.chmod(0o755)
    env = {**os.environ, 'XDG_CONFIG_HOME': str(config),
           'QT_PLUGIN_PATH': str(stage / 'plugins'),
           'QML_IMPORT_PATH': str(build / 'qml'), 'QML2_IMPORT_PATH': str(build / 'qml'),
           'KOS_GLASS_TRACE': '1', 'QS_DISABLE_FILE_WATCHER': '1',
           'LIBGL_ALWAYS_SOFTWARE': '1', 'QT_FORCE_STDERR_LOGGING': '1',
           'QT_LOGGING_RULES': '*.warning=true;kwin_core.info=true;kwin_scene_opengl.info=true'}
    command = ['dbus-run-session', '--', 'kwin_wayland', '--virtual',
               '--width', '960', '--height', '640', '--socket', 'kos-fixed-' + str(os.getpid()),
               '--no-lockscreen', '--no-global-shortcuts', '--no-kactivities',
               '--exit-with-session', str(session)]
    log = repo / '.build/fixed-glass-capture.log'
    with log.open('w') as output:
        process = subprocess.Popen(command, env=env, stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            process.wait(timeout=25)
        finally:
            if process.poll() is None:
                import signal
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=5)
    text = log.read_text(errors='replace')
    allocations = re.findall(r'allocating capture chain QSize\((\d+), (\d+)\)', text)
    backgrounds = set(re.findall(r'backgroundRect QRect\(([^)]*)\)', text))
    outlines = set(re.findall(r'geom QRectF\(([^)]*)\)', text))
    assert 'FIXED_CAPTURE_PASS' in text, f'Client test failed; see {log}'
    assert len(allocations) == 1 and allocations[0] == ('832', '532'), f'Unexpected allocations: {allocations}; see {log}'
    assert len(backgrounds) == 1, f'Capture moved during animation: {backgrounds}'
    assert len(outlines) > 10, f'Outline did not animate: {outlines}'
    assert not re.search(r'ReferenceError|TypeError|Binding loop|Failed to load configuration|Shader.*failed', text), f'Runtime error; see {log}'
    print(f'PASS: {len(outlines)} changing outlines, one 832x532 capture allocation; {log}')
