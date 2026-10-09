"""Build a deterministic, private-data-free SQLite catalog for app memory probes.

The template must be an empty database created by the current ListenFree app.
The output is a new file; this tool never modifies the template or user data.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sqlite3


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--rows", required=True, type=int)
    args = parser.parse_args()
    if args.rows <= 0 or args.output.exists() or not args.template.is_file():
        parser.error("rows must be positive, template must exist, and output must be new")
    args.output.parent.mkdir(parents=True, exist_ok=True)

    with sqlite3.connect(args.template) as source, sqlite3.connect(args.output) as target:
        if source.execute("SELECT COUNT(*) FROM tracks").fetchone()[0] != 0:
            parser.error("template must contain no songs")
        if source.execute("SELECT MAX(version) FROM schema_migrations").fetchone()[0] != 6:
            parser.error("template must use schema v6")
        source.backup(target)
        target.execute("PRAGMA foreign_keys=ON")
        with target:
            target.execute(
                "INSERT INTO settings(key,value,value_type) VALUES('library.metadataRelationsVersion','1','string') "
                "ON CONFLICT(key) DO UPDATE SET value='1',value_type='string'"
            )
            target.executemany(
                "INSERT INTO artists(artist_id,name) VALUES(?,?)",
                ((f"artist-{index:03d}", f"Artist {index:03d}") for index in range(60)),
            )
            target.executemany(
                "INSERT INTO albums(album_id,title,artwork_url) VALUES(?,?,NULL)",
                ((f"album-{index:03d}", f"Album {index:03d}") for index in range(300)),
            )
            for first in range(0, args.rows, 1000):
                indexes = range(first, min(first + 1000, args.rows))
                target.executemany(
                    "INSERT INTO tracks(track_id,title,duration_ms,local_path) VALUES(?,?,?,?)",
                    ((f"benchmark-{i:07d}", f"Track {i:07d}", 180000 + i % 1000,
                      f"C:/listenfree-synthetic-media/{i:07d}.flac") for i in indexes),
                )
                target.executemany(
                    "INSERT INTO track_artists(track_id,artist_id,ordinal) VALUES(?,?,0)",
                    ((f"benchmark-{i:07d}", f"artist-{i % 60:03d}") for i in indexes),
                )
                target.executemany(
                    "INSERT INTO track_albums(track_id,album_id) VALUES(?,?)",
                    ((f"benchmark-{i:07d}", f"album-{i % 300:03d}") for i in indexes),
                )
            target.execute("UPDATE catalog_state SET revision=2,reset_revision=2 WHERE singleton=1")
        count = target.execute("SELECT COUNT(*) FROM tracks").fetchone()[0]
        if count != args.rows or target.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise RuntimeError("synthetic catalog validation failed")
        print(f"{args.output.resolve()} rows={count} bytes={args.output.stat().st_size}")


if __name__ == "__main__":
    main()
