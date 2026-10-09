"""Pixel measurements of two sustained notes in the original iPad video.

Source: https://www.youtube.com/watch?v=Zne1E23Bd7w, 1920x1080/30 fps.
Reference frame 1 is the frame at 179 seconds, without frame interpolation.
Inputs A/B are --word-reference captures of the real QML renderer. The video
has no TTML: the two visible sweep onsets are manually marked, and test word
durations are explicitly approximate. Compare motion, not identical fonts.
OpenCV connected components isolate the first letter's core; three contrast
thresholds expose sensitivity to antialiasing, sweep and compression.
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


def glyph_core(image, rect, threshold=.5):
    left, top, right, bottom = [int(round(v)) for v in rect]
    patch = image[top:bottom, left:right].astype(np.float32)
    background = np.median(np.r_[patch[:5].ravel(), patch[-5:].ravel()])
    peak = np.quantile(patch, .97)
    assert peak - background > 15, "Insufficient foreground contrast"
    mask = np.uint8(patch > background + (peak - background) * threshold)
    count, labels, stats, centers = cv2.connectedComponentsWithStats(mask)
    assert count > 1
    index = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
    x, y, width, height, area = stats[index]
    assert 450 < area < 3000 and 35 < height < 70, f"Glyph was lost or merged: area={area}, height={height}"
    return {"centerY": float(top + y + height / 2), "height": int(height),
            "width": int(width), "area": int(area), "contrast": float(peak - background)}


CASES = [
    {"name": "长音 A", "onset": 183 + 10/30, "last": 184.4, "baseline": 183.0,
     "rect": (776, 435, 835, 523), "qtStart": 81000, "row": 20, "duration": 1200},
    {"name": "长音 B", "onset": 189 + 22/30, "last": 191.2, "baseline": 189.0,
     "rect": (1007, 435, 1064, 523), "qtStart": 85000, "row": 21, "duration": 1467},
]


def reference_frame(directory, time):
    return cv2.imread(str(directory / f"frame-{round((time-179)*30)+1:05d}.png"), 0)


def reference_trace(directory, case, threshold):
    baseline = glyph_core(reference_frame(directory, case["baseline"]), case["rect"], threshold)
    points = []
    first = round((case["onset"] - .4 - 179)*30)
    last = round((case["last"]-179)*30)
    for frame in range(first, last+1):
        time = 179+frame/30
        # A partially lit letter has two different contrasts. A single core
        # threshold cannot measure its geometry reliably; omit that interval
        # for all versions, rather than treating a sweep as a shape change.
        if -.067 < time-case["onset"] < .3: continue
        core = glyph_core(reference_frame(directory, time), case["rect"], threshold)
        points.append({"time": time-case["onset"], "sourceFrame": frame,
            "rise": (baseline["centerY"]-core["centerY"])/baseline["height"],
            "scale": core["height"]/baseline["height"], **core})
    return baseline, points


def qt_trace(directory, case, reference, threshold):
    states = json.loads((directory / "motion-state.json").read_text())
    identity = f"lyricWord{case['row']}/1"
    def sample(index):
        state = states[index]
        word = next(w for w in state["words"] if w["id"] == identity)
        x, y, width, height = word["rect"]
        image = cv2.imread(str(directory / "motion" / f"frame-{index:05d}.png"), 0)
        # The first shaped advance is 42.25 px at 64 px Microsoft YaHei UI.
        # Keep the neighboring letter outside the crop; CC rejects fragments.
        core = glyph_core(image, (x-15, y-20, x+42, y+height+16), threshold)
        return core, word
    base_index = 15 if case["row"] == 20 else 264
    baseline, base_word = sample(base_index)
    offset = baseline["centerY"]-base_word["rect"][1]
    points = []
    for point in reference:
        index = round((case["qtStart"]-80000+point["time"]*1000)*60/1000)
        core, word = sample(index)
        row_scale = word["rect"][3]/base_word["rect"][3]
        unlifted = word["rect"][1]-word["liftEm"]*64*row_scale+offset*row_scale
        points.append({"time": point["time"], "sourceFrame": index,
            "rise": (unlifted-core["centerY"])/(baseline["height"]*row_scale),
            "scale": core["height"]/(baseline["height"]*row_scale), **core})
    return baseline, points


def blur_trace(directory):
    # Fit the same incoming patch to its sharp future appearance. Overall
    # brightness/background and row scale are nuisance terms, not blur.
    # Sigma here is an image-fit proxy, never Qt MultiEffect.blur units.
    def highpass(image): return image-cv2.GaussianBlur(image, (0, 0), 15)
    base = reference_frame(directory, 193.5)[350:454, 778:1025].astype(np.float32)/255
    models = []
    for sigma in np.arange(0, 9.01, .3):
        blurred = cv2.GaussianBlur(base, (0, 0), sigma) if sigma else base
        for scale in [.97, .98, .99, 1., 1.01]:
            patch = cv2.resize(blurred, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)
            models.append((float(sigma), scale, highpass(patch)[15:-15, 12:-12]))
    points = []
    for frame in range(359, 392, 2):
        image = reference_frame(directory, 179+(frame-1)/30)[330:725, 765:1040].astype(np.float32)/255
        image = highpass(image)
        best = (-1,)
        for sigma, scale, patch in models:
            scores = cv2.matchTemplate(image, patch, cv2.TM_CCOEFF_NORMED)
            _, score, _, (x, y) = cv2.minMaxLoc(scores)
            if score > best[0]: best = (score, sigma, scale, x+765, y+330)
        points.append({"time": 179+(frame-1)/30, "score": best[0], "sigmaPx": best[1],
                       "scale": best[2], "x": best[3], "y": best[4]})
    return points


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["reference", "before", "after", "output"]: parser.add_argument(name, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei"]
    plt.rcParams["axes.unicode_minus"] = False
    fig, axes = plt.subplots(2, 2, figsize=(12, 7), sharex="col")
    results = []
    rows = []
    for column, case in enumerate(CASES):
        experiments = []
        for threshold in [.45, .5, .55]:
            base, reference = reference_trace(args.reference, case, threshold)
            _, before = qt_trace(args.before, case, reference, threshold)
            _, after = qt_trace(args.after, case, reference, threshold)
            error = lambda points,key: float(np.mean([abs(a[key]-b[key]) for a,b in zip(reference, points)]))
            experiments.append({"threshold": threshold, "beforeRiseMAE": error(before,"rise"),
                "afterRiseMAE": error(after,"rise"), "beforeScaleMAE": error(before,"scale"),
                "afterScaleMAE": error(after,"scale")})
            if threshold == .5:
                for label, points, color in [("原版 iPad", reference, "#171717"),
                    ("修改前", before, "#cd7045"), ("修改后", after, "#008a80")]:
                    axes[0, column].plot([p["time"] for p in points], [p["rise"]*100 for p in points], label=label, color=color)
                    axes[1, column].plot([p["time"] for p in points], [(p["scale"]-1)*100 for p in points], label=label, color=color)
                for a, b, c in zip(reference, before, after):
                    rows.append({"case": case["name"], "time": a["time"], "referenceFrame": a["sourceFrame"],
                        "qtFrame": b["sourceFrame"], "referenceRise": a["rise"], "beforeRise": b["rise"],
                        "afterRise": c["rise"], "referenceScale": a["scale"], "beforeScale": b["scale"], "afterScale": c["scale"]})
                primary = {"sourceBaseGlyphHeightPx": base["height"], "reference": reference,
                           "before": before, "after": after}
        axes[0, column].set_title(case["name"] + "：实际字形核心的位移")
        axes[0, column].set_ylabel("上浮 / 静止字形高度（%）")
        axes[1, column].set_ylabel("字形高度变化（%）")
        axes[1, column].set_xlabel("距手工标定扫亮起点（秒）")
        for axis in axes[:, column]:
            axis.axvspan(-.067, .3, color="gray", alpha=.1)
            axis.grid(alpha=.2); axis.legend(fontsize=8)
        results.append({"calibration": case, "sensitivity": experiments, **primary})
    fig.suptitle("长音逐帧核对：位移与扩张幅度", fontsize=15)
    fig.text(.5, .005, "30 fps 原版 / 60 次每秒 Qt 实图；灰区为部分扫亮，不测字形。不同字体、无原始逐字时间戳。", ha="center", fontsize=10)
    fig.tight_layout(rect=(0,.03,1,.95))
    fig.savefig(args.output / "word-alignment.png", dpi=150)
    plt.close(fig)
    blur = blur_trace(args.reference)
    report = {"source": "https://www.youtube.com/watch?v=Zne1E23Bd7w", "referenceFps": 30,
        "qtSamplesPerSecond": 60, "cases": results, "incomingBlur": blur,
        "limits": "手工扫亮起点与近似音节长度；字体不同。误差按字形核心高度归一化；阈值敏感性和未缩小的缩放差异均保留。模糊值是模板匹配的等效 sigma，不是 Qt blur 参数。"}
    (args.output / "word-alignment.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    with (args.output / "word-aligned-frames.csv").open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
    for result in results: print(result["calibration"]["name"], result["sensitivity"])


if __name__ == "__main__": main()
