#!/usr/bin/env python3
"""Exercise real QML surfaces; a fake platform records clipboard operations.

No request reaches the real clipboard, input daemon or desktop files. Requires
a running Wayland compositor, Quickshell and the QtTest QML module.
"""
import json
import os
from pathlib import Path
import re
import shutil
import socketserver
import subprocess
import tempfile
import threading

REPO = Path(__file__).resolve().parents[2]
requests = []


class Platform(socketserver.StreamRequestHandler):
    def handle(self):
        lock = threading.Lock()

        def respond(request, ok=True):
            operation = request["operation"]
            result = {"exists": False} if operation == "state.read" else {}
            response = {"version": 1, "requestId": request["requestId"], "ok": ok, "result": result}
            try:
                with lock:
                    self.wfile.write((json.dumps(response) + "\n").encode())
                    self.wfile.flush()
            except (OSError, ValueError):
                pass  # The test process may already have exited.

        try:
            for line in self.rfile:
                request = json.loads(line)
                requests.append(request)
                if request["operation"] == "clipboard.history.copy" and request["payload"].get("record") == "delayed-copy":
                    threading.Timer(0.18, respond, args=(request, False)).start()
                else:
                    respond(request)
        except ConnectionResetError:
            pass


class Server(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True


def run():
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    wayland = os.environ.get("WAYLAND_DISPLAY", "wayland-0")
    with tempfile.TemporaryDirectory(prefix="kos-interaction-test-") as directory:
        root = Path(directory)
        for name in ["config", "state", "runtime"]:
            (root / name).mkdir(mode=0o700)
        (root / "runtime" / wayland).symlink_to(runtime / wayland)
        for name in ["desktop", "Kos"]:
            (root / name).symlink_to(REPO / "shell" / name, target_is_directory=True)
        shutil.copy(Path(__file__).with_name("shell.qml"), root / "shell.qml")
        with Server(str(root / "platform.sock"), Platform) as server:
            threading.Thread(target=server.serve_forever, daemon=True).start()
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / "config"),
                       XDG_STATE_HOME=str(root / "state"), XDG_RUNTIME_DIR=str(root / "runtime"),
                       KOS_PLATFORM_SOCKET=str(root / "platform.sock"),
                       KOS_DATA_SOCKET=str(root / "no-data.sock"), QT_QPA_PLATFORM="wayland")
            for restart in ["0", "1"]:
                result = subprocess.run(["quickshell", "--path", str(root), "--no-color"],
                                        env=dict(env, LAYOUT_RESTART=restart),
                                        capture_output=True, text=True, timeout=25)
                output = result.stdout + result.stderr
                assert result.returncode == 0 and "INTERACTION_RUNTIME_PASS" in output, output
                assert not re.search(r"INTERACTION_RUNTIME_FAIL|ReferenceError|TypeError|Cannot assign|Unable to assign|is not a type|Duplicate signal", output), output
            pastes = 0
            checkpoints = {}
            for request in requests:
                if request["operation"] == "input.paste":
                    pastes += 1
                    assert request["payload"]["expectedWindowId"] == "{11111111-1111-1111-1111-111111111111}"
                if request["operation"] == "test.checkpoint":
                    checkpoints[request["payload"]["name"]] = pastes
            assert checkpoints == {"different-window": 0, "timeout": 0, "closed-target": 0,
                                   "missing-target": 0, "matched-target": 1, "stale-copy": 1}, checkpoints
            assert not any(r["operation"] == "clipboard.history.delete" for r in requests)
            server.shutdown()
            print("PASS: Dock/Bar boot, reversal and geometry; popup lifetime; search text editing; guarded paste; desktop refresh, rename and restart")


if __name__ == "__main__":
    run()
