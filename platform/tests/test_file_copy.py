#!/usr/bin/env python3
"""file.copy must be able to replace a destination that already exists.

Registered by platform/CMakeLists.txt as the "kos-platform.file-copy" test. It
runs the freshly built binary on a private session bus and a private
XDG_RUNTIME_DIR, like the startup smoke test, so it needs nothing from the
machine beyond dbus-run-session and a Python interpreter.

Why this test exists: cleanCreatePath() used to accept only a path whose
deepest existing component was a directory, so a destination that already
existed was rejected with "invalid-path" before any copy happened. Every
publisher of a fixed path therefore worked exactly once. Measured on a running
desktop before the fix: the lock screen weather feed re-publishes the same
LockFeed.qml every five minutes, the copy failed every single time (727
"publish failed: 文件路径无效" lines in one session) and the lock screen kept
showing the weather from the day the theme was installed, while the launcher's
custom-icon import fails on the second import for the same app.

The cases below pin the whole destination-shape contract rather than only the
regression, because the fix widens what that helper accepts and the shapes it
must keep rejecting are the interesting half:

  * a missing destination (with missing parents) is created,
  * an existing regular-file destination is replaced, repeatedly,
  * a file copied onto itself still fails without destroying the source,
  * a missing component *under* an existing file is invalid,
  * an existing symlink is not silently written through,
  * a missing source is invalid,
  * an existing directory is not a file destination.
"""
import json
import os
import selectors
import shutil
import signal
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


def group_pids(pgid):
    """Live process ids still in the daemon's session, zombies excluded.

    A zombie keeps its process group, so killpg(pgid, 0) keeps succeeding long
    after the daemon is gone. In a container whose pid 1 does not reap orphans
    that never clears, and a teardown waiting for it would fail a run the
    daemon left perfectly clean -- which is exactly what the first version of
    this helper did. The state therefore comes from /proc.
    """
    live = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open("/proc/" + entry + "/stat", "rb") as handle:
                fields = handle.read().rsplit(b")", 1)[1].split()
        except (OSError, IndexError):
            continue
        # After the parenthesised command name: state, ppid, pgrp, ...
        if len(fields) >= 3 and fields[0] != b"Z" \
                and fields[2] == str(pgid).encode():
            live.append(int(entry))
    return live


def stop_daemon(proc, output=""):
    """SIGTERM the daemon's whole session and wait for it to be gone.

    dbus-run-session does not forward signals to the process it launches, so
    signalling only the child Popen knows about orphans the resident daemon: it
    keeps running, holding its socket and ~90 MB, until the session ends. The
    Popen is therefore started in its own session and the entire group is
    signalled.
    """
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    if proc.poll() is None:
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            fail("dbus-run-session ignored SIGTERM", output)
    deadline = time.monotonic() + 5
    while group_pids(proc.pid) and time.monotonic() < deadline:
        time.sleep(0.05)
    if group_pids(proc.pid):
        fail("daemon survived SIGTERM", output)


def kill_daemon(proc):
    """Last resort for a daemon that is still running when the test ends."""
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    if proc.poll() is None:
        proc.wait()


def start_daemon(binary, runtime):
    env = dict(os.environ,
               QT_QPA_PLATFORM="offscreen",
               QT_QUICK_BACKEND="software",
               XDG_RUNTIME_DIR=runtime)
    # start_new_session makes this pid the process group stop_daemon() below
    # signals, so nothing dbus-run-session forks outlives the test.
    proc = subprocess.Popen(["dbus-run-session", "--", binary, "daemon"],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, env=env, start_new_session=True)
    sel = selectors.DefaultSelector()
    sel.register(proc.stdout, selectors.EVENT_READ)
    output = ""
    ready = False
    deadline = time.monotonic() + 15
    try:
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
    finally:
        sel.close()
    return proc, output, ready


def connect(sock_path):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(10)
    for _ in range(50):
        try:
            client.connect(sock_path)
            return client
        except OSError:
            time.sleep(0.1)
    client.close()
    return None


