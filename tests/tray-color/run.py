#!/usr/bin/env python3
"""Render the shipping icon shader and round-trip the tray preference in isolation."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from PIL import Image

REPO = Path(__file__).resolve().parents[2]


def main():
    if "--private-bus" not in sys.argv:
        with tempfile.TemporaryDirectory(prefix="kos-tray-color-bus-") as directory:
            config = Path(directory) / "bus.conf"
            config.write_text('<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>'
                '<policy context="default"><allow send_destination="*"/>'
                '<allow receive_sender="*"/><allow own="*"/></policy></busconfig>')
            subprocess.run(["dbus-run-session", "--config-file=" + str(config), "--",
                sys.executable, __file__, "--private-bus"], check=True)
        return
    with tempfile.TemporaryDirectory(prefix="kos-tray-color-") as directory:
        root = Path(directory)
        (root / "runtime").mkdir(mode=0o700)
        common = root / "desktop/modules/common"
        platform = root / "desktop/modules/platform"
        shutil.copytree(REPO / "shell/desktop", root / "desktop", symlinks=True)
        for name in ["Kos", "shared"]:
            (root / name).symlink_to(REPO / "shell" / name, target_is_directory=True)
        shutil.copy(REPO / "tests/status-area/PlatformFixture.qml", platform / "PlatformClient.qml")
        shutil.copy(Path(__file__).with_name("shell.qml"), root / "shell.qml")
        (common / "IconThemeReloadService.qml").write_text(
            "pragma Singleton\nimport QtQuick\nQtObject { property bool pixmapCacheAllowed: true }\n")
        # Only the transport is stubbed; the real service serializes/reloads its preference.
        (platform / "JsonConfigStore.qml").write_text(
            "pragma Singleton\nimport QtQuick\nQtObject {\n"
            "property var texts: ({})\n"
            "function readPath(path, callback) { callback(\"\", false) }\n"
            "function writePath(path, text) { const next = Object.assign({}, texts); next[path] = text; texts = next }\n}\n")
        icon = Image.new("RGBA", (40, 24))
        for index, color in enumerate([(0, 0, 0, 255), (255, 0, 0, 255),
                (0, 255, 0, 255), (255, 255, 255, 128)]):
            icon.paste(color, (index * 8, 0, index * 8 + 8, 24))
        icon.save(root / "icon.png")
        env = dict(os.environ, QT_QPA_PLATFORM="wayland", QSG_RHI_BACKEND="opengl",
            LIBGL_ALWAYS_SOFTWARE="1", CAPTURE_DIR=str(root), TRAY_TEST_ICON=(root / "icon.png").as_uri(),
            TRAY_SETTINGS_SECTION=(REPO / "apps/settings/pages/IconAppearanceSection.qml").as_uri(),
            XDG_STATE_HOME=str(root / "state"), XDG_CONFIG_HOME=str(root / "config"),
            XDG_CACHE_HOME=str(root / "cache"), XDG_DATA_HOME=str(root / "data"),
            KOS_PLATFORM_SOCKET=str(root / "no-platform.sock"), KOS_DATA_SOCKET=str(root / "no-data.sock"),
            QML_IMPORT_PATH=os.environ.get("QML_IMPORT_PATH", str(REPO / ".build/kosctl/qml")),
            XDG_RUNTIME_DIR=str(root / "runtime"), WAYLAND_DISPLAY="tray-color-test", DISPLAY="")
        env.pop("QT_QUICK_BACKEND", None)
        with (root / "kwin.log").open("w+") as log:
            compositor = subprocess.Popen(["kwin_wayland", "--virtual", "--width", "800",
                "--height", "600", "--no-lockscreen", "--no-global-shortcuts", "--no-kactivities",
                "--socket", "tray-color-test"],
                env=dict(env, QT_QPA_PLATFORM="offscreen", KWIN_COMPOSE="O2"), stdout=log, stderr=log)
            try:
                for _ in range(100):
                    if (root / "runtime/tray-color-test").exists():
                        break
                    if compositor.poll() is not None:
                        log.seek(0)
                        raise AssertionError(log.read())
                    time.sleep(0.05)
                result = subprocess.run(["quickshell", "-p", str(root), "--no-color"],
                    env=env, capture_output=True, text=True, timeout=15)
            finally:
                compositor.terminate()
                try:
                    compositor.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    compositor.kill()
                    compositor.wait()
        output = result.stdout + result.stderr
        if os.environ.get("KOS_TRAY_COLOR_QA"):
            qa = Path(os.environ["KOS_TRAY_COLOR_QA"])
            qa.mkdir(parents=True, exist_ok=True)
            for path in root.glob("*.png"):
                shutil.copy(path, qa / path.name)
        assert result.returncode == 0 and "TRAY_COLOR_PASS" in output, output
        assert not re.search(r"TRAY_COLOR_FAIL|ReferenceError|TypeError|Cannot assign|Unable to assign|"
            r"Failed to (create|compile)|Cannot open|Shader.*error|is not a type", output), output
        frames = {name: Image.open(root / f"{name}.png").convert("RGB")
            for name in ["original", "white", "black", "restored", "reloaded", "tinted", "color"]}
        for name, frame in frames.items():
            scale = frame.width / 320
            def pixel(x):
                return frame.getpixel((int(x * scale), int(16 * scale)))
            def near(actual, expected):
                assert all(abs(a - b) <= 2 for a, b in zip(actual, expected)), (name, actual, expected)
            for index, original in enumerate([(0, 0, 0), (255, 0, 0), (0, 255, 0)]):
                expected = (255, 255, 255) if name in ["white", "reloaded", "tinted", "color"] else (
                    (0, 0, 0) if name == "black" else original)
                near(pixel(index * 8 + 4), expected)
            near(pixel(28), (16, 32, 48) if name == "black" else (144, 160, 176))
            near(pixel(36), (32, 64, 96))
            near(pixel(44), (0, 0, 0))
            near(pixel(52), (76, 76, 76))
            near(pixel(60), (150, 150, 150))
            # Connected shell controls match the reference label at full ink
            # even when application artwork is grayscale/tinted at 20% opacity.
            ink = (0, 0, 0) if name in ["black", "restored"] else (255, 255, 255)
            for x, width in [(160, 24), (200, 24), (240, 24), (280, 24)]:
                crop = frame.crop((int(x * scale), int(4 * scale), int((x + width) * scale), int(28 * scale)))
                assert sum(count for count, color in crop.getcolors(crop.width * crop.height) if color == ink) > 8, (name, x, "missing opaque ink")
        assert frames["original"].crop((0, 0, 80, 32)).tobytes() == frames["restored"].crop((0, 0, 80, 32)).tobytes()
        assert frames["white"].tobytes() == frames["reloaded"].tobytes()
        assert frames["white"].tobytes() == frames["tinted"].tobytes() == frames["color"].tobytes()
        for name, ink, backdrop in [("white", (255, 255, 255), (22, 54, 113)), ("black", (0, 0, 0), (240, 240, 240))]:
            gallery = Image.open(root / f"applications-{name}.png").convert("RGB")
            for x in [4, 36, 68]:
                colors = dict((color, count) for count, color in gallery.crop((x, 4, x + 24, 28)).getcolors(576))
                assert colors.get(ink, 0) > 20, (name, x, "template is not opaque ink")
                assert colors.get(backdrop, 0) > 20, (name, x, "template lost transparent details")
        print("PASS: tray and production status controls share opaque appearance ink in color/grayscale/tint; alpha and settings round-trip")


if __name__ == "__main__":
    main()
