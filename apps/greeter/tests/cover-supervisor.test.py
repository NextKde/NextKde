#!/usr/bin/env python3
"""Resource lifecycle, peer selection, and real KWin termination/restart."""
import base64
import io
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import struct
import time
from PIL import Image

APP = Path(__file__).resolve().parents[1]
OUT = Path(os.environ.get('KOS_COVER_EVIDENCE', str(APP.parents[1] / 'docs/kos-greeter/evidence/T10')))
sys.path.insert(0, str(APP / 'companion'))
import cover
from handoff import Runtime, build, read_reference
from resources import Store, NOTICE

with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
    store = Store(root / 'store')
    image = io.BytesIO(); Image.new('RGB', (320,200), '#b3652a').save(image, format='PNG')
    manifest = store.publish(os.geteuid(), image.getvalue(), consent=True, notice=NOTICE)
    ref = Runtime(str(runtime))
    try:
        ref.write(build(ref.session, ref.uid, store.root, ref.uid), store.root, ref.uid)
        desc = read_reference(str(runtime), ref.session, ref.digest.hex(), store.root, ref.uid)
        assert desc is not None
        assert read_reference(str(runtime), ref.session, ref.digest.hex(), store.root, ref.uid) is None
        state, live = cover.resource_state(desc, store.root, ref.uid)
        assert live and state['version'] == manifest['version']
        assert base64.b64decode(state['source'].split(',',1)[1]) == image.getvalue()
        store.publish(ref.uid, image.getvalue(), consent=True, notice=NOTICE)
        state, live = cover.resource_state(desc, store.root, ref.uid)
        assert live is None and state['source'] == ''
        store.revoke(ref.uid)
        assert cover.resource_state(desc, store.root, ref.uid)[0]['source'] == ''
    finally: ref.close()
    sock = socket.socket(socket.AF_UNIX)
    sock.bind(str(root / 'wayland-test')); sock.listen()
    try:
        def roundtrip():
            client, _ = sock.accept()
            with client:
                assert client.recv(12) == struct.pack('=III', 1, 12 << 16, 2)
                client.sendall(struct.pack('=III', 2, 12 << 16, 1))
        worker = threading.Thread(target=roundtrip); worker.start()
        assert cover.connectable(root / 'wayland-test', {os.getpid()})
        worker.join()
        assert not cover.connectable(root / 'wayland-test', set())
    finally: sock.close()
from unittest.mock import patch
with tempfile.TemporaryDirectory() as tmp:
    placeholder = Path(tmp) / 'wayland-test'; placeholder.touch()
    real_popen = subprocess.Popen
    children = []
    def hung_ui(*args, **kwargs):
        child = real_popen([sys.executable, '-c', 'import time; time.sleep(60)'], start_new_session=True)
        children.append(child)
        return child
    started = time.monotonic()
    with patch.dict(os.environ, {'XDG_RUNTIME_DIR': tmp}), patch.object(cover, 'compositor_pids', return_value={os.getpid()}), patch.object(cover, 'connectable', return_value=True), patch.object(cover.subprocess, 'Popen', side_effect=hung_ui):
        cover.supervise(os.getpid(), timeout=.2)
    assert len(children) == 1 and children[0].poll() is not None
    assert time.monotonic() - started < 1.5
    with patch.dict(os.environ, {'XDG_RUNTIME_DIR': tmp}), patch.object(cover, 'compositor_pids', return_value=set()), patch.object(cover, 'connectable', return_value=False):
        cover.supervise(os.getpid(), timeout=.1)
# Process can vanish between poll() and killpg(); cleanup must still complete.
with tempfile.TemporaryDirectory() as tmp:
    (Path(tmp) / 'wayland-test').touch()
    from unittest.mock import Mock
    vanished = Mock(pid=99999999)
    vanished.poll.return_value = None
    with patch.dict(os.environ, {'XDG_RUNTIME_DIR': tmp}), patch.object(cover, 'compositor_pids', return_value={os.getpid()}), patch.object(cover, 'connectable', return_value=True), patch.object(cover.subprocess, 'Popen', return_value=vanished), patch.object(cover.os, 'killpg', side_effect=ProcessLookupError):
        cover.supervise(os.getpid(), timeout=.1)
    vanished.wait.assert_called_once_with(timeout=1)
