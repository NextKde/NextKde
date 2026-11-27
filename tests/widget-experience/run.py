#!/usr/bin/env python3
"""Real Quickshell input/rendering tests, with persistence confined to a fixture.

Uses a private Wayland compositor in CI, or an existing session by default.
Requires QtTest. The fake platform only serves state and widget package
snapshots: appearance requests never reach the user's compositor or daemon.
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

REPO = Path(__file__).resolve().parents[2]
state = {
    "appearance/config.json": json.dumps({"version": 28, "shellStyle": "macos", "useSystemFont": False}),
    "appearance/icon-appearance.json": json.dumps({"version": 1, "mode": "grayscale"}),
}


def build_widget_packages():
    """Mirror WidgetPackageIndex's widget-package.snapshot payload from REPO/widgets."""
    packages = []
    widgets_dir = REPO / "widgets"
    if not widgets_dir.is_dir():
        return packages
    for pkg_dir in sorted(widgets_dir.iterdir()):
        meta_path = pkg_dir / "metadata.json"
        if not meta_path.is_file():
            continue
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        variants = meta.get("widgets")
        if isinstance(variants, list) and variants:
            for variant in variants:
                widget_rel = variant.get("widgetEntry", "Widget.qml")
                snap_rel = variant.get("snapshotEntry", meta.get("snapshotEntry", "Snapshot.qml"))
                settings_rel = variant.get("settingsEntry", meta.get("settingsEntry", ""))
                popup_rel = variant.get("popupEntry", meta.get("popupEntry", ""))
                merged_i18n = {}
                for locale, block in (meta.get("i18n") or {}).items():
                    if isinstance(block, dict):
                        merged_i18n[locale] = dict(block)
                for locale, block in (variant.get("i18n") or {}).items():
                    if isinstance(block, dict):
                        merged_i18n.setdefault(locale, {}).update(block)
                entry = {
                    "id": variant["id"],
                    "packageId": meta["id"],
                    "packageName": meta.get("name", meta["id"]),
                    "name": variant.get("name", meta.get("name", variant["id"])),
                    "description": variant.get("description", meta.get("description", "")),
                    "category": variant.get("category", meta.get("category", "other")),
                    "categoryName": variant.get("categoryName", meta.get("categoryName", "")),
                    "style": variant.get("style", meta.get("style", "")),
                    "source": "default",
                    "version": meta.get("version", "1.0.0"),
                    "minApiRevision": meta.get("minApiRevision", 1),
                    "containers": variant.get("containers", meta.get("containers", ["desktop"])),
                    "sizes": variant.get("sizes", meta.get("sizes", [[1, 1]])),
                    "defaultSize": variant.get("defaultSize", meta.get("defaultSize", [1, 1])),
                    "dockUnits": variant.get("dockUnits", meta.get("dockUnits", 2)),
                    "available": True,
                    "rootPath": str(pkg_dir.resolve()),
                    "widgetEntry": str((pkg_dir / widget_rel).resolve()),
                    "snapshotEntry": str((pkg_dir / snap_rel).resolve()),
                    "revision": "fixture-1",
                    "hasSettings": bool(settings_rel),
                    "hasPopup": bool(popup_rel),
                    "i18n": merged_i18n,
                }
                if settings_rel:
                    entry["settingsEntry"] = str((pkg_dir / settings_rel).resolve())
                if popup_rel:
                    entry["popupEntry"] = str((pkg_dir / popup_rel).resolve())
                packages.append(entry)
        else:
            widget_rel = meta.get("widgetEntry", "Widget.qml")
            snap_rel = meta.get("snapshotEntry", "Snapshot.qml")
            settings_rel = meta.get("settingsEntry", "")
            popup_rel = meta.get("popupEntry", "")
            entry = {
                "id": meta["id"],
                "packageId": meta["id"],
                "packageName": meta.get("name", meta["id"]),
                "name": meta.get("name", meta["id"]),
                "description": meta.get("description", ""),
                "category": meta.get("category", "other"),
                "categoryName": meta.get("categoryName", ""),
                "style": meta.get("style", ""),
                "source": "default",
                "version": meta.get("version", "1.0.0"),
                "minApiRevision": meta.get("minApiRevision", 1),
                "containers": meta.get("containers", ["desktop"]),
                "sizes": meta.get("sizes", [[1, 1]]),
                "defaultSize": meta.get("defaultSize", [1, 1]),
                "dockUnits": meta.get("dockUnits", 2),
                "available": True,
                "rootPath": str(pkg_dir.resolve()),
                "widgetEntry": str((pkg_dir / widget_rel).resolve()),
                "snapshotEntry": str((pkg_dir / snap_rel).resolve()),
                "revision": "fixture-1",
                "hasSettings": bool(settings_rel),
                "hasPopup": bool(popup_rel),
                "i18n": meta.get("i18n", {}),
            }
            if settings_rel:
                entry["settingsEntry"] = str((pkg_dir / settings_rel).resolve())
            if popup_rel:
                entry["popupEntry"] = str((pkg_dir / popup_rel).resolve())
            packages.append(entry)
    return packages


