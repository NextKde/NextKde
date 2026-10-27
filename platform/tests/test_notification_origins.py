"""Real private-bus Notify calls must resolve to their actual sender PID."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time


def wait_for(predicate):
    deadline = time.monotonic() + 6
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.02)
    raise AssertionError("timed out")


server_code = """
import dbus, dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib
DBusGMainLoop(set_as_default=True)
class Server(dbus.service.Object):
    @dbus.service.method('org.freedesktop.Notifications', in_signature='susssasa{sv}i', out_signature='u')
    def Notify(self, app, replace, icon, summary, body, actions, hints, timeout): return 1
bus = dbus.SessionBus()
name = dbus.service.BusName('org.freedesktop.Notifications', bus)
server = Server(bus, '/org/freedesktop/Notifications')
print('ready', flush=True)
GLib.MainLoop().run()
"""
sender_code = """
import dbus, time
bus = dbus.SessionBus()
notify = dbus.Interface(bus.get_object('org.freedesktop.Notifications', '/org/freedesktop/Notifications'), 'org.freedesktop.Notifications')
notify.Notify('Konsole', dbus.UInt32(0), '', 'Konsole', '同名 MainThread\\n"引号"', dbus.Array([], signature='s'), dbus.Dictionary({}, signature='sv'), -1)
print('sent', flush=True)
time.sleep(5)
"""
children = []
with tempfile.TemporaryDirectory(prefix='kos-origin-test-') as directory:
    try:
        server = subprocess.Popen([sys.executable, '-u', '-c', server_code], stdout=subprocess.PIPE, text=True)
        children.append(server)
        assert server.stdout.readline().strip() == 'ready'
        path = str(Path(directory) / 'platform.sock')
        daemon = subprocess.Popen([sys.argv[1], 'daemon'], env={**os.environ,
            'QT_QPA_PLATFORM': 'offscreen', 'KOS_PLATFORM_SOCKET': path,
            'KOS_NOTIFICATION_PYTHON': sys.executable}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        children.append(daemon)
        wait_for(lambda: Path(path).exists())
        time.sleep(.3)
        peer = socket.socket(socket.AF_UNIX)
        peer.settimeout(3)
        peer.connect(path)
        stream = peer.makefile('rwb', buffering=0)
        body = '同名 MainThread\n"引号"'
        def request(index, payload):
            stream.write((json.dumps({'version': 1, 'requestId': str(index),
                'operation': 'notification.resolve', 'payload': payload}) + '\n').encode())
        payload = {'appName': 'Konsole', 'summary': 'Konsole', 'body': body}
        for index in range(2):
            # UI lookup arrives first in one case, observer arrives first in the other.
            if index == 0:
                request(index, payload)
            sender = subprocess.Popen([sys.executable, '-u', '-c', sender_code], stdout=subprocess.PIPE, text=True)
            children.append(sender)
            assert sender.stdout.readline().strip() == 'sent'
            if index == 1:
                request(index, payload)
            response = json.loads(stream.readline())
            assert response.get('ok') and response['result']['pid'] == sender.pid, response
        request(3, payload)
        assert json.loads(stream.readline())['result']['pid'] == 0, 'origins must be consumed once'
        request(4, {**payload, 'body': 'x' * 16385})
        assert not json.loads(stream.readline())['ok'], 'oversized metadata must be rejected'
        print('notification origins: two identical Notify payloads, distinct sender PIDs, both arrival orders, one-shot lookup passed')
    finally:
        for child in reversed(children):
            child.terminate()
        for child in reversed(children):
            try: child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
