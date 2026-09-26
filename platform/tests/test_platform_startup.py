#!/usr/bin/env python3
"""Smoke test: start the kos-platform daemon, talk to it, stop it cleanly.

Registered by platform/CMakeLists.txt as the "kos-platform.startup" test. It
runs the freshly built binary on a private session bus, so beyond
dbus-run-session and a Python interpreter it needs nothing from the machine.
"""
import json
import os
import selectors
import shutil
import socket
import subprocess
import sys
import tempfile
import time


def fail(message, output=""):
    if output:
        print(output.rstrip())
    print("FAIL: " + message)
    sys.exit(1)


def main():
    if len(sys.argv) != 2:
        print("usage: test_platform_startup.py <kos-platform-binary>")
        return 1

    binary = os.path.abspath(sys.argv[1])
    runtime = tempfile.mkdtemp(prefix="p-")
    sock_path = os.path.join(runtime, "kos-platform.sock")

    # A Unix socket path is capped at ~108 bytes; a deep scratch directory
    # makes the daemon fail with QLocalServer "Name error" before READY.
    if len(sock_path.encode()) >= 100:
        shutil.rmtree(runtime, ignore_errors=True)
        print("FAIL: scratch path too long for a Unix socket: " + sock_path)
        return 1

    env = dict(os.environ,
               QT_QPA_PLATFORM="offscreen",
               QT_QUICK_BACKEND="software",
               XDG_RUNTIME_DIR=runtime)

    proc = subprocess.Popen(["dbus-run-session", "--", binary, "daemon"],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, env=env)
    try:
        output = ""
        deadline = time.monotonic() + 15
        sel = selectors.DefaultSelector()
        sel.register(proc.stdout, selectors.EVENT_READ)
        ready = False
        while time.monotonic() < deadline and not ready:
            for key, _ in sel.select(timeout=1):
                line = key.fileobj.readline()
                if line == "":
                    break
                output += line
                if "READY" in line:
                    ready = True
                    break
            if proc.poll() is not None and not ready:
                break
        sel.close()

        if not ready:
            fail("daemon never reported READY", output)

        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        for _ in range(50):
            try:
                client.connect(sock_path)
                break
            except OSError:
                time.sleep(0.1)
        else:
            fail("could not connect to " + sock_path, output)

        client.sendall(b'{"version":1,"requestId":"1",'
                       b'"operation":"platform.ping","payload":{}}\n')
        client.settimeout(10)
        buf = b""
        while b"\n" not in buf:
            chunk = client.recv(4096)
            if not chunk:
                break
            buf += chunk
        client.close()
        if b"\n" not in buf:
            fail("no newline-terminated reply from platform.ping", output)

        reply = json.loads(buf.decode().splitlines()[0])
        for key, value in (("version", 1), ("requestId", "1"), ("ok", True)):
            if reply.get(key) != value:
                fail("unexpected platform.ping reply: " + buf.decode().strip(),
                     output)
        if reply.get("result", {}).get("ready") is not True:
            fail("platform.ping did not report ready: " + buf.decode().strip(),
                 output)

        # A missing target must fail before contacting KWin; a valid target on
        # this private bus must also fail safely (there is no injection effect).
        for payload, code in [({}, "invalid-paste-target"),
                              ({"expectedWindowId": "not-a-window"}, "invalid-paste-target"),
                              ({"expectedWindowId": "11111111-1111-1111-1111-111111111111"},
                               "input-bridge-unavailable")]:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as paste_client:
                paste_client.settimeout(10)
                paste_client.connect(sock_path)
                paste_client.sendall((json.dumps({"version": 1, "requestId": "paste",
                    "operation": "input.paste", "payload": payload}) + "\n").encode())
                with paste_client.makefile("rb") as stream:
                    response = json.loads(stream.readline())
                if response.get("ok") or response.get("error", {}).get("code") != code:
                    fail("unguarded paste request did not fail safely: " + str(response), output)

        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            fail("daemon ignored SIGTERM", output)
        if proc.returncode not in (0, -15):
            fail("daemon exited with " + str(proc.returncode), output)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        shutil.rmtree(runtime, ignore_errors=True)

    print("PASS: kos-platform started, answered platform.ping and stopped cleanly")
    return 0


if __name__ == "__main__":
    sys.exit(main())
