"""Check resource snapshots from the native immersive performance probe."""
import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("objects", type=Path)
    parser.add_argument("--stage", default="monet-frozen")
    args = parser.parse_args()
    rows = json.loads(args.objects.read_text(encoding="utf-8"))
    assert rows[-1]["label"] == "finished", "Incomplete native run"
    row = next(r for r in rows if r["stage"] == args.stage and r["label"] == "end")
    assert row["frameCount"] > 1, "Scene did not render"
    counts = row["scopes"]["immersive"]
    assert counts["texts"] > 10 and counts["enabledLayers"] > 0, "Missing lyric/effect scene"
    redundant = counts.get("zeroContributionBlur", 0)
    print(f"{args.stage}: rendered={row['frameCount']}, "
          f"layers={counts['enabledLayers']}, zero-contribution blur={redundant}")
    assert redundant == 0, "Settled sharp glyphs still retain blur effects"


if __name__ == "__main__":
    main()