import runpy
wrapper = runpy.run_path(str(APP / 'bin/kos-user-session'))
with tempfile.TemporaryDirectory() as tmp:
    reference = Runtime(tmp)
    directory = Path(tmp) / ('kos-handoff-' + reference.session)
    child = Mock(pid=99999998); child.wait.return_value = 0
    vanished = Mock(pid=99999999); vanished.poll.return_value = None
    with patch.dict(os.environ, {'XDG_RUNTIME_DIR': tmp}), patch.object(cover.subprocess, 'Popen', side_effect=[child, vanished]), patch.object(cover.os, 'killpg', side_effect=ProcessLookupError):
        assert wrapper['run_session'](reference, Path(tmp)/'missing', os.geteuid()) == 0
    assert not directory.exists()
print('PASS T10 wrapper exit race preserves handoff cleanup')
print('PASS T10 exit race still reaps UI after ProcessLookupError')
print('PASS T10 supervisor independent deadline kills unresponsive UI; socket timeout; no restart')
print('PASS T10 resource bytes/hash, single consumption, replacement/revocation, peer PID isolation')

with tempfile.TemporaryDirectory(prefix='kos-t10-supervisor-') as temp:
    env = os.environ.copy()
    for key in ('DISPLAY','WAYLAND_DISPLAY','GREETD_SOCK','KOS_HANDOFF_PATH','KOS_HANDOFF_SESSION','KOS_HANDOFF_SHA256'):
        env.pop(key, None)
    env['XDG_CONFIG_HOME'] = temp + '/config'
    for attempt in range(2):
        with (OUT / f'kwin-restart-{attempt}.log').open('w') as stream:
            compositor = subprocess.Popen(['dbus-run-session','--',('kwin_wayland' if attempt == 0 else 'kwin_wayland_wrapper'),'--virtual','--output-count','2','--width','1024','--height','768','--socket',f'wayland-kos-t10-supervisor-{os.getpid()}-{attempt}','--no-lockscreen','--no-global-shortcuts','--no-kactivities','--exit-with-session',str(APP / 'tests/cover-idle-session')], env=env, stdout=stream, stderr=stream, start_new_session=True)
            supervisor = subprocess.Popen([sys.executable, '-c', 'import sys; sys.path.insert(0,sys.argv[1]); import cover; cover.compositor_pids=lambda p: {n for n in cover.descendants(p) if cover.is_kwin(n)}; cover.supervise(int(sys.argv[2]))', str(APP / 'companion'), str(compositor.pid)], env=env, stdout=stream, stderr=stream, start_new_session=True)
            try:
                deadline = time.monotonic()+10
                log = OUT / f'kwin-restart-{attempt}.log'
                while time.monotonic()<deadline:
                    if log.read_text(errors='replace').count('FrameSubmitted') >= 2: break
                    if supervisor.poll() is not None: raise AssertionError(log.read_text())
                    time.sleep(.05)
                else: raise AssertionError(log.read_text())
                started = time.monotonic()
                os.killpg(compositor.pid, signal.SIGKILL); compositor.wait(timeout=3)
                supervisor.wait(timeout=3)
                elapsed = time.monotonic()-started
                assert supervisor.returncode == 0
                assert log.read_text().count('SocketConnected') == 1
                print(f'PASS T10 KWin termination/restart attempt {attempt}: recovery={elapsed:.3f}s; no automatic restart')
            finally:
                for process in (compositor,supervisor):
                    if process.poll() is None:
                        os.killpg(process.pid,signal.SIGTERM)
                        try: process.wait(timeout=3)
                        except subprocess.TimeoutExpired:
                            os.killpg(process.pid,signal.SIGKILL); process.wait()
