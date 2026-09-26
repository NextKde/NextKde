#!/usr/bin/env python3
"""Real Quickshell input/rendering tests, with persistence confined to a fixture.

Requires a Wayland session and QtTest. The fake platform only serves state:
appearance requests never reach the user's compositor or installed daemon.
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
WIDGETS = ["clock", "weather", "calendar", "todo", "system", "activity", "music"]
state = {
    "appearance/config.json": json.dumps({"version": 28, "shellStyle": "macos"}),
    "appearance/icon-appearance.json": json.dumps({"version": 1, "mode": "grayscale"}),
}


class Platform(socketserver.StreamRequestHandler):
    def handle(self):
        for line in self.rfile:
            request = json.loads(line)
            payload = request.get("payload", {})
            key = "/".join(str(payload.get("dir", "")).split("/")[-1:]) + "/" + payload.get("file", "")
            operation = request["operation"]
            if operation == "state.read":
                result = {"exists": key in state, "data": state.get(key, "")}
            elif operation == "state.write":
                state[key] = payload["data"]
                result = {}
            else:
                result = {}
            reply = {"version": 1, "requestId": request["requestId"], "ok": True, "result": result}
            self.wfile.write((json.dumps(reply) + "\n").encode())
            self.wfile.flush()


class Server(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True


def run():
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    wayland = os.environ.get("WAYLAND_DISPLAY", "wayland-0")
    with tempfile.TemporaryDirectory(prefix="kos-widget-test-") as directory:
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
                       KOS_DATA_SOCKET=str(root / "absent-data.sock"),
                       QT_QPA_PLATFORM="wayland")
            # First load migrates grayscale -> glass. The second must respect
            # an explicit colour widget style despite those same legacy icons.
            for expected in ["glass", "color"]:
                result = subprocess.run(["quickshell", "--path", str(root), "--no-color"],
                                        env=dict(env, EXPECTED_WIDGET_STYLE=expected),
                                        capture_output=True, text=True, timeout=25)
                output = result.stdout + result.stderr
                assert result.returncode == 0, output
                assert "WIDGET_EXPERIENCE_PASS" in output, output
                assert not re.search(r"WIDGET_EXPERIENCE_FAIL|ReferenceError|TypeError|Cannot assign|Unable to assign|is not a type", output), output
                saved = json.loads(state["appearance/config.json"])
                assert saved["version"] == 29 and saved["widgetStyle"] == "color", saved
                assert set(saved["hiddenDeskCenterWidgets"]) == set(WIDGETS) - {"clock"}, saved
                assert json.loads(state["appearance/icon-appearance.json"])["mode"] == "grayscale"
                print(f"PASS: {expected} load, empty desktop recovery, gestures, 18 appearance combinations, persistence")
            server.shutdown()


if __name__ == "__main__":
    run()
