#!/usr/bin/env python3
"""Exercise the built Stage overlay in an isolated virtual KWin/private bus."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument("plugin", type=Path)
parser.add_argument("--quickshell", default="quickshell")
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--inside", action="store_true")
args = parser.parse_args()
if not args.inside:
    # No activation directories: the fixture must not start portals, keyrings
    # or other desktop helpers inherited from the workstation's D-Bus catalog.
    with tempfile.TemporaryDirectory(prefix="kos-stage-bus-") as directory:
        config = Path(directory) / "bus.conf"
        config.write_text('''<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>
            <auth>EXTERNAL</auth><policy context="default"><allow own="*"/>
            <allow send_destination="*"/><allow receive_sender="*"/></policy></busconfig>''')
        subprocess.run(["dbus-run-session", f"--config-file={config}", "--", sys.executable,
                        str(Path(__file__).resolve()), *sys.argv[1:], "--inside"],
                       check=True, timeout=35)
    sys.exit(0)

args.output.mkdir(parents=True, exist_ok=True)
log_path = args.output / "compositor.log"
with tempfile.TemporaryDirectory(prefix="kos-stage-static-") as directory:
    stage = Path(directory)
    config, runtime, state = [stage / name for name in ("config", "runtime", "state")]
    for path in (config, runtime, state):
        path.mkdir(mode=0o700)
    plugins = stage / "plugins/kwin/effects/plugins"
    plugins.mkdir(parents=True)
    shutil.copy2(args.plugin, plugins / "stageanim13.so")
    (config / "kwinrc").write_text("""[Plugins]
stageanim13Enabled=true
slideEnabled=true
glassEnabled=false
blurEnabled=false
scaleEnabled=false
squashEnabled=false
fadingpopupsEnabled=false
slidingpopupsEnabled=false
[Desktops]
Number=2
Rows=1
Id_1=11111111-1111-4111-8111-111111111111
Id_2=22222222-2222-4222-8222-222222222222
[Effect-slide]
Duration=700
""")
    env = {**os.environ, "XDG_CONFIG_HOME": str(config), "XDG_STATE_HOME": str(state),
           "XDG_RUNTIME_DIR": str(runtime), "QT_PLUGIN_PATH": str(stage / "plugins"),
           "LIBGL_ALWAYS_SOFTWARE": "1", "QT_FORCE_STDERR_LOGGING": "1",
           "QS_DISABLE_FILE_WATCHER": "1"}
    for name in ("DISPLAY", "WAYLAND_DISPLAY", "QT_QPA_PLATFORM"):
        env.pop(name, None)
    processes = []

    def call(*arguments):
        return subprocess.check_output(["qdbus6", *arguments], env=env, text=True,
                                       stderr=subprocess.DEVNULL, timeout=2).strip()

    def until(predicate, timeout=8):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                result = predicate()
                if result:
                    return result
            except (subprocess.SubprocessError, ValueError, KeyError, IndexError):
                pass
            time.sleep(.035)
        raise AssertionError(f"Timed out; see {log_path}")

    def debug():
        text = call("org.kde.KWin", "/Effects", "org.kde.kwin.Effects.debug",
                    "stageanim13", "live-cards")
        return json.loads(text[text.index("{"):])

    live_path = state / "quickshell/kos/fg-sched/stage-live.json"
    live_path.parent.mkdir(parents=True)
    live_path.write_text('{"cards":[]}')
    with log_path.open("w") as output:
        try:
            compositor = subprocess.Popen(["kwin_wayland", "--virtual", "--width", "960",
                "--height", "640", "--socket", "stage-static", "--no-lockscreen",
                "--no-global-shortcuts", "--no-kactivities"], env=env,
                stdout=output, stderr=subprocess.STDOUT)
            processes.append(compositor)
            until(lambda: call("org.kde.KWin", "/Effects", "org.kde.kwin.Effects.isEffectLoaded",
                               "stageanim13") == "true")
            debug() # A system plugin accidentally loaded instead has no such diagnostics.
            script = stage / "probe.js"
            script.write_text('''function capture(w) {
                if (w.caption.indexOf("Stage static test") < 0) return;
                print("STAGE_STATIC_WINDOW " + w.internalId);
                w.minimized = true;
            }
            workspace.windowAdded.connect(capture);
            workspace.windowList().forEach(capture);
            ''')
            script_id = call("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript",
                             str(script), "stage-static-test")
            call("org.kde.KWin", f"/Scripting/Script{script_id}", "run")
            fixture = stage / "shell.qml"
            fixture.write_text('''import QtQuick
                import Quickshell
                ShellRoot { Window { visible: true; width: 640; height: 480
                    title: "Stage static test"; color: "#ff3355" } }
                ''')
            client_env = {**env, "WAYLAND_DISPLAY": "stage-static", "QT_QPA_PLATFORM": "wayland"}
            client = subprocess.Popen([args.quickshell, "-p", str(fixture), "--no-color"],
                env=client_env, stdout=output, stderr=subprocess.STDOUT)
            processes.append(client)

            def window_id():
                match = re.search(r"STAGE_STATIC_WINDOW .*?([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})",
                                  log_path.read_text(errors="replace"))
                return match.group(1) if match else None

            win_id = until(window_id)
            manager = ["org.kde.KWin", "/VirtualDesktopManager",
                       "org.kde.KWin.VirtualDesktopManager.current"]
            original = call(*manager)

            def publish(desktop, card_id):
                body = {"at": time.time() * 1000, "desktopId": desktop, "cards": [{
                    "id": card_id, "winId": win_id, "x": 48, "y": 100, "w": 180, "h": 140,
                    "angle": 0, "focal": 1100, "radius": 12, "fade": 1,
                    "enterInstant": True, "hoverScale": 1, "cardOpacity": 1}]}
                temporary = live_path.with_suffix(".tmp")
                temporary.write_text(json.dumps(body))
                temporary.replace(live_path)

            publish(original, "original")
            until(lambda: debug()["cards"] and debug()["cards"][0]["paintCount"] > 3)
            until(lambda: debug()["cards"][0]["alpha"] == 1)
            call(*manager, "22222222-2222-4222-8222-222222222222")
            frames = []
            started = time.monotonic()
            while time.monotonic() - started < 1.8:
                snapshot = debug()
                snapshot["ms"] = round((time.monotonic() - started) * 1000)
                frames.append(snapshot)
                time.sleep(.025)
            (args.output / "frames.json").write_text(json.dumps(frames, indent=2))
            during = [frame for frame in frames if frame["fullscreenEffect"]]
            assert len(during) > 3, "Desktop effect did not run"
            assert all(frame["paintAllowed"] for frame in during)
            assert all(frame["cards"][0]["x"] == 48 and frame["cards"][0]["y"] == 100
                       and frame["cards"][0]["alpha"] == 1 and frame["cards"][0]["fade"] == 1
                       for frame in during), "Cards moved or faded during desktop switch"
            assert during[-1]["cards"][0]["paintCount"] > during[0]["cards"][0]["paintCount"] + 3, \
                "Live-card painting stopped during desktop switch"
            publish("22222222-2222-4222-8222-222222222222", "destination")
            updated = until(lambda: (snapshot := debug())["cards"]
                and snapshot["cards"][0]["id"] == "destination" and snapshot)
            assert len(updated["cards"]) == 1 and updated["cards"][0]["alpha"] == 1, \
                "Desktop commit left ghost cards or faded the replacement"
            print(f"PASS: {len(during)} desktop-switch samples kept fixed opaque cards; "
                  "paint count advanced; model replacement was immediate")
        finally:
            for process in reversed(processes):
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=4)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=2)
