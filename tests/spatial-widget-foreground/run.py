#!/usr/bin/env python3
"""Pixel and pointer checks for the actual subject renderer, isolated from user state."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "shell/desktop/modules/wallpaper"

def run():
    for renderer in ("shader", "mesh"):
        with tempfile.TemporaryDirectory(prefix="kos-spatial-widget-") as directory:
            root = Path(directory)
            common = root / "desktop/modules/common"
            wallpaper = root / "desktop/modules/wallpaper"
            common.mkdir(parents=True)
            wallpaper.mkdir(parents=True)
            for name in ("DepthWallpaperLayer.qml", "DepthWallpaper3D.qml", "SpatialWidgetForeground.qml", "SpatialPointer.mjs"):
                shutil.copy(SOURCE / name, wallpaper / name)
            shutil.copytree(SOURCE / "shaders", wallpaper / "shaders")
            # Only the dependencies are fixtures; the QML renderers and shaders
            # being exercised are copied byte-for-byte from the implementation.
            (common / "qmldir").write_text("module qs.desktop.modules.common\nsingleton ScreenLifecycle 1.0 ScreenLifecycle.qml\n")
            (common / "ScreenLifecycle.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject { property var activeScreen: null }\n")
            (wallpaper / "qmldir").write_text("module qs.desktop.modules.wallpaper\nsingleton SpatialWallpaperService 1.0 SpatialWallpaperService.qml\nsingleton WallpaperPreviewService 1.0 WallpaperPreviewService.qml\nDepthWallpaperLayer 1.0 DepthWallpaperLayer.qml\nSpatialWidgetForeground 1.0 SpatialWidgetForeground.qml\n")
            (wallpaper / "WallpaperPreviewService.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool active: false; property string mode: "image" }\n')
            for name, color in [("source", "red"), ("background", "lime"), ("matte", "white"), ("influence", "black"), ("depth", "white")]:
                Image.new("RGB", (640, 360), color).save(root / f"{name}.png")
            Image.new("I;16", (640, 360), 40000).save(root / "depth.png")
            matte = Image.new("RGB", (640, 360), "black")
            matte.paste("white", (0, 0, 320, 360))
            matte.save(root / "matte.png")
            service = 'pragma Singleton\nimport QtQuick\nQtObject {\nproperty bool ready: true\nproperty bool layeredReady: true\nproperty bool activationPending: false\nfunction presentationReady() {}\n'
            for prop, name in [("wallpaperUrl", "source"), ("backgroundPath", "background"), ("mattePath", "matte"), ("influencePath", "influence"), ("depthPath", "depth")]:
                service += f'property string {prop}: "{root / (name + ".png")}"\n'
            (wallpaper / "SpatialWallpaperService.qml").write_text(service + "}\n")
            if renderer == "shader":
                # Force the optional plugin's normal shader fallback without
                # producing an expected missing-plugin error in the log.
                path = wallpaper / "DepthWallpaperLayer.qml"
                path.write_text(path.read_text().replace("active: root.active && root.layeredTexturesReady", "active: false"))
            shutil.copy(Path(__file__).with_name("shell.qml"), root / "shell.qml")
            env = dict(os.environ, CAPTURE_DIR=str(root), EXPECTED_RENDERER=renderer, QML_IMPORT_PATH=os.environ.get("SPATIAL_QML_IMPORT_PATH", str(REPO / ".build/kosctl/qml")))
            result = subprocess.run(["quickshell", "--path", str(root), "--no-color"], env=env, capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            (REPO / "tmp" / f"spatial-widget-{renderer}.log").write_text(output)
            assert result.returncode == 0 and "SPATIAL_WIDGET_PASS" in output, output
            assert not re.search(r"FAIL|ReferenceError|TypeError|Cannot assign|Unable to assign|Failed to|Shader.*error|is not a type", output), output
            if renderer == "mesh":
                assert "renderer=3D mesh" in output, output
            normal = Image.open(root / "normal.png").convert("RGB")
            shutil.copy(root / "normal.png", REPO / "tmp" / f"spatial-widget-{renderer}.png")
            sx, sy = normal.width / 640, normal.height / 360
            def pixel(image, x, y): return image.getpixel((int(x*sx), int(y*sy)))
            assert pixel(normal, 163, 180)[0] > 220, (renderer, pixel(normal, 163, 180))
            assert pixel(normal, 477, 180)[2] > 220, "transparent matte must not cover the far rim"
            assert pixel(normal, 240, 180)[0] > 220, "subject must cover the widget center"
            assert pixel(normal, 520, 180)[1] > 220, ("foreground must stay within widget bounds", renderer, pixel(normal, 520, 180))
            assert pixel(normal, 196, 126)[:2] == (255, 255), "files must stay above foreground even inside widget bounds"
            hover = Image.open(root / "hover.png").convert("RGB")
            assert pixel(hover, 240, 180)[2] > 220, "hover reveals entire widget"
            assert pixel(hover, 120, 320)[0] > 220, "hover must not reveal other widgets"
            assert pixel(hover, 196, 126)[:2] == (255, 255), "files remain unchanged during hover"
            restored = Image.open(root / "restored.png").convert("RGB")
            assert pixel(restored, 240, 180)[0] > 220, "leaving restores full subject occlusion"
            for name in ("editing", "empty"):
                image = Image.open(root / (name + ".png")).convert("RGB")
                x = 163 if name == "editing" else 83
                assert pixel(image, x, 180)[2] > 220, f"{name}: no foreground occlusion"
            moved = Image.open(root / "moved.png").convert("RGB")
            assert pixel(moved, 83, 180)[0] > 220, "foreground follows moved widgets and pointer"
            assert pixel(moved, 240, 180)[0] > 220, "moved widget center covered"
            print(f"PASS {renderer}: full subject, file protection, hover reveal/restore, independent widgets, clicks, edit mode, movement, empty layout")

if __name__ == "__main__":
    run()
