#!/usr/bin/env python3
"""Isolated T09 fault matrix; never starts a desktop or imports environment."""
import copy
import hashlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch
from PIL import Image
APP = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(APP / 'companion'))
from handoff import Runtime, build, validate, parse, read_reference
from resources import Store, NOTICE
loader = importlib.machinery.SourceFileLoader('session_wrapper', str(APP / 'bin/kos-user-session'))
spec = importlib.util.spec_from_loader(loader.name, loader)
wrapper = importlib.util.module_from_spec(spec); loader.exec_module(wrapper)
checks = 0

def rejected(fn):
    global checks
    try: fn()
    except (ValueError, OSError): checks += 1
    else: raise AssertionError('accepted invalid input')

start = time.monotonic()
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp) / 'store'; store = Store(root)
    runtime = Path(tmp) / 'runtime'; runtime.mkdir(mode=0o700)
    os.environ['XDG_RUNTIME_DIR'] = str(runtime)
    uid = os.geteuid()
    image = io.BytesIO(); Image.new('RGB', (19, 13), '#dd6633').save(image, 'PNG')
    store.publish(uid, image.getvalue(), consent=True, notice=NOTICE)
    a, b = Runtime(runtime), Runtime(runtime)
    d = build(a.session, uid, root, uid)
    validate(d, a.session, uid, root, uid)
    a.write(d, root, uid); b.write(build(b.session, uid, root, uid), root, uid)
    ap = runtime / ('kos-handoff-' + a.session); bp = runtime / ('kos-handoff-' + b.session)
    assert ap.stat().st_mode & 0o777 == 0o700
    assert (ap / 'handoff.json').stat().st_mode & 0o777 == 0o600
    for field, value in [('schemaVersion', 99), ('sessionId', b.session), ('issuedAt', int(time.time())-130), ('expiresAt', int(time.time())-1), ('outputs', [{}]*17), ('command', 'SECRET_SENTINEL')]:
        bad = copy.deepcopy(d); bad[field] = value
        rejected(lambda: validate(bad, a.session, uid, root, uid))
    for raw in (b'{', b'[]', b'{"a":1,"a":2}', b' '*16385, b'['*1500, '{}'.encode('utf-16')):
        rejected(lambda: validate(parse(raw), a.session, uid, root, uid))
    for resource in ({'path': '/home/secret', 'sha256': '0'*64}, {'version': '../escape', 'sha256': '0'*64}, {'version': d['resource']['version'], 'sha256': '0'*64}):
        bad = copy.deepcopy(d); bad['resource'] = resource
        rejected(lambda: validate(bad, a.session, uid, root, uid))
    bad = copy.deepcopy(d); bad['user']['uid'] = uid + 1
    rejected(lambda: validate(bad, a.session, uid, root, uid))
    output = dict(connector='eDP-2', hardwareId='abcd', width=2560, height=1600, refreshHz=239.998, scale=1.5, rotation=0, position=[0,0], crop=[0,0,1,1], vrr='never', hdr=False)
    for field, value in [('width', True), ('scale', float('nan')), ('crop', [0,0,2,1]), ('connector', 'x'*129), ('position', [99999,0])]:
        bad = copy.deepcopy(d); bad['outputs'] = [dict(output, **{field:value})]
        rejected(lambda: validate(bad, a.session, uid, root, uid))
    # Huge JSON integers remain rejected/default rather than OverflowError.
    for field in ('refreshHz', 'scale', 'crop'):
        bad = copy.deepcopy(d)
        bad['outputs'] = [dict(output, **{field: [0, 0, 10**400, 1] if field == 'crop' else 10**400})]
        rejected(lambda: validate(bad, a.session, uid, root, uid))
        raw = json.dumps(bad).encode()
        (ap / 'handoff.json').write_bytes(raw)
        assert read_reference(runtime, a.session, hashlib.sha256(raw).hexdigest(), root, uid) is None
    # Inode replacement, content mutation, symlink and overly permissive file.
    file = ap / 'handoff.json'
    file.unlink(); file.write_text(json.dumps(d)); file.chmod(0o600)
    rejected(lambda: a.consume(root, uid))
    a.write(d, root, uid); file.write_text('{}')
    rejected(lambda: a.consume(root, uid))
    file.unlink(); file.symlink_to(bp / 'handoff.json')
    rejected(lambda: a.consume(root, uid))
    a.write(d, root, uid); file.chmod(0o644)
    rejected(lambda: a.consume(root, uid))
    a.write(d, root, uid)
    assert read_reference(runtime, b.session, a.digest.hex(), root, uid) is None
    assert read_reference(runtime, a.session, a.digest.hex(), root, uid) == d
    assert read_reference(runtime, a.session, a.digest.hex(), root, uid) is None
    a.write(d, root, uid)
    store.revoke(uid)
    rejected(lambda: a.consume(root, uid))
    store.publish(uid, image.getvalue(), consent=True, notice=NOTICE)
    rejected(lambda: a.consume(root, uid))
    lock = a.lock(); rejected(b.lock); os.close(lock)
    a.close(); assert not ap.exists() and (bp / 'handoff.json').exists()
    b.close(); assert not bp.exists()
    # Shared shell/logind checks fail closed, without touching actual services.
    os.environ.pop('WAYLAND_DISPLAY', None); os.environ.pop('DISPLAY', None)
    with patch.dict(os.environ, {'WAYLAND_DISPLAY': 'wayland-test'}):
        rejected(wrapper.reject_existing)
    def result(rc=0, out=''):
        return subprocess.CompletedProcess([], rc, out, '')
    with patch.object(wrapper.subprocess, 'run', return_value=result()):
        rejected(wrapper.reject_existing)
    with patch.object(wrapper.subprocess, 'run', return_value=result(1)):
        rejected(wrapper.reject_existing)
    with patch.object(wrapper.subprocess, 'run', side_effect=[result(3), result(0, f'other {uid} user seat0 tty2\n'), result(0, 'Type=wayland\nState=active\n')]):
        rejected(wrapper.reject_existing)
    with patch.object(wrapper.subprocess, 'run', side_effect=[result(3), result(0, '')]):
        wrapper.reject_existing()
    # Validation failure launches the fixed child with no handoff reference.
    c = Runtime(runtime)
    with patch.object(wrapper, 'build', return_value={'command': 'SECRET_SENTINEL'}):
        with patch.dict(os.environ, {'KOS_HANDOFF_PATH':'stale', 'KOS_HANDOFF_SESSION':'stale', 'KOS_HANDOFF_SHA256':'stale'}):
            assert wrapper.run_session(c, root, uid, [sys.executable, '-c', 'import os; assert not any(k.startswith("KOS_HANDOFF_") for k in os.environ)']) == 0
    # Child process sees only local refs; normal and failed launch clean up.
    c = Runtime(runtime)
    code = 'import os,json; print(json.dumps({k:os.environ[k] for k in ("KOS_HANDOFF_PATH","KOS_HANDOFF_SESSION","KOS_HANDOFF_SHA256")}))'
    assert wrapper.run_session(c, root, uid, [sys.executable, '-c', code]) == 0
    assert not (runtime / ('kos-handoff-' + c.session)).exists()
    c = Runtime(runtime)
    assert wrapper.run_session(c, root, uid, [sys.executable, '-c', 'raise SystemExit(7)']) == 7
    c = Runtime(runtime)
    rejected(lambda: wrapper.run_session(c, root, uid, ['/nonexistent']))
    assert not (runtime / ('kos-handoff-' + c.session)).exists()
    # Termination forwarding and owner cleanup in another wrapper process.
    script = '''import os,sys,importlib.machinery,importlib.util
sys.path.insert(0,sys.argv[1]+"/companion")
from handoff import Runtime
l=importlib.machinery.SourceFileLoader("w",sys.argv[1]+"/bin/kos-user-session")
s=importlib.util.spec_from_loader(l.name,l);w=importlib.util.module_from_spec(s);l.exec_module(w)
r=Runtime(os.environ["XDG_RUNTIME_DIR"])
print(r.session,flush=True)
sys.exit(w.run_session(r, command=[sys.executable,"-c","import time;time.sleep(60)"]))
'''
    proc = subprocess.Popen([sys.executable, '-c', script, str(APP)], stdout=subprocess.PIPE, text=True)
    session = proc.stdout.readline().strip()
    target = runtime / ('kos-handoff-' + session)
    deadline = time.monotonic() + 5
    while not (target / 'handoff.json').exists() and time.monotonic() < deadline: time.sleep(.01)
    time.sleep(.1); proc.send_signal(signal.SIGTERM); proc.wait(timeout=6)
    assert not target.exists()
    # Default publication is a valid bounded descriptor; no secret fields.
    c = Runtime(runtime); default = build(c.session, uid, Path(tmp)/'missing', uid)
    c.write(default, Path(tmp)/'missing', uid); assert c.consume(Path(tmp)/'missing', uid)['resource']['version'] == 'default'; c.close()
    assert not list(runtime.glob('kos-handoff-*'))
    runtime.chmod(0o755); rejected(lambda: Runtime(runtime))
    runtime.chmod(0o700)
print(f'PASS T09: {checks} rejection cases; atomic permissions, same-UID isolation, single-use, revoke/replacement, lock, child failure/signal cleanup; elapsed={time.monotonic()-start:.3f}s')
