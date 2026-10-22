#!/usr/bin/env python3
"""Real Quickshell input/rendering tests, with persistence confined to a fixture.

Uses a private Wayland compositor in CI, or an existing session by default.
Requires QtTest and Pillow. The fake platform only serves state:
appearance requests never reach the user's compositor or installed daemon.
"""
import json
import os
from pathlib import Path
import re
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
from PIL import Image

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


def check_bell_pixels(directory):
    frames = {}
    for name in ["timer-color", "timer-glass", "timer-restored"]:
        with Image.open(directory / f"{name}.png") as image:
            frame = image.convert("RGBA")
        visible = [pixel for pixel in frame.getdata() if pixel[3] > 32]
        assert len(visible) >= 5, (name, "bell was not rendered")
        expected = (255, 255, 255) if name == "timer-glass" else (255, 176, 40)
        assert all(all(abs(pixel[channel] - expected[channel]) <= 8 for channel in range(3))
                   for pixel in visible), (name, "stale countdown ink", visible[:10])
        frames[name] = frame
    assert frames["timer-color"].tobytes() == frames["timer-restored"].tobytes(), "bell colour did not round-trip"


def run(base_env=None):
    base_env = dict(os.environ if base_env is None else base_env)
    runtime = Path(base_env.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    wayland = base_env.get("WAYLAND_DISPLAY", "wayland-0")
    with tempfile.TemporaryDirectory(prefix="kos-widget-test-") as directory:
        root = Path(directory)
        for name in ["config", "state", "runtime"]:
            (root / name).mkdir(mode=0o700)
        (root / "captures").mkdir()
        (root / "runtime" / wayland).symlink_to(runtime / wayland)
        for name in ["desktop", "Kos", "shared"]:
            (root / name).symlink_to(REPO / "shell" / name, target_is_directory=True)
        shutil.copy(Path(__file__).with_name("shell.qml"), root / "shell.qml")
        with Server(str(root / "platform.sock"), Platform) as server:
            threading.Thread(target=server.serve_forever, daemon=True).start()
            env = dict(base_env, XDG_CONFIG_HOME=str(root / "config"),
                       XDG_STATE_HOME=str(root / "state"), XDG_RUNTIME_DIR=str(root / "runtime"),
                       KOS_PLATFORM_SOCKET=str(root / "platform.sock"),
                       KOS_DATA_SOCKET=str(root / "absent-data.sock"),
                       QT_QPA_PLATFORM="wayland",
                       WIDGET_CAPTURE_DIR=str(root / "captures"),
                       # These assertions inspect the legacy blur-region transport.
                       # Keep them stable when the compositor also advertises v8.
                       KOS_SURFACE_SHAPE_MAX_VERSION="7")
            # First load migrates grayscale -> glass. The second must respect
            # an explicit colour widget style despite those same legacy icons.
            for expected in ["glass", "color"]:
                result = subprocess.run(["quickshell", "--path", str(root), "--no-color"],
                                        env=dict(env, EXPECTED_WIDGET_STYLE=expected),
                                        capture_output=True, text=True, timeout=25)
                output = result.stdout + result.stderr
                qa = Path(base_env["KOS_WIDGET_QA"]) / expected if base_env.get("KOS_WIDGET_QA") else None
                if qa:
                    qa.mkdir(parents=True, exist_ok=True)
                    (qa / "quickshell.log").write_text(output)
                    for capture in (root / "captures").glob("*.png"):
                        shutil.copy(capture, qa / capture.name)
                assert result.returncode == 0, output
                assert "WIDGET_EXPERIENCE_PASS" in output, output
                assert not re.search(r"WIDGET_EXPERIENCE_FAIL|ReferenceError|TypeError|Cannot assign|Unable to assign|is not a type", output), output
                check_bell_pixels(root / "captures")
                saved = json.loads(state["appearance/config.json"])
                assert saved["version"] == 30 and saved["widgetStyle"] == "color", saved
                assert set(saved["hiddenDeskCenterWidgets"]) == set(WIDGETS) - {"clock"}, saved
                assert json.loads(state["appearance/icon-appearance.json"])["mode"] == "grayscale"
                # Each launch must render its own frames, not reuse the first run.
                for capture in (root / "captures").glob("*.png"):
                    capture.unlink()
                print(f"PASS: {expected} load, empty desktop recovery, gestures, 18 appearance combinations, countdown colour pixels, persistence")
            server.shutdown()


def main():
    if "--private-compositor" not in sys.argv:
        run()
        return
    if "--private-bus" not in sys.argv:
        with tempfile.TemporaryDirectory(prefix="kos-widget-bus-") as directory:
            config = Path(directory) / "bus.conf"
            config.write_text('<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>'
                '<policy context="default"><allow send_destination="*"/>'
                '<allow receive_sender="*"/><allow own="*"/></policy></busconfig>')
            subprocess.run(["dbus-run-session", "--config-file=" + str(config), "--",
                sys.executable, __file__, "--private-compositor", "--private-bus"], check=True)
        return
    with tempfile.TemporaryDirectory(prefix="kos-widget-compositor-") as directory:
        root = Path(directory)
        for name in ["runtime", "config", "state", "cache", "data"]:
            (root / name).mkdir(mode=0o700)
        env = dict(os.environ, XDG_RUNTIME_DIR=str(root / "runtime"),
            XDG_CONFIG_HOME=str(root / "config"), XDG_STATE_HOME=str(root / "state"),
            XDG_CACHE_HOME=str(root / "cache"), XDG_DATA_HOME=str(root / "data"),
            WAYLAND_DISPLAY="widget-experience-test", DISPLAY="",
            QSG_RHI_BACKEND="opengl", LIBGL_ALWAYS_SOFTWARE="1")
        env.pop("QT_QUICK_BACKEND", None)
        with (root / "kwin.log").open("w+") as log:
            compositor = subprocess.Popen(["kwin_wayland", "--virtual", "--width", "1920",
                "--height", "1080", "--no-lockscreen", "--no-global-shortcuts", "--no-kactivities",
                "--socket", env["WAYLAND_DISPLAY"]],
                env=dict(env, QT_QPA_PLATFORM="offscreen", KWIN_COMPOSE="O2"), stdout=log, stderr=log)
            try:
                for _ in range(100):
                    if (root / "runtime" / env["WAYLAND_DISPLAY"]).exists():
                        break
                    if compositor.poll() is not None:
                        log.seek(0)
                        raise AssertionError(log.read())
                    time.sleep(0.05)
                else:
                    raise AssertionError("private compositor did not create its Wayland socket")
                run(env)
            finally:
                compositor.terminate()
                try:
                    compositor.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    compositor.kill()
                    compositor.wait()
                log.seek(0)
                output = log.read()
                if env.get("KOS_WIDGET_QA"):
                    qa = Path(env["KOS_WIDGET_QA"])
                    qa.mkdir(parents=True, exist_ok=True)
                    (qa / "kwin.log").write_text(output)
                print(output, flush=True)


if __name__ == "__main__":
    main()
