"""Measure either of two scrolls in the fixed 30 fps Apple Music reference.

Source: https://www.youtube.com/watch?v=jKdvwVAZKZM (608x972, 141 frames).
OpenCV normalized template matching tracks the same text patches; no OCR,
invented intermediate source frames, or unconstrained time warping is used.
Qt traces come from the actual QML scene rendered by render_probe.
"""
import argparse
import csv
import json
from pathlib import Path

import cv2
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def crossing(times, progress, threshold=.1):
    for i in range(1, len(times)):
        if progress[i - 1] < threshold <= progress[i]:
            weight = (threshold - progress[i - 1]) / (progress[i] - progress[i - 1])
            return float(times[i - 1] + weight * (times[i] - times[i - 1]))
    raise ValueError("The trace never crosses the requested displacement")


def reference_rows(directory, transition):
    # Patch coordinates are in the original, unscaled video frames. The
    # outgoing patch leaves the lyric viewport after source frame 29.
    specifications = [
        ("outgoing", 1, (337, 363, 438, 387), (323, 260, 448, 402), 29),
        ("incoming", 61, (318, 362, 441, 386), (290, 340, 450, 490), 50),
        ("following", 101, (317, 362, 439, 386), (293, 430, 450, 580), 50),
    ]
    first, last_frame = 0, 50
    if transition == 2:
        first, last_frame = 59, 99
        specifications = [
            ("outgoing", 61, (318, 362, 441, 386), (295, 260, 448, 402), 77),
            ("incoming", 101, (317, 362, 439, 386), (293, 340, 450, 490), 99),
            ("following", 141, (327, 362, 441, 386), (300, 430, 450, 585), 99),
        ]
    images = [cv2.imread(str(directory / f"frame-{i:05d}.png"), cv2.IMREAD_GRAYSCALE)
              for i in range(first + 1, last_frame + 2)]
    assert all(image is not None and image.shape == (972, 608) for image in images)
    result = {}
    for identity, source, patch, search, last in specifications:
        seed = cv2.imread(str(directory / f"frame-{source:05d}.png"), cv2.IMREAD_GRAYSCALE)
        x, y, right, bottom = patch
        template = seed[y:bottom, x:right]
        left, top, right, bottom = search
        points = []
        for local_index, image in enumerate(images[:last - first + 1]):
            index = first + local_index
            scores = cv2.matchTemplate(image[top:bottom, left:right], template, cv2.TM_CCOEFF_NORMED)
            _, score, _, location = cv2.minMaxLoc(scores)
            points.append({"frame": index, "time": index / 30, "y": location[1] + top,
                           "score": score})
        result[identity] = {"points": points, "patch": patch, "search": search, "templateFrame": source - 1}
    # Same layout pitch; the outgoing row's destination is clipped by the
    # header, so use the fully visible incoming row's measured travel.
    incoming = result["incoming"]["points"]
    travel = np.median([p["y"] for p in incoming[:18]]) - np.median([p["y"] for p in incoming[-9:]])
    assert 85 < travel < 105, "Unexpected reference geometry"
    for row in result.values():
        initial = float(np.median([p["y"] for p in row["points"][:18]]))
        row["initialY"], row["travelPx"] = initial, float(travel)
        for point in row["points"]:
            point["progress"] = (initial - point["y"]) / travel
        row["t10"] = crossing([p["time"] for p in row["points"]], [p["progress"] for p in row["points"]])
    return result


def qt_rows(directory, transition):
    states = json.loads((directory / "motion-state.json").read_text())
    result = {}
    change_time = 4 * transition
    for identity, index in [("outgoing", 19 + transition), ("incoming", 20 + transition), ("following", 21 + transition)]:
        points = [(s["positionMs"] / 1000 - 80, r["y"])
                  for s in states for r in s["rows"] if r["index"] == index]
        times, ys = np.asarray(points).T
        initial = float(np.median(ys[(times >= change_time - .5) & (times < change_time - .05)]))
        final = float(np.median([r["targetY"] for s in states for r in s["rows"]
            if r["index"] == index and change_time + .5 <= s["positionMs"] / 1000 - 80 < change_time + 1]))
        progress = (initial - ys) / (initial - final)
        selected = times >= change_time - .5
        result[identity] = {"times": times[selected], "progress": progress[selected], "t10": crossing(times[selected], progress[selected])}
    return result


