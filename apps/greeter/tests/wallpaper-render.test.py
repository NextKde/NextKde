#!/usr/bin/env python3
"""Actual Qt image renders on an isolated virtual compositor; no login seat."""
import os
from pathlib import Path
import signal
import subprocess
import tempfile

APP = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='kos-t07-virtual-') as tmp:
    env = os.environ.copy()
    for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'GREETD_SOCK', 'KOS_GREETER_OUTPUT_APPLY'):
        env.pop(key, None)
    env['XDG_CONFIG_HOME'] = tmp + '/config'
    env['KOS_T07_TEST'] = '1'
    with open(tmp + '/log', 'w') as stream:
        process = subprocess.Popen(['dbus-run-session', '--', 'kwin_wayland', '--virtual', '--output-count', '2',
            '--width', '1024', '--height', '768', '--socket', 'kos-t07-' + str(os.getpid()),
            '--no-lockscreen', '--no-global-shortcuts', '--no-kactivities', '--exit-with-session',
            str(APP / 'tests/wallpaper-render-session')], env=env, stdout=stream, stderr=stream, start_new_session=True)
        try: code = process.wait(timeout=55)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL); process.wait(); code = 124
    output = Path(tmp + '/log').read_text()
    print(output)
    assert code == 0, code
    assert 'PASS T07 Qt renders' in output
