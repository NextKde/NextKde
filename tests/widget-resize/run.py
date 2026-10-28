#!/usr/bin/env python3
"""Exercise the real desktop corner grab and restart with isolated settings."""
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import threading

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("widget_fixture", REPO / "tests/widget-experience/run.py")
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
# Reuse the appearance-only fake daemon; no request reaches the user daemon.
fixture.state["appearance/config.json"] = '{"version":29,"shellStyle":"macos","widgetStyle":"glass"}'

def run(base_env=None):
    base_env = dict(os.environ if base_env is None else base_env)
    runtime = Path(base_env.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    wayland = base_env.get("WAYLAND_DISPLAY", "wayland-0")
    with tempfile.TemporaryDirectory(prefix="kos-widget-resize-") as directory:
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
            for restart in ["0", "1"]:
                env = dict(base_env, XDG_CONFIG_HOME=str(root / "config"),
                           XDG_STATE_HOME=str(root / "state"), XDG_RUNTIME_DIR=str(root / "runtime"),
                           KOS_PLATFORM_SOCKET=str(root / "platform.sock"),
                           KOS_DATA_SOCKET=str(root / "absent-data.sock"), QT_QPA_PLATFORM="wayland",
                           VERIFY_WIDGET_RESTART=restart)
                try:
                    result = subprocess.run(["quickshell", "--path", str(root), "--no-color"],
                                            env=env, capture_output=True, text=True, timeout=45)
                except subprocess.TimeoutExpired as error:
                    print((error.stdout or b"").decode(errors="replace"), flush=True)
                    print((error.stderr or b"").decode(errors="replace"), flush=True)
                    raise
                output = result.stdout + result.stderr
                capture_dir = os.environ.get("WIDGET_RESIZE_CAPTURE_DIR")
                if capture_dir:
                    (Path(capture_dir) / f"runtime-{restart}.log").write_text(output)
                assert result.returncode == 0, output
                expected = "WIDGET_RESIZE_RESTART_PASS" if restart == "1" else "WIDGET_RESIZE_PASS"
                assert expected in output, output
                assert not re.search(r"WIDGET_RESIZE_FAIL|ReferenceError|TypeError|Cannot assign|Unable to assign|Binding loop|is not a type", output), output
                print("\n".join(line for line in output.splitlines() if "WIDGET_RESIZE_" in line))
            if os.environ.get("WIDGET_RESIZE_CAPTURE_DIR"):
                from PIL import Image
                for name in ["music", "calendar", "weather"]:
                    for size in ["1x1", "1x2", "2x2", "2x1"]:
                        path = Path(os.environ["WIDGET_RESIZE_CAPTURE_DIR"]) / f"{name}-{size}.png"
                        assert Image.open(path).getbbox(), f"empty capture: {path}"
            server.shutdown()


if __name__ == "__main__":
    # Reuse the existing private KWin/D-Bus lifecycle, with this test as its
    # payload. Importing that fixture never starts its own widget test.
    fixture.run = run
    fixture.__file__ = __file__
    fixture.main()
