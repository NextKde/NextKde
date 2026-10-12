"""Bounded early cover supervisor and static, revocation-aware resource feed."""
import base64
import json
import os
from pathlib import Path
import signal
import socket
import stat
import struct
import subprocess
import sys
import time
from handoff import PUBLIC_ROOT, read_reference, validate
from wallpaper import Reader
from session_output import diagnostic

APP = Path(__file__).resolve().parents[1]


def event(name):
    diagnostic(f'KOS_COVER {name} {time.monotonic_ns()}')


def descendants(pid):
    result = {pid}
    pending = [pid]
    while pending:
        current = pending.pop()
        try:
            children = Path(f'/proc/{current}/task/{current}/children').read_text().split()
        except OSError:
            continue
        for child in children:
            value = int(child)
            if value not in result:
                result.add(value); pending.append(value)
    return result


def connectable(path, allowed, on_peer=None):
    try:
        metadata = path.lstat()
        if not stat.S_ISSOCK(metadata.st_mode) or metadata.st_uid != os.geteuid(): return False
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(.1)
            connection.connect(str(path))
            pid, uid, _ = struct.unpack('3i', connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
            if uid != os.geteuid() or pid not in allowed: return False
            if on_peer is not None: on_peer()
            # wl_display.sync(new_id=2). A wrapper can listen before KWin reads
            # inherited fds; only a complete callback proves protocol service.
            connection.sendall(struct.pack("=III", 1, (12 << 16), 2))
            deadline = time.monotonic() + .15
            data = b""
            while time.monotonic() < deadline:
                connection.settimeout(max(.001, deadline - time.monotonic()))
                chunk = connection.recv(4096)
                if not chunk: return False
                data += chunk
                while len(data) >= 8:
                    object_id, header = struct.unpack_from("=II", data)
                    size, opcode = header >> 16, header & 0xffff
                    if size < 8 or size % 4 or size > 65536: return False
                    if len(data) < size: break
                    if object_id == 2 and opcode == 0 and size == 12: return True
                    if object_id == 1 and opcode == 0: return False
                    data = data[size:]
            return False
    except OSError:
        return False


def compositor_pids(pid):
    allowed = descendants(pid)
    # Plasma's systemd boot starts KWin under the user manager, outside the
    # wrapper subtree. Read the fixed service PID; never import its environment.
    try:
        result = subprocess.run(['/usr/bin/systemctl', '--user', 'show', 'plasma-kwin_wayland.service', '--property=MainPID', '--value'], capture_output=True, text=True, timeout=.5)
        if result.returncode == 0 and result.stdout.strip().isdigit():
            main = int(result.stdout.strip())
            if main > 0: allowed.update(descendants(main))
    except (OSError, subprocess.SubprocessError):
        pass
    return {candidate for candidate in allowed if is_kwin(candidate)}


def is_kwin(pid):
    # KWin disables dumpability; /proc/<pid>/exe may be unreadable even to
    # this UID. comm is readable and is checked only inside the fixed service
    # or wrapper process tree, never as a global same-UID discovery rule.
    try: return Path(f'/proc/{pid}/comm').read_text().strip() in ('kwin_wayland', 'kwin_wayland_wr')
    except OSError: return False


def supervise(pid, timeout=25):
    """No restart. Timeout includes socket discovery and the whole visible life."""
    ui = None
    started = time.monotonic()
    event('SocketDiscoveryStarted')
    listening = set()
    def peer(path):
        if path not in listening:
            listening.add(path); event('SocketPeerMatched')
    try:
        while time.monotonic() - started < timeout:
            if not Path(f'/proc/{pid}').exists(): event('SessionEnded'); return
            allowed = compositor_pids(pid)
            for path in Path(os.environ['XDG_RUNTIME_DIR']).glob('wayland-*'):
                if connectable(path, allowed, lambda: peer(path)):
                    event('SocketConnected')
                    env = dict(os.environ, WAYLAND_DISPLAY=path.name)
                    env.pop('DISPLAY', None); env.pop('GREETD_SOCK', None)
                    ui = subprocess.Popen(['/usr/bin/qs', '--no-duplicate', '-p', str(APP / 'cover.qml')], env=env, start_new_session=True, restore_signals=False)
                    break
            if ui is not None: break
            time.sleep(.05)
        if ui is None: event('SocketTimeout'); return
        while time.monotonic() - started < timeout:
            if ui.poll() is not None: event('Exited'); return
            if not Path(f'/proc/{pid}').exists(): event('SessionEnded'); return
            time.sleep(.05)
        event('Deadline')
    finally:
        if ui is not None and ui.poll() is None:
            try: os.killpg(ui.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            try: ui.wait(timeout=1)
            except subprocess.TimeoutExpired:
                try: os.killpg(ui.pid, signal.SIGKILL)
                except ProcessLookupError: pass
                ui.wait()


def feed():
    root = APP / 'public-display' if APP == Path('/run/kos-greeter-test/app') else PUBLIC_ROOT
    diagnostic('KOS_COVER FeedReferenceStarting ' + str(time.monotonic_ns()), error=True)
    desc = read_reference(os.environ.get('XDG_RUNTIME_DIR', ''), os.environ.get('KOS_HANDOFF_SESSION'), os.environ.get('KOS_HANDOFF_SHA256'), root)
    diagnostic('KOS_COVER FeedReferenceReady ' + str(time.monotonic_ns()), error=True)
    first = True
    while True:
        state, desc = resource_state(desc, root)
        if first:
            diagnostic('KOS_COVER FeedInitialStateReady ' + str(time.monotonic_ns()), error=True)
            first = False
        state['session'] = os.environ.get('KOS_HANDOFF_SESSION', '')
        state['hash'] = desc['resource']['sha256'] if desc else ''
        print(json.dumps(state, separators=(',', ':')), flush=True)
        time.sleep(.5)


def resource_state(desc, root=PUBLIC_ROOT, owner=0):
    # Invalid/replaced descriptions latch the fixed fallback for this cover.
    state = dict(source='', fit='crop', version='default')
    if desc and desc['resource']['version'] != 'default':
        try:
            validate(desc, desc['sessionId'], os.geteuid(), root, owner)
            manifest, images = Reader(root, owner).consume(os.geteuid())
            # Revalidate the bytes actually emitted, not an earlier read.
            import hashlib
            if manifest['version'] != desc['resource']['version'] or manifest['fit'] != desc['wallpaper']['fit'] or hashlib.sha256(images['wallpaper']).hexdigest() != desc['resource']['sha256']:
                raise ValueError('changed')
            state = dict(source='data:image/png;base64,' + base64.b64encode(images['wallpaper']).decode(), fit=manifest['fit'], version=manifest['version'])
        except (OSError, ValueError, TypeError, KeyError):
            desc = None
    return state, desc


if __name__ == '__main__':
    if sys.argv[1:] == ['--feed']: feed()
    elif len(sys.argv) == 3 and sys.argv[1] == '--supervise' and sys.argv[2].isdigit():
        def stop(*_): raise SystemExit(0)
        signal.signal(signal.SIGTERM, stop); signal.signal(signal.SIGINT, stop); signal.signal(signal.SIGHUP, stop)
        supervise(int(sys.argv[2]))
    else: sys.exit(2)
