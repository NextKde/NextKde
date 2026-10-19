#!/usr/bin/env python3
"""Two-output virtual KWin only; never DRM or host display-manager switching."""
import os
from pathlib import Path
import signal
import subprocess
import tempfile

APP = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='kos-t06-virtual-') as temporary:
    directory = Path(temporary)
    env = os.environ.copy()
    for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'GREETD_SOCK', 'KOS_GREETER_OUTPUT_APPLY'):
        env.pop(key, None)
    env['XDG_CONFIG_HOME'] = str(directory / 'config')
    env['KOS_T06_VIRTUAL_TEST'] = '1'
    log = directory / 'run.log'
    with log.open('wb') as stream:
        process = subprocess.Popen(['dbus-run-session', '--', 'kwin_wayland', '--virtual', '--output-count', '2',
            '--width', '1024', '--height', '768', '--socket', 'kos-t06-virtual-' + str(os.getpid()),
            '--no-lockscreen', '--no-global-shortcuts', '--no-kactivities', '--exit-with-session',
            str(APP / 'tests/virtual-display-session')], env=env, stdout=stream, stderr=stream, start_new_session=True)
        try:
            code = process.wait(timeout=35)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
            code = 124
    output = log.read_text(errors='replace')
    print(output)
    assert code == 0, ('virtual KWin exit', code)
    assert output.count('PASS virtual KWin:') == 5, output
    assert 'Traceback' not in output, output
