#!/usr/bin/env python3
"""file.create-desktop-shortcut links an installed entry into the desktop.

Registered by platform/CMakeLists.txt as the "kos-platform.desktop-shortcut"
test. Like the file-copy fixture it starts the freshly built daemon under a
private session bus and a private XDG environment, so it needs nothing from
the machine beyond dbus-run-session and a Python interpreter.

The contract under test:

  * only an installed desktop id is accepted, never a caller path or content,
  * a missing shortcut becomes a symbolic link named after the entry,
  * repeating the request leaves the existing link in place and reports
    created:false,
  * rename, move and trash operate on the link itself and leave the installed
    entry intact,
  * an existing regular file is never replaced,
  * invalid ids, unknown entries, non-application entries and hidden entries
    are rejected,
  * a missing desktop directory is reported instead of being created.
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

ENTRY_ID = "org.kos.DesktopShortcutTest.desktop"


def fail(message, output=""):
    if output:
        print(output.rstrip())
    print("FAIL: " + message)
    sys.exit(1)


def group_pids(pgid):
    """Live process ids still in the daemon's session, zombies excluded."""
    live = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open("/proc/" + entry + "/stat", "rb") as handle:
                fields = handle.read().rsplit(b")", 1)[1].split()
        except (OSError, IndexError):
            continue
        if len(fields) >= 3 and fields[0] != b"Z" \
                and fields[2] == str(pgid).encode():
            live.append(int(entry))
    return live


def stop_daemon(proc, output=""):
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
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    if proc.poll() is None:
        proc.wait()


def start_daemon(binary, env):
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


def shortcut(sock_path, tag, desktop_id, extra=None):
    payload = {"desktopId": desktop_id}
    if extra:
        payload.update(extra)
    return request(sock_path, tag, "file.create-desktop-shortcut", payload)


def expect_error(response, tag, code):
    if response.get("ok") or response.get("error", {}).get("code") != code:
        fail(tag + ": expected " + code + ", got " + str(response))


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(data)


def read(path):
    with open(path, "rb") as handle:
        return handle.read()


def write_entry(directory, name, entry_type="Application"):
    write(os.path.join(directory, name),
          ("[Desktop Entry]\n"
           "Type=" + entry_type + "\n"
           "Name=Desktop Shortcut Test\n"
           "Exec=/bin/true\n"
           "Icon=application-x-executable\n").encode())