def short_word_float(directory):
    # A single short word is stationary with its row during these frames.
    # High-pass normalized correlation suppresses the changing album backdrop
    # and highlight brightness. Subpixel peaks are estimates, not extra frames.
    seed = cv2.imread(str(directory / "frame-00061.png"), cv2.IMREAD_GRAYSCALE).astype(np.float32)
    template = seed[325:350, 240:304]
    template -= cv2.GaussianBlur(template, (0, 0), 2)
    points = []
    for number in range(37, 71):
        image = cv2.imread(str(directory / f"frame-{number:05d}.png"), cv2.IMREAD_GRAYSCALE).astype(np.float32)
        region = image[319:357, 236:308]
        region -= cv2.GaussianBlur(region, (0, 0), 2)
        scores = cv2.matchTemplate(region, template, cv2.TM_CCOEFF_NORMED)
        _, score, _, (x, y) = cv2.minMaxLoc(scores)
        fraction = 0.
        if 0 < y < scores.shape[0] - 1:
            a, b, c = scores[y - 1:y + 2, x]
            fraction = float(.5 * (a - c) / (a - 2 * b + c))
        points.append({"frame": number - 1, "time": (number - 1) / 30,
                       "yPx": y + 319 + fraction, "score": score})
    return {"templateRect": [240, 325, 64, 25], "points": points,
            "observedUpwardDriftPx": points[9]["yPx"] - points[-1]["yPx"],
            "limits": "This shows the direction/hold of a short-word float only. It does not identify the exact font size, original TTML word boundaries, or an exact duration/easing fit."}


def compare(reference, candidate, transition):
    # One shared time offset, established only from the outgoing row. The
    # other two rows must retain their real relative delays and trajectory.
    offset = candidate["outgoing"]["t10"] - reference["outgoing"]["t10"]
    metrics = {"sharedTimeOffsetMs": offset * 1000, "rows": {}}
    origin = 0 if transition == 1 else 1.6
    for name, row in reference.items():
        qt = candidate[name]
        points = [p for p in row["points"] if .65 + origin <= p["time"] <= 1.3 + origin and p["score"] >= .6]
        sampled = np.interp([p["time"] + offset for p in points], qt["times"], qt["progress"])
        error = sampled - [p["progress"] for p in points]
        metrics["rows"][name] = {"samples": len(points), "normalizedMae": float(np.abs(error).mean()),
            "normalizedRmse": float(np.sqrt(np.mean(error**2))),
            "t10LagMs": (qt["t10"] - candidate["outgoing"]["t10"]) * 1000,
            "referenceT10LagMs": (row["t10"] - reference["outgoing"]["t10"]) * 1000}
    return metrics


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--transition", type=int, choices=(1, 2), default=1)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    reference = reference_rows(args.reference, args.transition)
    candidates = {"before": qt_rows(args.before, args.transition), "after": qt_rows(args.after, args.transition)}
    results = {name: compare(reference, candidate, args.transition) for name, candidate in candidates.items()}
    report = {"source": "https://www.youtube.com/watch?v=jKdvwVAZKZM", "referenceFps": 30,
              "transition": args.transition, "referenceRows": reference, "comparisons": results,
              "shortWordFloat": short_word_float(args.reference),
              "limits": "Normalized vertical motion only; one shared time offset per capture. Source sampling is 33.3 ms; pixel matching does not establish subframe accuracy, full visual equivalence, or word timing."}
    (args.output / "alignment.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    with (args.output / "aligned-frames.csv").open("w", newline="", encoding="utf-8") as file:
        writer = csv.writer(file)
        writer.writerow(["row", "sourceFrame", "sourceTimeSec", "sourceY", "matchScore", "sourceDisplacement", "before", "after"])
        for name, row in reference.items():
            for point in row["points"]:
                values = [float(np.interp(point["time"] + results[version]["sharedTimeOffsetMs"] / 1000,
                          candidate[name]["times"], candidate[name]["progress"])) for version, candidate in candidates.items()]
                writer.writerow([name, point["frame"], point["time"], point["y"], point["score"], point["progress"], *values])
    plt.rcParams["font.family"] = "Microsoft YaHei"
    figure, axes = plt.subplots(1, 3, figsize=(14, 5), sharey=True)
    for axis, name, title in zip(axes, reference, ["离场行", "进入行", "下一行"]):
        points = reference[name]["points"]
        axis.plot([p["time"] for p in points], [p["progress"] for p in points], "o", ms=4,
                  color="#222222", label="原版逐帧测量（30 fps）")
        for version, color, label in [("before", "#c87331", "修复前"), ("after", "#1769aa", "修复后")]:
            data = candidates[version][name]
            axis.plot(data["times"] - results[version]["sharedTimeOffsetMs"] / 1000, data["progress"], color=color, label=label)
        origin = 0 if args.transition == 1 else 1.6
        axis.set(xlim=(.6 + origin, 1.35 + origin), ylim=(-.04, 1.06), title=title, xlabel="原片时间（秒）")
        axis.grid(alpha=.2)
    axes[0].set_ylabel("归一化向上位移")
    axes[0].legend(fontsize=8, loc="lower right")
    figure.suptitle("Apple Music 换行帧对齐：三行共用同一时间偏移，保留相邻行的起动差")
    figure.text(.5, .015, "只比较垂直运动；原片一帧 33.3 ms。字幕、字体、模糊与逐字亮度不计入此误差。", ha="center", fontsize=9)
    figure.tight_layout(rect=(0, .05, 1, .94))
    figure.savefig(args.output / "scroll-alignment.png", dpi=150)
    print(json.dumps(results, ensure_ascii=False, indent=2))
