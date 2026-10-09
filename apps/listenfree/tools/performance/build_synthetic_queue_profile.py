"""Create an isolated, deterministic restored queue for full-app memory A/B."""

import argparse
import json
import sqlite3
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--count", type=int, default=20000)
    args = parser.parse_args()
    if args.count < 1:
        parser.error("--count must be positive")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        parser.error("output already exists")

    with sqlite3.connect(args.source.resolve().as_uri() + "?mode=ro", uri=True) as source:
        with sqlite3.connect(args.output) as target:
            source.backup(target)
            items = [
                {
                    "trackId": f"queue-{index:06d}",
                    "title": f"Queue Track {index:06d}",
                    "artist": f"Queue Artist {index % 97:02d}",
                    "album": f"Queue Album {index % 313:03d}",
                    "durationMs": 180000,
                    "remoteUrl": f"https://invalid.example/queue/{index:06d}",
                    "source": "Online",
                }
                for index in range(args.count)
            ]
            state = {"position": 0, "items": items, "index": 0, "mode": "listLoop"}
            target.execute(
                "INSERT INTO settings(key,value,value_type) VALUES('portable.queue',?,'string') "
                "ON CONFLICT(key) DO UPDATE SET value=excluded.value,value_type=excluded.value_type",
                (json.dumps(state, separators=(",", ":"), ensure_ascii=False),),
            )
    print(args.output.resolve())


if __name__ == "__main__":
    main()
