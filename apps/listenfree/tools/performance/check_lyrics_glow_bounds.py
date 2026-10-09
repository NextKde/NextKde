"""Compare matched GPU captures with/without glow sample and quad culling.

The control must use the same kernel/parameters, a large fixed transparent
padding, and compute the halo without the mask/support early-outs. This checks
real output pixels, including halo edges and effect handoffs. Default tolerance
is 1 LSB; changed quad geometry may additionally alter ink-edge interpolation.
It does not compare the new visual tuning against the old tuning.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image


def check(control, candidate, tolerance=1):
    metadata = json.loads((control/"motion.json").read_text())
    current = json.loads((candidate/"motion.json").read_text())
    assert metadata == current, "Capture configuration mismatch"
    before = json.loads((control/"motion-state.json").read_text())
    after = json.loads((candidate/"motion-state.json").read_text())
    assert len(before) == len(after) == metadata["frames"]
    maximum = 0
    changed_pixels = 0
    over_one = 0
    over_tolerance = 0
    worst_frame = None
    for index, (a, b) in enumerate(zip(before, after)):
        assert a["positionMs"] == b["positionMs"], "Media clock mismatch"
        name = f"frame-{index:05d}.png"
        old = np.asarray(Image.open(control/"motion"/name).convert("RGB"), dtype=np.int16)
        new = np.asarray(Image.open(candidate/"motion"/name).convert("RGB"), dtype=np.int16)
        assert old.shape == new.shape == (metadata["height"], metadata["width"], 3)
        difference = np.abs(old-new).max(axis=2)
        frame_max = int(difference.max())
        if frame_max > maximum:
            maximum, worst_frame = frame_max, index
        changed_pixels += int(np.count_nonzero(difference))
        over_one += int(np.count_nonzero(difference > 1))
        over_tolerance += int(np.count_nonzero(difference > tolerance))
    return {"passed": over_tolerance == 0, "frames": metadata["frames"],
        "fixture": metadata["fixture"], "pixelsCompared": metadata["frames"]*metadata["width"]*metadata["height"],
        "maximumChannelDifference": maximum, "worstFrame": worst_frame,
        "changedPixels": changed_pixels, "pixelsBeyondOneLSB": over_one,
        "tolerance": tolerance, "pixelsBeyondTolerance": over_tolerance,
        "control": str(control), "candidate": str(candidate)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("control", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--tolerance", type=int, choices=(0, 1, 2), default=1)
    args = parser.parse_args()
    result = check(args.control, args.candidate, args.tolerance)
    (args.candidate/"glow-bounds.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result))
    raise SystemExit(0 if result["passed"] else 1)
