#!/usr/bin/env python3
"""Verify real KWin wallpaper selection and desktop shortcut protection in CI/VM."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time

import dbus

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("widget_fixture", REPO / "tests/widget-experience/run.py")
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


def run(base_env):
    bus = dbus.SessionBus()
    scripting = dbus.Interface(bus.get_object("org.kde.KWin", "/Scripting"), "org.kde.kwin.Scripting")
    compositor_log = Path(base_env["KOS_TEST_KWIN_LOG"])
    runtime = Path(base_env["XDG_RUNTIME_DIR"])
    wayland = base_env["WAYLAND_DISPLAY"]
    with tempfile.TemporaryDirectory(prefix="kos-desktop-overview-") as directory:
        root = Path(directory)
        for name in ["config", "state", "runtime"]:
            (root / name).mkdir(mode=0o700)
        (root / "runtime" / wayland).symlink_to(runtime / wayland)
        for name in ["desktop", "Kos"]:
            (root / name).symlink_to(REPO / "shell" / name, target_is_directory=True)
        (root / "shared").symlink_to(REPO / "shared", target_is_directory=True)
        shutil.copy(Path(__file__).with_name("shell.qml"), root / "shell.qml")
        with fixture.Server(str(root / "platform.sock"), fixture.Platform) as server:
            threading.Thread(target=server.serve_forever, daemon=True).start()
            try:
                for order in ["0", "1"]:
                    env = dict(base_env, XDG_CONFIG_HOME=str(root / "config"),
                               XDG_STATE_HOME=str(root / "state"), XDG_RUNTIME_DIR=str(root / "runtime"),
                               KOS_PLATFORM_SOCKET=str(root / "platform.sock"),
                               KOS_DATA_SOCKET=str(root / "absent-data.sock"), QT_QPA_PLATFORM="wayland",
                               DESKTOP_OVERVIEW_WIDGETS_FIRST=order)
                    with (root / "shell.log").open("w+") as log:
                        shell = subprocess.Popen(["quickshell", "--path", str(root), "--no-color"],
                                                 env=env, stdout=log, stderr=log)
                        plugin = "kos-desktop-overview-test-" + order
                        start_offset = compositor_log.stat().st_size
                        try:
                            script_id = scripting.loadDeclarativeScript(
                                str(Path(__file__).with_name("probe.qml")), plugin)
                            assert script_id >= 0, "failed to load native KWin probe"
                            scripting.start()
                            deadline = time.monotonic() + 15
                            while time.monotonic() < deadline:
                                with compositor_log.open() as kwin_log:
                                    kwin_log.seek(start_offset)
                                    output = kwin_log.read()
                                assert "DESKTOP_OVERVIEW_NATIVE_FAIL" not in output, output
                                assert shell.poll() is None, (root / "shell.log").read_text()
                                if "DESKTOP_OVERVIEW_NATIVE_PASS" in output:
                                    break
                                time.sleep(0.1)
                            else:
                                raise AssertionError(output + "\n" + (root / "shell.log").read_text())
                            print(f"PASS: native wallpaper selection, close/move, Show Desktop; widgets-first={order}")
                        finally:
                            scripting.unloadScript(plugin)
                            shell.terminate()
                            try:
                                shell.wait(timeout=3)
                            except subprocess.TimeoutExpired:
                                shell.kill()
                                shell.wait()
            finally:
                server.shutdown()


if __name__ == "__main__":
    if "--private-compositor" not in sys.argv:
        raise SystemExit("This test requires --private-compositor; never target a user's desktop")
    fixture.run = run
    fixture.__file__ = __file__
    fixture.main()
