#!/usr/bin/env python3
"""Capture the real applications with temporary profiles in both UI languages."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--music", action="store_true")
parser.add_argument("--language", action="append", help="Override the default zh_CN/en_US/fr_FR matrix")
parser.add_argument("--view", action="append", help="Capture only these views")
args = parser.parse_args()
REPO = Path(__file__).resolve().parents[2]
OUTPUT = Path(os.environ.get("KOS_LANGUAGE_QA_DIR", str(REPO / ".build/language-qa")))
OUTPUT.mkdir(parents=True, exist_ok=True)
for language in args.language or ["zh_CN", "en_US", "fr_FR"]:
    apps = ["music"] if args.music else ["calendar", "todo", "weather"]
    for app in apps:
        default_views = ["settings", "settings-sources", "settings-accounts", "library/albums"] if args.music else ["main", "small", "settings", "editor"] if app in ["calendar", "todo"] else ["main", "small", "settings"]
        for view in args.view or default_views:
            tag = f"{app}-{language}-{view}".replace("/", "-")
            with tempfile.TemporaryDirectory(prefix="kos-language-") as directory:
                profile = Path(directory)
                env = dict(os.environ, LANG="en_US.UTF-8", LC_ALL="en_US.UTF-8", LANGUAGE=language,
                           XDG_CONFIG_HOME=directory + "/config", XDG_DATA_HOME=directory + "/data",
                           XDG_STATE_HOME=directory + "/state", XDG_CACHE_HOME=directory + "/cache",
                           QT_QPA_PLATFORMTHEME="", QT_NO_XDG_DESKTOP_PORTAL="1",
                           KOS_WEATHER_DISABLE_SERVICE_AUTOSTART="1",
                           KOS_DATA_SOCKET=directory + "/absent-weather.sock",
                           DBUS_SESSION_BUS_ADDRESS="unix:path=" + directory + "/absent-bus")
                if args.music:
                    env.update(QT_QPA_PLATFORM="xcb", LIBGL_ALWAYS_SOFTWARE="1", QSG_RHI_BACKEND="opengl", LISTENFREE_CAPTURE_DELAY="2000")
                    env.pop("QT_QUICK_BACKEND", None)
                    command = [os.environ.get("LISTENFREE_BIN", str(REPO / ".build/language-music/listenfree")), "--data-dir", directory + "/profile", "--capture", str(OUTPUT / (tag + ".png")), "--view", view]
                else:
                    env.update(QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software")
                    command = [str(Path(os.environ["KOS_APP_BIN_DIR"]) / f"kos-{app}") if "KOS_APP_BIN_DIR" in os.environ else str(REPO / f".build/language-apps/apps/{app}/kos-{app}"), "--screenshot", str(OUTPUT / (tag + ".png"))]
                    if view == "settings":
                        command += ["--settings"]
                    if view in ["small", "editor"]:
                        (profile / "qml").mkdir()
                        wrapper = profile / "qml/Capture.qml"
                        editor = ""
                        if view == "editor":
                            component = "EventEditorDialog" if app == "calendar" else "TodoEditorDialog"
                            method = "openForDate(new Date(), 9)" if app == "calendar" else "openNew()"
                            editor = f"App.{component} {{ id: editor }} Timer {{ interval: 80; running: true; onTriggered: editor.{method} }}"
                        wrapper.write_text(f"import QtQuick\nimport Kos.Apps.{app.title()} as App\nApp.Main {{ width: 760; height: 540; {editor} }}\n")
                        command += ["--watch-qml", str(wrapper)]
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=25)
                output = result.stdout + result.stderr
                (OUTPUT / (tag + ".log")).write_text(output)
                assert result.returncode == 0, output
                assert not any(message in output for message in ["ReferenceError:", "TypeError:", "Unable to load KOS translations", "Binding loop"]), output
                print(tag, "PASS", flush=True)
