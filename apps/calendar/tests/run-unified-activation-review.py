#!/usr/bin/env python3
"""VM-only review of the legacy launcher's single-window activation contract."""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile
import time

repo = Path(__file__).resolve().parents[3]
build = Path(sys.argv[-1]).resolve() if len(sys.argv) > 1 else repo / '.build/apps-release'
if '--session' not in sys.argv:
    raise SystemExit(subprocess.call(['dbus-run-session', '--', sys.executable, __file__, '--session', str(build)]))
with tempfile.TemporaryDirectory(prefix='calendar-activation-review-') as directory:
    env = dict(os.environ, KOS_PIM_STORAGE_DIR=directory + '/data',
               XDG_CONFIG_HOME=directory + '/config', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
    service = subprocess.Popen([str(build / 'services/pim-service/kos-pim-service')], env=env)
    calendar = subprocess.Popen([str(build / 'apps/calendar/kos-calendar'), '--view', 'week'], env=env)
    def owner_pid():
        reply = subprocess.run(['dbus-send', '--session', '--print-reply', '--dest=org.freedesktop.DBus',
                                '/org/freedesktop/DBus', 'org.freedesktop.DBus.GetConnectionUnixProcessID',
                                'string:org.nextkde.Kos.Calendar'], capture_output=True, text=True)
        match = re.search(r'uint32 (\d+)', reply.stdout)
        return int(match[1]) if match else None
    try:
        deadline = time.monotonic() + 10
        while owner_pid() != calendar.pid and time.monotonic() < deadline:
            if calendar.poll() is not None:
                raise RuntimeError('Calendar exited before activation registration')
            time.sleep(.1)
        assert owner_pid() == calendar.pid, 'Calendar did not own its D-Bus identity'
        for arguments in ([], ['--view', 'today'], ['--view=planned'], ['--item', 'missing-test-id'], ['--view', 'completed']):
            subprocess.run([str(build / 'apps/todo/kos-todo'), *arguments], env=env, check=True, timeout=10)
            assert owner_pid() == calendar.pid and calendar.poll() is None, 'Legacy launch replaced the primary Calendar instance'
        print('UNIFIED_ACTIVATION_TESTS_PASSED')
    finally:
        calendar.terminate()
        calendar.wait(timeout=5)
        service.terminate()
        service.wait(timeout=5)
