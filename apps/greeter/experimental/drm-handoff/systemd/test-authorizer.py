#!/usr/bin/python3 -I
"""Private user/PID namespace test: real resource reader and seqpacket/SCM_RIGHTS."""
import array
import hashlib
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import socket
import sys
import threading

assert os.geteuid() == 0 and not Path('/dev/tty1').exists() and not Path('/run/systemd/private').exists()
loader = importlib.machinery.SourceFileLoader('authorizer', '/tests/kos-handoff-authorize')
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
sys.path.insert(0, '/usr/local/lib/kos-greeter/app/companion')
from resources import Store, NOTICE
from PIL import Image

root = Path('/var/lib/kos/greeter/display')
root.mkdir(parents=True)
image = Path('/tmp/fixture.png')
Image.new('RGB', (8, 6), '#445577').save(image)
image_bytes = image.read_bytes()
store = Store(root)
nonce = 'b' * 32


def exchange(uid, expected_prefix, *, stale=False, fail=False, expected_image=None):
    parent, peer = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    errors = []
    def server():
        try:
            data, controls, flags, _ = peer.recvmsg(128, socket.CMSG_SPACE(4))
            assert data.startswith(expected_prefix)
            assert data.endswith(nonce.encode()) and not flags
            received = []
            for level, kind, payload in controls:
                assert (level, kind) == (socket.SOL_SOCKET, socket.SCM_RIGHTS)
                descriptors = array.array('i'); descriptors.frombytes(payload)
                received.extend(descriptors)
            if expected_image is None:
                assert not received
            else:
                assert len(received) == 1
                fd = received[0]
                try:
                    assert os.fstat(fd).st_uid == 0
                    assert hashlib.sha256(os.pread(fd, 1024 * 1024, 0)).hexdigest() == expected_image
                    try: os.write(fd, b'forbidden')
                    except OSError: pass
                    else: raise AssertionError('received image FD was writable')
                finally:
                    os.close(fd)
            if stale:
                peer.send(b'PRESENTED:' + b'a' * 32)
            peer.send((b'TIMEOUT:' if fail else b'PRESENTED:') + nonce.encode())
        except BaseException as error:
            errors.append(error)
        finally:
            peer.close()
    thread = threading.Thread(target=server)
    thread.start()
    try:
        if fail:
            try: module.arm(parent, uid, nonce)
            except ValueError: pass
            else: raise AssertionError('matching timeout authorized a handoff')
        else:
            module.arm(parent, uid, nonce)
    finally:
        parent.close(); thread.join(4)
    assert not thread.is_alive() and not errors, errors


exchange(1000, b'ARM:default:', stale=True)
print('PASS unpublished UID uses default and ignores stale nonce confirmation')
manifest = store.publish(1000, image_bytes, consent=True, notice=NOTICE)
exchange(1000, b'ARM:cover:1000:', expected_image=manifest['resources']['wallpaper']['sha256'])
print('PASS consented image crosses a real readonly root-owned SCM_RIGHTS FD')
manifest = store.publish(1000, image_bytes, consent=True, notice=NOTICE, fit='fit')
exchange(1000, b'ARM:contain:1000:', stale=True, expected_image=manifest['resources']['wallpaper']['sha256'])
print('PASS fit metadata remains bound to the image and current nonce')
store.revoke(1000)
exchange(1000, b'ARM:default:', fail=True)
print('PASS withdrawal falls back and timeout never authorizes launch')
store.publish(1000, image_bytes, consent=True, notice=NOTICE, ttl=15)
exchange(1000, b'ARM:default:')
print('PASS near-expiry publication cannot be retained through a handoff')
store.publish(1000, image_bytes, consent=True, notice=NOTICE, fit='stretch')
exchange(1000, b'ARM:default:')
print('PASS unsupported fit is explicit default, never mislabelled crop')
print('6 authorizer protocol/resource cases passed; no PAM/display/system-bus access')

# The installed root is authoritative, including withdrawal/missing manifest.
installed = Path('/usr/local/lib/kos-greeter/app/public-display')
installed.mkdir()
store.publish(1000, image_bytes, consent=True, notice=NOTICE)
exchange(1000, b'ARM:default:')
installed_store = Store(installed)
manifest = installed_store.publish(1000, image_bytes, consent=True, notice=NOTICE)
exchange(1000, b'ARM:cover:1000:', expected_image=manifest['resources']['wallpaper']['sha256'])
installed_store.revoke(1000)
exchange(1000, b'ARM:default:')
print('PASS installed root selection never resurrects withdrawn var publication')

# A fake bus and real seqpacket exercise prepare/commit rollback without logind.
original_call = module.call
for response in ('READY', 'EXPIRED', 'STALE', 'EOF', 'prepare-failed'):
    calls = []
    def bus(path, method, signature=None, args=()):
        calls.append(method)
        if response == 'prepare-failed' and method == 'PrepareGreeterHandoff':
            raise ValueError('fake-prepare-failure')
    module.call = bus
    parent, peer = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    def confirm_peer():
        try:
            request = peer.recv(128)
            assert request == ('CONFIRM:' + nonce).encode()
            if response != 'EOF':
                peer.send((response + ':' + (nonce if response != 'STALE' else 'a' * 32)).encode())
        finally: peer.close()
    thread = threading.Thread(target=confirm_peer)
    if response != 'prepare-failed': thread.start()
    try:
        try: module.prepare_and_confirm(parent, '/fake', 42, nonce)
        except (ValueError, OSError): assert response != 'READY'
        else: assert response == 'READY'
    finally:
        parent.close()
        if response != 'prepare-failed': thread.join(2)
        else: peer.close()
    assert calls == (['PrepareGreeterHandoff'] if response in ('READY', 'prepare-failed') else ['PrepareGreeterHandoff', 'CancelGreeterHandoff'])
module.call = original_call
print('PASS prepare failure, expired/stale confirmation and EOF cancel; current READY commits')
print('Final authorizer cases passed; no PAM/display/system-bus access')