WIDGET_PACKAGES = build_widget_packages()


class Platform(socketserver.StreamRequestHandler):
    def handle(self):
        try:
            for line in self.rfile:
                request = json.loads(line)
                payload = request.get("payload", {})
                key = "/".join(str(payload.get("dir", "")).split("/")[-1:]) + "/" + payload.get("file", "")
                operation = request["operation"]
                if operation == "platform.ping":
                    result = {
                        "capabilities": [
                            "state.read",
                            "state.write",
                            "system.timezone",
                            "widget-package.snapshot",
                        ]
                    }
                elif operation == "widget-package.snapshot":
                    result = {"packages": WIDGET_PACKAGES, "invalidPackages": []}
                elif operation == "state.read":
                    result = {"exists": key in state, "data": state.get(key, "")}
                elif operation == "system.timezone":
                    result = {"timeZone": "Europe/London"}
                elif operation == "state.write":
                    state[key] = payload["data"]
                    result = {}
                else:
                    result = {}
                reply = {"version": 1, "requestId": request["requestId"], "ok": True, "result": result}
                self.wfile.write((json.dumps(reply) + "\n").encode())
                self.wfile.flush()
        except (ConnectionResetError, BrokenPipeError):
            pass


class Server(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True


def run(base_env=None):
    base_env = dict(os.environ if base_env is None else base_env)
    runtime = Path(base_env.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    wayland = base_env.get("WAYLAND_DISPLAY", "wayland-0")
    with tempfile.TemporaryDirectory(prefix="kos-widget-test-") as directory:
        root = Path(directory)
        for name in ["config", "state", "runtime"]:
            (root / name).mkdir(mode=0o700)
        (root / "config/kdeglobals").write_text("[General]\nfont=Inter,10\n")
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
                       # These assertions inspect the legacy blur-region transport.
                       # Keep them stable when the compositor also advertises v8.
                       KOS_SURFACE_SHAPE_MAX_VERSION="7")
            for expected in ["glass", "color"]:
                result = subprocess.run(["quickshell", "--path", str(root), "--no-color"],
                                        env=dict(env, EXPECTED_WIDGET_STYLE=expected),
                                        capture_output=True, text=True, timeout=120)
                output = result.stdout + result.stderr
                qa = Path(base_env["KOS_WIDGET_QA"]) / expected if base_env.get("KOS_WIDGET_QA") else None
                if qa:
                    qa.mkdir(parents=True, exist_ok=True)
                    (qa / "quickshell.log").write_text(output)
                assert result.returncode == 0, output
                assert "WIDGET_EXPERIENCE_PASS" in output, output
                assert not re.search(r"WIDGET_EXPERIENCE_FAIL|ReferenceError|TypeError|Cannot assign|Unable to assign|is not a type", output), output
                saved = json.loads(state["appearance/config.json"])
                assert saved["version"] == 35 and saved["widgetStyle"] == "color", saved
                assert "useSystemFont" not in saved and isinstance(saved["desktopFontFamily"], str) and saved["desktopFontFamily"], saved
                assert json.loads(state["appearance/icon-appearance.json"])["mode"] == "grayscale"
                print(f"PASS: {expected} load, SDK package catalog/add/park/restore, gestures, edit-mode dismissal, 18 appearance combinations, persistence")
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
            QSG_RHI_BACKEND="opengl", LIBGL_ALWAYS_SOFTWARE="1",
            KOS_TEST_KWIN_LOG=str(root / "kwin.log"))
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
