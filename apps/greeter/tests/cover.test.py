#!/usr/bin/env python3
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

APP = Path(__file__).resolve().parents[1]
OUT = Path(os.environ.get('KOS_COVER_EVIDENCE', str(APP.parents[1] / '.build/greeter-tests/T10')))
OUT.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(APP / 'companion'))
import cover

with tempfile.TemporaryDirectory(prefix='kos-t10-') as temp:
    env = os.environ.copy()
    for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'GREETD_SOCK', 'KOS_HANDOFF_PATH', 'KOS_HANDOFF_SESSION', 'KOS_HANDOFF_SHA256'):
        env.pop(key, None)
    env.update(XDG_CONFIG_HOME=temp+'/config', KOS_T10_TEST='1', KOS_T10_EVIDENCE=str(OUT))
    with (OUT / 'virtual.log').open('w') as stream:
        compositor = subprocess.Popen(['dbus-run-session', '--', 'kwin_wayland', '--virtual', '--output-count', '2', '--width', '1024', '--height', '768', '--socket', 'wayland-kos-t10-'+str(os.getpid()), '--no-lockscreen', '--no-global-shortcuts', '--no-kactivities', '--exit-with-session', str(APP / 'tests/cover-session')], env=env, stdout=stream, stderr=stream, start_new_session=True)
        try: code = compositor.wait(timeout=60)
        except subprocess.TimeoutExpired:
            os.killpg(compositor.pid, signal.SIGKILL); compositor.wait(); code=124
    text = (OUT / 'virtual.log').read_text(errors='replace')
    print('\n'.join(line for line in text.splitlines() if line.startswith('PASS')))
    assert code == 0, code
    assert text.count('PASS T10') == 9, text
from PIL import Image
for name, pixel in [('valid-resource', (179,101,42)), ('shell-ready', (22,40,59))]:
    for output in ('Virtual-0','Virtual-1'):
        image = Image.open(OUT / f'{name}-{output}.png').convert('RGB')
        assert image.size == (1024,768)
        assert image.getpixel((512,384)) == pixel
print('PASS Cover snapshots: default and valid fixture on both outputs')
print('PASS isolated Cover matrix')
