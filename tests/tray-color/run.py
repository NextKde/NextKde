#!/usr/bin/env python3
"""Render the shipping icon shader and round-trip the tray icon preference in isolation."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from PIL import Image, ImageChops

REPO = Path(__file__).resolve().parents[2]

# Straight-colour stripes in the generated tray test icon.
STRIPES = [(0, 0, 0), (255, 0, 0), (0, 255, 0)]
TINT = (255, 0, 0)
APPLICATION_COLORS = [(225, 140, 105), (74, 142, 214)]


def luminance(color):
    return (color[0] * 0.299 + color[1] * 0.587 + color[2] * 0.114) / 255.0


def grayscale(color):
    value = round(luminance(color) * 255)
    return (value, value, value)


def tinted(color):
    # Matches icon_effect.frag: mix(tint, white, lum) * lum, per channel.
    lum = luminance(color)
    return tuple(round((channel / 255.0 * (1.0 - lum) + lum) * lum * 255)
        for channel in TINT)


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
            "pragma Singleton\nimport QtQuick\nQtObject { property bool pixmapCacheAllowed: true; property int revision: 0 }\n")
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
        # The installed desktop icons have color even though the live tray
        # pixels are dark silhouettes. Use real DesktopEntries in a private XDG
        # catalogue, with distinct colors to catch swapped application matches.
        applications = root / "data/applications"
        applications.mkdir(parents=True)
        for index, (name, shade, desktop_id) in enumerate([
                ("mono", 0, "com.anthropic.Claude"), ("gray", 31, "magpie")]):
            for suffix, color in [("", (shade, shade, shade)), ("-color", APPLICATION_COLORS[index])]:
                artwork = Image.new("RGBA", (24, 24))
                artwork.paste((*color, 255), (2, 2, 14, 22))
                artwork.paste((*color, 128), (14, 2, 22, 22))
                artwork.paste((0, 0, 0, 0), (6, 8, 10, 16))
                artwork.save(root / f"{name}{suffix}.png")
            (applications / f"{desktop_id}.desktop").write_text(
                f"[Desktop Entry]\nType=Application\nName={desktop_id}\n"
                f"Exec=/bin/true\nIcon={root / (name + '-color.png')}\n")
        # Font glyphs can switch between subpixel and grayscale antialiasing
        # when the light/dark transition recreates an effect layer. Pin one
        # method so exact pixel comparisons cover the whole scene reliably.
        env = dict(os.environ, QT_QPA_PLATFORM="wayland", QSG_RHI_BACKEND="opengl",
            QSG_DISTANCEFIELD_ANTIALIASING="gray",
            LIBGL_ALWAYS_SOFTWARE="1", CAPTURE_DIR=str(root), TRAY_TEST_ICON=(root / "icon.png").as_uri(),
            TRAY_TEST_MONO_ICON=(root / "mono.png").as_uri(), TRAY_TEST_GRAY_ICON=(root / "gray.png").as_uri(),
            TRAY_TEST_MISSING_ICON=(root / "missing-application-icon.png").as_uri(),
            XDG_STATE_HOME=str(root / "state"), XDG_CONFIG_HOME=str(root / "config"),
            XDG_CACHE_HOME=str(root / "cache"), XDG_DATA_HOME=str(root / "data"),
            KOS_PLATFORM_SOCKET=str(root / "no-platform.sock"), KOS_DATA_SOCKET=str(root / "no-data.sock"),
            QML_IMPORT_PATH=os.environ.get("QML_IMPORT_PATH", str(REPO / ".build/kosctl/qml")),
            XDG_RUNTIME_DIR=str(root / "runtime"), WAYLAND_DISPLAY="tray-color-test", DISPLAY="")
        env.pop("QT_QUICK_BACKEND", None)
        client_output = ""
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
                client_output = result.stdout + result.stderr
            except subprocess.TimeoutExpired as error:
                client_output = "\n".join(part.decode(errors="replace") if isinstance(part, bytes) else part
                    for part in [error.stdout, error.stderr] if part)
                raise
            finally:
                compositor.terminate()
                try:
                    compositor.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    compositor.kill()
                    compositor.wait()
                logs = {"kwin.log": (root / "kwin.log").read_text(), "quickshell.log": client_output}
                for name, text in logs.items():
                    print(f"\n--- {name} ---\n{text}", flush=True)
                if os.environ.get("KOS_TRAY_COLOR_QA"):
                    qa = Path(os.environ["KOS_TRAY_COLOR_QA"])
                    qa.mkdir(parents=True, exist_ok=True)
                    for name, text in logs.items():
                        (qa / name).write_text(text)
        output = result.stdout + result.stderr
        if os.environ.get("KOS_TRAY_COLOR_QA"):
            qa = Path(os.environ["KOS_TRAY_COLOR_QA"])
            qa.mkdir(parents=True, exist_ok=True)
            for path in root.glob("*.png"):
                shutil.copy(path, qa / path.name)
        assert result.returncode == 0 and "TRAY_COLOR_PASS" in output, output
        # A deliberately missing override exercises deferred image-error fallback.
        checked_output = "\n".join(line for line in output.splitlines()
            if "missing-application-icon.png" not in line)
        assert not re.search(r"TRAY_COLOR_FAIL|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign|"
            r"Failed to (create|compile)|Cannot open|Shader.*error|is not a type", checked_output), output
        frames = {name: Image.open(root / f"{name}.png").convert("RGB")
            for name in ["original", "white", "black", "restored", "reloaded", "tinted", "color"]}
        # Tray artwork follows the Dock's icon mode: color keeps the source,
        # grayscale desaturates, and tint applies the tonal formula.
        expected_for = {
            "original": lambda color: color,
            "restored": lambda color: color,
            "color": lambda color: color,
            "white": grayscale,
            "black": grayscale,
            "reloaded": grayscale,
            "tinted": tinted,
        }
        for name, frame in frames.items():
            scale = frame.width / 320
            def pixel(x):
                return frame.getpixel((int(x * scale), int(16 * scale)))
            def near(actual, expected):
                assert all(abs(a - b) <= 2 for a, b in zip(actual, expected)), (name, actual, expected)
            for index, original in enumerate(STRIPES):
                near(pixel(index * 8 + 4), expected_for[name](original))
            # The fourth stripe is white at 50% alpha; every mode leaves it white.
            near(pixel(28), (144, 160, 176))
            near(pixel(36), (32, 64, 96))
            near(pixel(44), (0, 0, 0))
            near(pixel(52), (76, 76, 76))
            near(pixel(60), (150, 150, 150))
            # Connected shell controls match the reference label at full ink
            # even when application artwork is grayscale/tinted.
            ink = (0, 0, 0) if name in ["black", "restored"] else (255, 255, 255)
            for x, width in [(160, 24), (200, 24), (240, 24), (280, 24)]:
                crop = frame.crop((int(x * scale), int(4 * scale), int((x + width) * scale), int(28 * scale)))
                assert sum(count for count, color in crop.getcolors(crop.width * crop.height) if color == ink) > 8, (name, x, "missing opaque ink")
        for name in frames:
            gallery = Image.open(root / f"applications-{name}.png").convert("RGB")
            scale = gallery.width / 320
            background = (240, 240, 240) if name in ["black", "restored"] else (22, 54, 113)
            def gallery_pixel(x, y):
                return gallery.getpixel((int(x * scale), int(y * scale)))
            for index, x in enumerate([40, 72]):
                color = expected_for[name](APPLICATION_COLORS[index])
                actual = gallery_pixel(x + 4, 16)
                assert all(abs(a - b) <= 2 for a, b in zip(actual, color)), (name, x, "application color", actual, color)
                assert gallery_pixel(x + 8, 16) == background, (name, x, "transparent hole")
                edge = tuple(round(fg * 128 / 255 + bg * 127 / 255) for fg, bg in zip(color, background))
                actual = gallery_pixel(x + 18, 16)
                assert all(abs(a - b) <= 2 for a, b in zip(actual, edge)), (name, x, "alpha edge", actual, edge)
                # Attention and unqualified Chromium items retain even black
                # source pixels instead of turning into an opaque ink badge.
                assert gallery_pixel(x + 3, 48) == (0, 0, 0), (name, x, "original artwork")
                expected = expected_for[name]((255, 0, 0))
                actual = gallery_pixel(x + 8, 48)
                assert all(abs(a - b) <= 2 for a, b in zip(actual, expected)), (name, x, "color artwork", actual, expected)
        assert frames["original"].crop((0, 0, 80, 32)).tobytes() == frames["restored"].crop((0, 0, 80, 32)).tobytes()
        # The complete scene, including font glyphs and reference labels,
        # must return to exactly the same pixels after the settings reload.
        for name, reference in [("reloaded", "white"), ("color", "original")]:
            difference = ImageChops.difference(frames[reference], frames[name])
            assert difference.getbbox() is None, (name, "tray artwork changed", difference.getbbox())
        print("PASS: Claude/Magpie use installed color icons with alpha preserved; live attention and other tray artwork stay intact; settings round-trip")


if __name__ == "__main__":
    main()
