"""Write a repeatable full-app catalog browsing and idle-memory case."""

import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    config = {
        "runtime": str(args.runtime.resolve()),
        "profile": str(args.profile.resolve()),
        "report": str(output.parent / "objects.json"),
        "width": 1066,
        "height": 709,
        "renderLoop": "threaded",
        "renderReadbackMs": 0,
        "foreground": True,
        "requireUnlocked": True,
        "inspectObjects": False,
        "steps": [
            {"name": "setup", "action": "setup", "ms": 30000},
            {"name": "songs-idle", "action": "noop", "ms": 16000},
            {
                "name": "songs-filtered",
                "action": "noop",
                "ms": 21000,
                "mutations": [
                    {"name": "globalSearchInput", "property": "text", "value": "Track"}
                ],
            },
            {
                "name": "albums-filtered",
                "action": "route",
                "value": "library/albums",
                "ms": 18000,
                "mutations": [
                    {"name": "globalSearchInput", "property": "text", "value": "Album"}
                ],
            },
            {
                "name": "artists-filtered",
                "action": "route",
                "value": "library/artists",
                "ms": 18000,
                "mutations": [
                    {"name": "globalSearchInput", "property": "text", "value": "Artist"}
                ],
            },
            {
                "name": "songs-clear",
                "action": "route",
                "value": "library/songs",
                "ms": 18000,
                "mutations": [
                    {"name": "globalSearchInput", "property": "text", "value": ""}
                ],
            },
            {"name": "idle-settle", "action": "noop", "ms": 18000},
        ],
    }
    output.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8")
    print(output)


if __name__ == "__main__":
    main()