def request(sock_path, request_id, operation, payload):
    client = connect(sock_path)
    if client is None:
        fail("could not connect to " + sock_path)
    try:
        client.sendall((json.dumps({"version": 1, "requestId": request_id,
                                    "operation": operation,
                                    "payload": payload}) + "\n").encode())
        with client.makefile("rb") as stream:
            line = stream.readline()
    finally:
        client.close()
    if not line:
        fail(request_id + ": no newline-terminated reply")
    return json.loads(line)


def copy(sock_path, tag, source, destination, expect_error=None):
    response = request(sock_path, tag, "file.copy",
                       {"source": source, "destination": destination})
    if expect_error is None:
        if not response.get("ok"):
            fail(tag + ": expected the copy to succeed: " + str(response))
    else:
        code = response.get("error", {}).get("code")
        if response.get("ok") or code != expect_error:
            fail(tag + ": expected " + expect_error + ", got " + str(response))
    return response


def read(path):
    with open(path, "rb") as handle:
        return handle.read()


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(data)


def main():
    if len(sys.argv) != 2:
        print("usage: test_file_copy.py <kos-platform-binary>")
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

    files = os.path.join(runtime, "files")
    source = os.path.join(files, "source.txt")
    existing = os.path.join(files, "existing.txt")
    directory = os.path.join(files, "adir")
    plain_file = os.path.join(files, "not-a-directory")
    link = os.path.join(files, "link.txt")

    payload = b"source-payload\n"
    replacement = b"replacement-payload\n"

    proc, output, ready = start_daemon(binary, runtime)
    try:
        if not ready:
            fail("daemon never reported READY", output)

        write(source, payload)
        write(existing, b"stale\n")
        write(plain_file, b"not-a-directory\n")
        os.makedirs(directory, exist_ok=True)
        if os.path.lexists(link):
            os.unlink(link)
        os.symlink(existing, link)

        # 1. A destination that does not exist yet -- including its parents --
        #    is still created, which is what every first publish relies on.
        nested = os.path.join(files, "nested", "deep", "out.txt")
        copy(sock_path, "create", source, nested)
        if read(nested) != payload:
            fail("created destination has the wrong contents")

        # 2. The regression: an existing regular file is a valid destination,
        #    and stays valid when it is written again -- the every-five-minutes
        #    shape of the lock screen feed.
        copy(sock_path, "replace-1", source, existing)
        if read(existing) != payload:
            fail("existing destination was not replaced")
        copy(sock_path, "replace-2", source, existing)
        if read(existing) != payload:
            fail("existing destination was not replaced a second time")

        # 3. QSaveFile truncates its destination on open, so copying a file
        #    onto itself must be refused before the write starts.
        copy(sock_path, "self", existing, existing, expect_error="copy-failed")
        if read(existing) != payload:
            fail("copying a file onto itself destroyed the source")

        # 4. An existing file is not a directory: nothing can be created under
        #    it, so the missing final component is still an invalid path.
        copy(sock_path, "under-file", source,
             os.path.join(plain_file, "child.txt"), expect_error="invalid-path")
        if read(plain_file) != b"not-a-directory\n":
            fail("rejected request modified the file it was addressed through")

        # 5. A symlink destination is resolved nowhere and replaced nowhere:
        #    the request is refused and the link target keeps its contents.
        copy(sock_path, "symlink", source, link, expect_error="invalid-path")
        if read(existing) != payload:
            fail("a symlink destination wrote through to its target")

        # 6. A source that does not exist is not a copy.
        copy(sock_path, "missing-source", os.path.join(files, "absent.txt"),
             os.path.join(files, "out.txt"), expect_error="invalid-path")

        # 7. A directory is not a file destination.
        copy(sock_path, "directory", source, directory,
             expect_error="copy-failed")

        stop_daemon(proc, output)
        if proc.returncode not in (0, -15):
            fail("daemon exited with " + str(proc.returncode), output)
    finally:
        if group_pids(proc.pid):
            kill_daemon(proc)
        shutil.rmtree(runtime, ignore_errors=True)

    print("PASS: file.copy creates, replaces and safely refuses every "
          "destination shape")
    return 0


if __name__ == "__main__":
    sys.exit(main())