def main():
    if len(sys.argv) != 2:
        print("usage: test_desktop_shortcut.py <kos-platform-binary>")
        return 1

    binary = os.path.abspath(sys.argv[1])
    root = tempfile.mkdtemp(prefix="ksd-")
    runtime = os.path.join(root, "run")
    os.makedirs(runtime)
    sock_path = os.path.join(runtime, "kos-platform.sock")
    if len(sock_path.encode()) >= 100:
        shutil.rmtree(root, ignore_errors=True)
        print("FAIL: scratch path too long for a Unix socket: " + sock_path)
        return 1

    home = os.path.join(root, "home")
    config = os.path.join(root, "config")
    data = os.path.join(root, "data")
    system_data = os.path.join(root, "system-data")
    cache = os.path.join(root, "cache")
    desktop = os.path.join(home, "Desktop")
    applications = os.path.join(data, "applications")
    for directory in (home, config, applications, system_data, cache, desktop):
        os.makedirs(directory, exist_ok=True)

    # QStandardPaths::DesktopLocation reads user-dirs.dirs; use an absolute
    # path so the test does not depend on variable expansion.
    write(os.path.join(config, "user-dirs.dirs"),
          ('XDG_DESKTOP_DIR="' + desktop + '"\n').encode())

    source_path = os.path.join(applications, ENTRY_ID)
    write_entry(applications, ENTRY_ID)
    dest_path = os.path.join(desktop, ENTRY_ID)

    env = dict(os.environ,
               HOME=home,
               XDG_RUNTIME_DIR=runtime,
               XDG_CONFIG_HOME=config,
               XDG_CACHE_HOME=cache,
               XDG_DATA_HOME=data,
               XDG_DATA_DIRS=system_data,
               QT_QPA_PLATFORM="offscreen",
               QT_QUICK_BACKEND="software")

    # Best effort: make KService's primary path index the fixture. The daemon
    # also falls back to the XDG application directories, so a missing
    # kbuildsycoca6 does not turn this test into a false skip.
    sycoca = shutil.which("kbuildsycoca6")
    if sycoca:
        try:
            subprocess.run([sycoca, "--noincremental"], env=env, cwd=root,
                           stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=30)
        except (OSError, subprocess.TimeoutExpired):
            pass

    proc, output, ready = start_daemon(binary, env)
    try:
        if not ready:
            fail("daemon never reported READY", output)

        # 1. A missing shortcut becomes a link named after the entry.
        response = shortcut(sock_path, "create", ENTRY_ID)
        if not response.get("ok"):
            fail("create: expected success, got " + str(response))
        result = response.get("result", {})
        if result.get("created") is not True:
            fail("create: expected created:true, got " + str(response))
        if result.get("path") != dest_path:
            fail("create: wrong destination " + str(result.get("path")))
        if not os.path.islink(dest_path):
            fail("create: destination is not a symbolic link")
        if os.path.realpath(os.readlink(dest_path)) != os.path.realpath(source_path):
            fail("create: link target is " + os.readlink(dest_path))

        # 2. Repeating the request is idempotent and leaves the link alone.
        response = shortcut(sock_path, "repeat", ENTRY_ID)
        if not response.get("ok") or response.get("result", {}).get("created") is not False:
            fail("repeat: expected ok with created:false, got " + str(response))
        if not os.path.islink(dest_path) \
                or os.path.realpath(os.readlink(dest_path)) != os.path.realpath(source_path):
            fail("repeat: the existing link changed")

        # 3. Caller paths are ignored: only desktopId routes the operation.
        os.unlink(dest_path)
        evil = os.path.join(root, "caller-supplied.desktop")
        response = shortcut(sock_path, "caller-path", ENTRY_ID,
                            {"source": "/etc/passwd", "destination": evil,
                             "path": evil, "desktopFile": evil})
        if not response.get("ok") or response.get("result", {}).get("created") is not True:
            fail("caller-path: expected a normal creation, got " + str(response))
        if os.path.lexists(evil):
            fail("caller-path: a caller-supplied destination was written")
        if not os.path.islink(dest_path):
            fail("caller-path: the normal destination was not created")

        # 3b. Rename and move act on the shortcut entry, not its target.
        renamed = os.path.join(desktop, "RenamedShortcut.desktop")
        response = request(sock_path, "rename-link", "file.rename",
                           {"source": dest_path, "target": renamed})
        if not response.get("ok"):
            fail("rename-link: expected success, got " + str(response))
        if os.path.lexists(dest_path) or not os.path.islink(renamed):
            fail("rename-link: the shortcut link was not renamed")
        if not os.path.isfile(source_path):
            fail("rename-link: the installed entry was renamed instead")

        subdir = os.path.join(desktop, "sub")
        response = request(sock_path, "move-link", "file.transfer",
                           {"paths": [renamed], "destination": subdir,
                            "mode": "move"})
        if not response.get("ok"):
            fail("move-link: expected success, got " + str(response))
        moved = os.path.join(subdir, "RenamedShortcut.desktop")
        if not os.path.islink(moved) or os.path.lexists(renamed):
            fail("move-link: the shortcut link was not moved")
        if not os.path.isfile(source_path):
            fail("move-link: the installed entry was moved instead")

        # 3c. Trash removes the link and leaves the installed entry intact.
        response = request(sock_path, "trash-link", "file.trash",
                           {"paths": [moved]})
        if not response.get("ok"):
            fail("trash-link: expected success, got " + str(response))
        if os.path.lexists(moved):
            fail("trash-link: the shortcut link still exists")
        if not os.path.isfile(source_path):
            fail("trash-link: the installed entry was trashed instead")
        trashed = os.path.join(data, "Trash", "files", "RenamedShortcut.desktop")
        if not os.path.lexists(trashed):
            fail("trash-link: the link was not moved to the trash")

        # 4. An existing regular file is never replaced. Steps 3b and 3c moved
        # the link away, so ask for the shortcut again before replacing it.
        response = shortcut(sock_path, "restore", ENTRY_ID)
        if not response.get("ok"):
            fail("restore: expected success, got " + str(response))
        os.unlink(dest_path)
        write(dest_path, b"user content\n")
        response = shortcut(sock_path, "regular-file", ENTRY_ID)
        if not response.get("ok") or response.get("result", {}).get("created") is not False:
            fail("regular-file: expected ok with created:false, got " + str(response))
        if read(dest_path) != b"user content\n":
            fail("regular-file: the existing file was replaced")

        # 5. Id validation matches application.launch.
        expect_error(shortcut(sock_path, "invalid-id", "../" + ENTRY_ID),
                     "invalid-id", "invalid-desktop-id")

        # 6. An id with no installed entry is not a shortcut.
        expect_error(shortcut(sock_path, "missing-app",
                              "org.kos.NoSuchShortcutTest.desktop"),
                     "missing-app", "application-not-found")

        # 7. A desktop entry that is not an application is not accepted.
        link_id = "org.kos.ShortcutTestLink.desktop"
        write_entry(applications, link_id, entry_type="Link")
        expect_error(shortcut(sock_path, "not-application", link_id),
                     "not-application", "application-not-found")

        # 8. Hidden entries would not appear on the desktop; refuse them.
        hidden_id = ".org.kos.HiddenShortcutTest.desktop"
        write_entry(applications, hidden_id)
        expect_error(shortcut(sock_path, "hidden-entry", hidden_id),
                     "hidden-entry", "invalid-desktop-entry")

        stop_daemon(proc, output)

        # 9. A missing desktop directory is reported, not created.
        os.rename(desktop, desktop + ".moved")
        proc, output, ready = start_daemon(binary, env)
        if not ready:
            fail("daemon never reported READY after restart", output)
        expect_error(shortcut(sock_path, "no-desktop", ENTRY_ID),
                     "no-desktop", "desktop-directory-unavailable")
        if os.path.exists(desktop):
            fail("no-desktop: the desktop directory was created")
        stop_daemon(proc, output)
    finally:
        if group_pids(proc.pid):
            kill_daemon(proc)
        shutil.rmtree(root, ignore_errors=True)

    print("PASS: desktop shortcuts link installed entries, stay bounded and "
          "keep file operations on the link")
    return 0


if __name__ == "__main__":
    sys.exit(main())
