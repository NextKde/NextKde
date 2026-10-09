"""Run the native corner/desktop regression in disposable profiles at several Qt scales."""
import argparse
from contextlib import contextmanager
import ctypes
import json
import os
from pathlib import Path
import subprocess
import tempfile
from PIL import Image


@contextmanager
def keep_test_display_awake():
    # A sleeping display returns black desktop captures. This is a temporary
    # execution requirement on the test thread, not a change to power settings.
    state = ctypes.WinDLL("kernel32").SetThreadExecutionState
    state.argtypes = [ctypes.c_uint]
    state.restype = ctypes.c_uint
    previous = state(0x80000002)
    try:
        yield
    finally:
        state(previous or 0x80000000)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scales", nargs="+", default=["1", "1.25", "1.5"])
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    summaries = []
    for scale in args.scales:
        report = args.output.resolve() / f"scale-{scale}.json"
        env = os.environ.copy()
        env["QT_SCALE_FACTOR"] = scale
        for key in ("QT_QPA_DISABLE_REDIRECTION_SURFACE", "QT_SCREEN_SCALE_FACTORS", "QT_ENABLE_HIGHDPI_SCALING"):
            env.pop(key, None)
        # Verify the distributed runtime without a Qt SDK or vendor DLLs on PATH.
        env["PATH"] = str(args.executable.resolve().parent) + ";" + str(Path(os.environ["SystemRoot"]) / "System32")
        with tempfile.TemporaryDirectory(prefix="window-corner-", dir=args.output) as profile:
            startup = subprocess.STARTUPINFO()
            startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startup.wShowWindow = 1
            with report.with_suffix(".log").open("wb") as log:
                result = subprocess.run([str(args.executable.resolve()), "--data-dir", str(Path(profile).resolve()),
                    "--window-corner-regression", str(report)], env=env, stdout=log, stderr=log,
                    startupinfo=startup, timeout=75)
        data = json.loads(report.read_text(encoding="utf-8")) if report.exists() else {}
        rounded_samples = [sample for sample in data.get("samples", []) if sample.get("qmlRadius") == 32]
        rendering_ok = bool(rounded_samples) and all(sample.get("qmlTopLeftAlpha") == 0 for sample in rounded_samples)
        pixels = []
        presentation = []
        for sample in rounded_samples:
            stage = sample["stage"]
            if sample.get("desktopCaptureSkipped") or stage == "released-boundary-reproduction":
                continue
            qml = Image.open(str(report) + f".{stage}.qml.png").convert("RGBA")
            desktop = Image.open(str(report) + f".{stage}.desktop.png").convert("RGB")
            interior = (round(qml.width*.6), round(qml.height*.4))
            presentation.append({"stage": stage, "windowPresented":
                max(abs(c-e) for c, e in zip(desktop.getpixel(interior), qml.getpixel(interior)[:3])) < 8})
            radius = round(32 * sample["dpr"])
            bad = count = 0
            for x in range(radius):
                for y in range(radius):
                    if qml.getpixel((x, y))[3] != 0:
                        continue
                    count += 1
                    color = desktop.getpixel((x, y))
                    bad += max(abs(c-e) for c, e in zip(color, (23, 201, 91))) > 5
            pixels.append({"stage": stage, "excludedPixels": count, "wrongBackdropPixels": bad})
        transparency = {}
        for stage in ("dark-transparent", "dark-opaque"):
            qml = Image.open(str(report) + f".{stage}.qml.png").convert("RGBA")
            transparency[stage] = qml.getpixel((round(10 * data["samples"][0]["dpr"]), qml.height//2))[3]
        pixels_ok = all(row["wrongBackdropPixels"] == 0 for row in pixels) and all(row["windowPresented"] for row in presentation)
        transparency_ok = 0 < transparency["dark-transparent"] < 255 and transparency["dark-opaque"] == 255
        summary = {"scale": scale, "exitCode": result.returncode,
            "passed": result.returncode == 0 and data.get("passed", False) and rendering_ok and pixels_ok and transparency_ok,
            "qmlTransparentCorners": rendering_ok,
            "cornerPixels": pixels, "presentation": presentation, "sidebarAlpha": transparency,
            "failedChecks": [key for key, value in data.get("checks", {}).items() if not value],
            "checkCount": len(data.get("checks", {})),
            "nativePassed": all(value for key, value in data.get("checks", {}).items() if not key.endswith("/desktopCorner")),
            "desktopCaptureValid": bool(presentation) and all(row["windowPresented"] for row in presentation),
            "desktopCaptureSkipped": any(sample.get("desktopCaptureSkipped") for sample in data.get("samples", [])),
            "dpr": data.get("samples", [{}])[0].get("dpr")}
        print(json.dumps(summary), flush=True)
        summaries.append(summary)
        if not summary["desktopCaptureValid"]:
            print("Desktop capture unavailable; unlock/show the test desktop before continuing.", flush=True)
            break
    (args.output / "summary.json").write_text(json.dumps(summaries, indent=2), encoding="utf-8")
    return 0 if all(row["passed"] for row in summaries) else 1


if __name__ == "__main__":
    with keep_test_display_awake():
        raise SystemExit(main())
