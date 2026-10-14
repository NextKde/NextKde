#!/usr/bin/env python3
"""Render actual widgets against an isolated platform fixture."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("fixture", REPO / "tests/widget-experience/run.py")
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
parser = argparse.ArgumentParser()
parser.add_argument("--size", choices=["small", "medium", "large"], default="")
args = parser.parse_args()
OUTPUT = REPO / ".build/language-qa"
OUTPUT.mkdir(parents=True, exist_ok=True)
for language in ["zh_CN", "en_US", "fr_FR"]:
    with tempfile.TemporaryDirectory(prefix="kos-widget-language-") as directory:
        root = Path(directory)
        for name in ["config", "state", "runtime", "data"]:
            (root / name).mkdir(mode=0o700)
        runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
        wayland = os.environ.get("WAYLAND_DISPLAY", "wayland-0")
        (root / "runtime" / wayland).symlink_to(runtime / wayland)
        for name in ["desktop", "Kos"]:
            (root / name).symlink_to(Path(os.environ.get("KOS_SHELL_DIR", str(REPO / "shell"))) / name, target_is_directory=True)
        (root / "shell.qml").write_text(Path(__file__).with_name("widget-shell.qml").read_text())
        fixture.state.clear()
        fixture.state.update({"appearance/config.json": json.dumps({"version": 29, "shellStyle": "macos", "widgetStyle": "color"}), "appearance/icon-appearance.json": json.dumps({"version": 1, "mode": "color"})})
        with fixture.Server(str(root / "platform.sock"), fixture.Platform) as server:
            threading.Thread(target=server.serve_forever, daemon=True).start()
            env = dict(os.environ, LANG="en_US.UTF-8", LC_ALL="en_US.UTF-8", LANGUAGE=language,
                       XDG_CONFIG_HOME=str(root / "config"), XDG_STATE_HOME=str(root / "state"),
                       XDG_DATA_HOME=str(root / "data"), XDG_RUNTIME_DIR=str(root / "runtime"),
                       KOS_PLATFORM_SOCKET=str(root / "platform.sock"), KOS_DATA_SOCKET=str(root / "absent.sock"),
                       QT_QPA_PLATFORM="wayland", QSG_RENDER_LOOP="basic", QSG_RHI_BACKEND="opengl", LANGUAGE_SCREENSHOT=str(OUTPUT / f"widgets-{language}{'-' + args.size if args.size else ''}.png"))
            env["LANGUAGE_WIDGET_SIZE"] = args.size
            env.pop("QT_QUICK_BACKEND", None)
            try:
                result = subprocess.run([os.environ.get("KOS_QUICKSHELL_BIN", "quickshell"), "--path", str(root), "--no-color"], env=env, capture_output=True, text=True, timeout=20)
            except subprocess.TimeoutExpired as error:
                output = (error.stdout or b"").decode() + (error.stderr or b"").decode()
                (OUTPUT / f"widgets-{language}{'-' + args.size if args.size else ''}.log").write_text(output)
                print(output[-4000:], flush=True)
                raise
            output = result.stdout + result.stderr
            (OUTPUT / f"widgets-{language}{'-' + args.size if args.size else ''}.log").write_text(output)
            print(language, result.returncode, "captured:", "LANGUAGE_CAPTURE true" in output, flush=True)
            assert result.returncode == 0, output
            assert output.count("LANGUAGE_CAPTURE true") == 8, output
            assert not any(error in output for error in ["ReferenceError:", "TypeError:", "Binding loop"]), output
            server.shutdown()
