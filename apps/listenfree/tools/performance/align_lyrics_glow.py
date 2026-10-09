"""Compare the outer glow of two sustained notes in the original iPad video.

Uses the source/onset calibration from align_lyrics_words.py. Sample the upper
straight stem of the first 'b', avoiding its bowl, at every source frame after
the partial reveal. Align the 50% ink edge, normalize contrast and distance by
each renderer's still glyph height. This compares halo falloff, not font shapes
or linear-light radiance; source compression/background gradients remain.
"""
import argparse
import json
from pathlib import Path

import cv2
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from align_lyrics_words import CASES, reference_frame


DISTANCES = np.linspace(-.16, -.04, 25)
STEM_WINDOWS = [(.14, .30), (.17, .34), (.20, .36)]


def stem_profile(image, rect, window):
    left, top, right, bottom = [int(round(v)) for v in rect]
    patch = image[top:bottom, left:right].astype(np.float64)
    background = np.median(np.r_[patch[:5].ravel(), patch[-5:].ravel()])
    peak = np.quantile(patch[:, 15:], .96)
    assert peak-background > 15, "Insufficient contrast"
    count, _, stats, _ = cv2.connectedComponentsWithStats(
        np.uint8(patch > background+(peak-background)*.5))
    assert count > 1, "Missing glyph"
    x, y, width, height, area = stats[1+np.argmax(stats[1:, cv2.CC_STAT_AREA])]
    assert 450 < area < 3000 and 35 < height < 70, "Glyph lost or merged"
    first, last = top+y+round(height*window[0]), top+y+round(height*window[1])
    profile = image[first:last, left:right].mean(axis=0)
    floor = float(np.median(profile[:5]))
    ceiling = float(np.max(profile[x:x+12]))
    normalized = (profile-floor)/(ceiling-floor)
    crossing = next(i for i in range(max(1, x-3), x+8) if normalized[i] >= .5)
    edge = crossing-1+(.5-normalized[crossing-1])/(normalized[crossing]-normalized[crossing-1])
    return np.arange(right-left)-edge, normalized, int(height)


def qt_sample(directory, states, case, frame):
    word = next(w for w in states[frame]["words"] if w["id"] == f"lyricWord{case['row']}/1")
    x, y, width, height = word["rect"]
    image = cv2.imread(str(directory/"motion"/f"frame-{frame:05d}.png"), 0)
    return image, (x-14, y-10, x+42, y+height+10)


def measure(reference, directory, states, case, window):
    if directory is None:
        sample = lambda time: (reference_frame(reference, time+case["onset"]), case["rect"])
        base = sample(case["baseline"]-case["onset"])
    else:
        sample = lambda time: qt_sample(directory, states, case,
            round((case["qtStart"]-80000+time*1000)*60/1000))
        base = qt_sample(directory, states, case, 15 if case["row"] == 20 else 264)
    x, profile, height = stem_profile(*base, window)
    baseline = np.interp(DISTANCES*height, x, profile)
    start = round((case["onset"]+.4-179)*30)
    stop = round((case["last"]-179)*30)
    points = []
    for frame in range(start, stop+1):
        time = 179+frame/30-case["onset"]
        x, profile, _ = stem_profile(*sample(time), window)
        values = np.interp(DISTANCES*height, x, profile)
        points.append({"time": time, "profile": values.tolist(),
                       "outerMean": float(np.mean(values)),
                       "atTenthHeight": float(np.interp(-.1*height, x, profile))})
    return {"baselineHeight": height, "baselineProfile": baseline.tolist(), "points": points}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("reference", "before", "after", "output"):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    states = {name: json.loads((getattr(args, name)/"motion-state.json").read_text())
              for name in ("before", "after")}
    args.output.mkdir(parents=True, exist_ok=True)
    plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei"]
    plt.rcParams["axes.unicode_minus"] = False
    fig, axes = plt.subplots(2, 2, figsize=(12, 7))
    results = []
    for column, case in enumerate(CASES):
        sensitivity = []
        for window in STEM_WINDOWS:
            traces = {"original": measure(args.reference, None, None, case, window)}
            for name in ("before", "after"):
                traces[name] = measure(args.reference, getattr(args, name), states[name], case, window)
            matrices = {name: np.array([p["profile"] for p in trace["points"]])
                        for name, trace in traces.items()}
            sensitivity.append({"stemWindow": window, "frames": len(matrices["original"]),
                "beforeProfileMAE": float(np.abs(matrices["before"]-matrices["original"]).mean()),
                "afterProfileMAE": float(np.abs(matrices["after"]-matrices["original"]).mean())})
            if window == STEM_WINDOWS[1]:
                primary = traces
                for name, label, color in (("original", "原版 iPad", "#171717"),
                        ("before", "修改前", "#cd7045"), ("after", "修改后", "#008a80")):
                    axes[0, column].plot(DISTANCES*100, matrices[name].mean(axis=0)*100, label=label, color=color)
                    points = traces[name]["points"]
                    axes[1, column].plot([p["time"] for p in points],
                        [p["atTenthHeight"]*100 for p in points], label=label, color=color)
        axes[0, column].set_title(case["name"]+"：柔光衰减（连续帧均值）")
        axes[0, column].set_xlabel("距 50% 字形边缘 / 静止字高（%）")
        axes[1, column].set_title("字形外侧 0.1 字高处的亮度")
        axes[1, column].set_xlabel("距手工标定扫亮起点（秒）")
        for axis in axes[:, column]:
            axis.set_ylabel("相对字形核心亮度（%）")
            axis.grid(alpha=.2); axis.legend(fontsize=8)
        results.append({"calibration": case, "sensitivity": sensitivity, "traces": primary})
    fig.suptitle("长音光晕逐帧核对", fontsize=15)
    fig.text(.5, .005, "原片 30 fps / Qt 每秒 60 次采样；不同字体，手工起点，无原始逐字时间戳。相对亮度不是线性光能量。", ha="center", fontsize=9)
    fig.tight_layout(rect=(0,.03,1,.95))
    fig.savefig(args.output/"glow-alignment.png", dpi=150)
    plt.close(fig)
    report = {"source": "https://www.youtube.com/watch?v=Zne1E23Bd7w",
        "normalizedDistances": DISTANCES.tolist(), "cases": results,
        "limits": "只覆盖两个长音的首字母直笔画；背景渐变、视频压缩、字体差异及手工时间标定仍影响测量。负值保留，不通过截断美化误差。"}
    (args.output/"glow-alignment.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    for result in results:
        print(result["calibration"]["name"], result["sensitivity"])


if __name__ == "__main__":
    main()
