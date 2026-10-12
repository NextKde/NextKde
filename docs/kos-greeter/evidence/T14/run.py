#!/usr/bin/env python3
"""T14 isolated regression collection. Never installs or switches host services."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
CASES = [
    ('resources', ['python3', 'apps/greeter/tests/resources.test.py']),
    ('accounts', ['python3', 'apps/greeter/tests/accounts.test.py']),
    ('lifecycle', ['node', 'apps/greeter/tests/lifecycle.test.cjs']),
    ('ipc', ['python3', 'apps/greeter/tests/ipc.test.py']),
    ('handoff', ['python3', 'apps/greeter/tests/handoff.test.py']),
    ('wallpaper', ['python3', 'apps/greeter/tests/wallpaper.test.py']),
    ('fallback', ['python3', 'apps/greeter/tests/fallback.test.py']),
    ('install', ['python3', 'apps/greeter/tests/install.test.py']),
    ('entry', ['python3', 'apps/greeter/tests/entry.test.py']),
    ('protocol', ['node', 'apps/greeter/tests/entry-protocol.test.cjs']),
    ('wallpaper-handoff', ['node', 'shell/desktop/modules/wallpaper/test_wallpaper_handoff.mjs']),
    ('measurement', ['python3', 'apps/greeter/tests/measurement.test.py']),
    ('display', ['python3', 'apps/greeter/tests/virtual-display.test.py']),
    ('cover', ['python3', 'apps/greeter/tests/cover.test.py']),
    ('supervisor', ['python3', 'apps/greeter/tests/cover-supervisor.test.py']),
    ('production-layer', ['python3', 'apps/greeter/tests/entry-virtual.test.py']),
]

def service_state():
    result = subprocess.run(['systemctl', 'show', 'display-manager.service', 'greetd.service',
        '-p', 'Id', '-p', 'ActiveState', '-p', 'UnitFileState'], capture_output=True, text=True, timeout=10)
    if result.returncode: raise RuntimeError('Cannot record host service state')
    return result.stdout

def main():
    before = service_state()
    (OUT / 'services-before.txt').write_text(before)
    env = os.environ.copy()
    # Each UI suite creates its own virtual compositor / private D-Bus.
    for key in ('GREETD_SOCK', 'KOS_HANDOFF_PATH', 'KOS_HANDOFF_SESSION', 'KOS_HANDOFF_SHA256'):
        env.pop(key, None)
    for directory in ('cover', 'production-layer'):
        (OUT / directory).mkdir(exist_ok=True)
    env.update(KOS_COVER_EVIDENCE=str(OUT / 'cover'), KOS_ENTRY_EVIDENCE=str(OUT / 'production-layer'),
               KOS_T12_PRODUCTION_LAYER='1')
    results = []
    def run(name, command):
        start = time.monotonic()
        with (OUT / (name + '.log')).open('w') as log:
            p = subprocess.Popen(command, cwd=REPO, env=env, stdout=log, stderr=log, start_new_session=True)
            try:
                code = p.wait(timeout=180)
            except subprocess.TimeoutExpired:
                code = 124
            finally:
                # Also reap fixture descendants if a suite fails or times out.
                try: os.killpg(p.pid, signal.SIGTERM)
                except ProcessLookupError: pass
                if p.poll() is None:
                    try: p.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(p.pid, signal.SIGKILL); p.wait()
        results.append(dict(case=name, command=command, exit=code, elapsedSeconds=round(time.monotonic()-start, 3),
                            evidence=name+'.log', scope='isolated'))
        print(f'{name}: exit={code}', flush=True)
    try:
        for name, command in CASES: run(name, command)
        with tempfile.TemporaryDirectory(prefix='kos-t14-bundle-') as temp:
            run('bundle', ['python3', 'tools/greeter-install.py', '--build', temp+'/bundle', '--no-wallpaper-sync'])
            manifest = json.loads((Path(temp)/'bundle/manifest.json').read_text())
            (OUT/'bundle-files.json').write_text(json.dumps(manifest, indent=2)+'\n')
        run('diff-check', ['git', 'diff', '--check'])
    finally:
        after = service_state()
        (OUT/'services-after.txt').write_text(after)
        (OUT/'results.json').write_text(json.dumps(dict(results=results, servicesUnchanged=before == after), indent=2)+'\n')
    if before != after or any(r['exit'] for r in results): return 1
    return 0

if __name__ == '__main__': sys.exit(main())
