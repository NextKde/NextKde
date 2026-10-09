"""Check real GPU frames for one-frame ink loss or double painting.

Uses Pillow/NumPy and the moving word bounds exported by render_probe.
This is a temporal regression gate, not a perceptual-similarity/FPS metric.
An old capture can be checked against an identical fixture's newer telemetry
with --state-from; frame count, resolution and media timestamps must agree.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image


def check(capture, state_from):
    metadata = json.loads((capture / "motion.json").read_text())
    state_metadata = json.loads((state_from / "motion.json").read_text())
    assert all(metadata[key] == state_metadata[key] for key in ("frames", "fps", "width", "height")), "Telemetry format does not match the video"
    assert metadata.get("fixture", "motion") == state_metadata.get("fixture", "motion"), "Telemetry belongs to a different lyric fixture"
    states = json.loads((state_from / "motion-state.json").read_text())
    assert len(states) == metadata["frames"], "Incomplete capture or mismatched telemetry"
    frames = []
    handoffs = []
    for index, state in enumerate(states):
        image = np.asarray(Image.open(capture / "motion" / f"frame-{index:05d}.png").convert("L"))
        assert image.shape == (metadata["height"], metadata["width"])
        # The synthetic fixture has a fixed #283343 background (luma 50).
        ink = np.maximum(image.astype(np.int16) - 54, 0)
        row = {}
        for word in state["words"]:
            x, y, width, height = word["rect"]
            if x < 5 or y < 38 or x + width > image.shape[1] - 5 or y + height > 722:
                continue
            left, top = int(np.floor(x)) - 4, int(np.floor(y)) - 4
            right, bottom = int(np.ceil(x + width)) + 4, int(np.ceil(y + height)) + 4
            energy = int(ink[top:bottom, left:right].sum())
            row[word["id"]] = {"energy": energy, "effect": word["effect"], "longTone": word["longTone"]}
        frames.append(row)
    failures = []
    comparisons = 0
    worst_dip = 0
    for index in range(1, len(frames) - 1):
        before, current, after = frames[index - 1:index + 2]
        for identity in before.keys() & current.keys() & after.keys():
            a, b, c = (frame[identity]["energy"] for frame in (before, current, after))
            if min(a, c) < 1000:
                continue
            comparisons += 1
            dip = max(0, 1 - b / min(a, c))
            spike = max(0, 1 - max(a, c) / max(1, b))
            worst_dip = max(worst_dip, dip)
            if before[identity]["effect"] and not current[identity]["effect"]:
                handoffs.append({"frame": index, "word": identity, "dip": dip,
                                 "longTone": current[identity]["longTone"]})
            if dip > .22 or spike > .35:
                failures.append({"frame": index, "word": identity, "ink": [a, b, c],
                                 "dip": round(dip, 5), "spike": round(spike, 5)})
    assert comparisons > 1000 and len(handoffs) >= 10, "Fixture did not exercise enough visible words/handoffs"
    assert sum(handoff["longTone"] for handoff in handoffs) >= 2, "Long-tone handoffs were not covered"
    return {"passed": not failures, "frames": len(frames), "wordFrameComparisons": comparisons,
            "worstSingleFrameDip": worst_dip, "handoffs": handoffs, "failures": failures,
            "limits": "One-frame loss/spike in tracked word ink; not a proof of all visual correctness."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--state-from", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = check(args.capture, args.state_from or args.capture)
    report = args.report or args.capture / "continuity.json"
    report.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: value for key, value in result.items() if key not in ("handoffs", "failures")}, ensure_ascii=False))
    print(f"Handoffs: {len(result['handoffs'])}; failures: {len(result['failures'])}; report: {report}")
    raise SystemExit(0 if result["passed"] else 1)
