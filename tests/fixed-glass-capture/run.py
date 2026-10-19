#!/usr/bin/env python3
"""Run the built effect in a private virtual KWin, without touching the desktop."""
import os
import json
import math
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
    config_match = re.search(r'FIXED_CAPTURE_CONFIG (\{[^\n]*\})', text)
    assert config_match, f'Client capture configuration missing; see {log}'
    capture = json.loads(config_match.group(1))
    # v8 adds the Gaussian kernel support around the fixed capture. Legacy
    # clients keep the original rectangle; both must allocate only once.
    padding = math.ceil(3 * capture['sigma']) if capture['continuous'] else 0
    width, height = capture['width'] + 2 * padding, capture['height'] + 2 * padding
    expected_size = (str(width), str(height))
    expected_background = f"{capture['x'] - padding},{capture['y'] - padding} {width}x{height}"
    assert allocations == [expected_size], f'Unexpected allocations: {allocations}; expected {expected_size}; see {log}'
    assert backgrounds == {expected_background}, f'Unexpected capture bounds: {backgrounds}; expected {expected_background}; see {log}'
    assert len(outlines) > 10, f'Outline did not animate: {outlines}'
    assert not re.search(r'ReferenceError|TypeError|Binding loop|Failed to load configuration|Shader.*failed', text), f'Runtime error; see {log}'
    print(f'PASS: {len(outlines)} changing outlines, one {width}x{height} capture allocation; {log}')
