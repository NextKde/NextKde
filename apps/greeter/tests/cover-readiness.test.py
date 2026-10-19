#!/usr/bin/env python3
"""Production wrapper peer + bounded wire protocol readiness regression."""
import importlib.util
import os
from pathlib import Path
import socket
import struct
import sys
import tempfile
import threading
import time
from unittest.mock import patch, Mock
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'companion'))
import cover

with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp)/'wayland-test'
    server = socket.socket(socket.AF_UNIX); server.bind(str(path)); server.listen()
    try:
        # A listening wrapper whose child has not started is not ready.
        start = time.monotonic()
        assert not cover.connectable(path, {os.getpid()})
        assert time.monotonic()-start < .5
        old, _ = server.accept(); old.close()
        assert not cover.connectable(path, set())
        old, _ = server.accept(); old.close()
        def respond():
            client, _ = server.accept()
            with client:
                assert client.recv(12) == struct.pack('=III', 1, 12 << 16, 2)
                # Both split packets and wl_display.delete_id are legal.
                answer = struct.pack('=III', 1, (12 << 16)|1, 9) + struct.pack('=III', 2, 12 << 16, 1)
                client.sendall(answer[:5]); client.sendall(answer[5:])
        worker = threading.Thread(target=respond); worker.start()
        assert cover.connectable(path, {os.getpid()}); worker.join()
    finally: server.close()

# SO_PEERCRED identifies the socket-creating wrapper, not its KWin child.
with patch.object(cover, 'descendants', side_effect=lambda p: {p,p+1}), \
     patch.object(cover.subprocess, 'run', return_value=Mock(returncode=0,stdout='200\n')), \
     patch.object(cover.Path, 'read_text', side_effect=lambda: ''):
    with patch.object(cover, 'is_kwin', side_effect=lambda p: p in (101,200,201)):
        assert cover.compositor_pids(100) == {101,200,201}
with patch.object(cover.Path, 'read_text', return_value='kwin_wayland_wr\n'):
    assert cover.is_kwin(200)
with patch.object(cover.Path, 'read_text', return_value='other\n'):
    assert not cover.is_kwin(200)
print('PASS trusted wrapper peer, unserviced socket deadline, sync roundtrip, fragmented events, unrelated peer rejection')
