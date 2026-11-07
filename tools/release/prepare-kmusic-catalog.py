#!/usr/bin/env python3
"""Pin a reviewed, published KMusic revision. Does not execute downloaded code."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
from urllib.request import urlopen

FILES = ("install.sh", "packaging/installer.py")
MAX_BYTES = 1024 * 1024


def release(revision, fetch=None):
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Use a reviewed, full 40-character lowercase commit SHA.")
    if fetch is None:
        def fetch(url):
            with urlopen(url, timeout=30) as response:
                if not response.url.startswith("https://raw.githubusercontent.com/"):
                    raise ValueError("Unexpected download origin")
                return response.read(MAX_BYTES + 1)
    hashes = {}
    for name in FILES:
        data = fetch(f"https://raw.githubusercontent.com/NextKde/KMusic/{revision}/{name}")
        if not data or len(data) > MAX_BYTES:
            raise ValueError(f"Invalid installer size: {name}")
        hashes[name] = hashlib.sha256(data).hexdigest()
    return {"revision": revision, "sha256": hashes}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("revision", help="Reviewed commit containing both installer files")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[2]
                        / "apps/settings/app-store/catalog.json")
    args = parser.parse_args()
    # Finish every download before touching the currently approved catalogue.
    pinned = release(args.revision)
    document = {"schemaVersion": 1, "kmusic": {"appId": "org.nextkde.KMusic",
                "repository": "https://github.com/NextKde/KMusic", "release": pinned}}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    name = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=args.output.parent,
                                         delete=False) as stream:
            name = stream.name
            json.dump(document, stream, indent=2)
            stream.write("\n")
        os.replace(name, args.output)
    finally:
        if name and os.path.exists(name):
            os.unlink(name)
    print(f"Prepared {args.output}; review the diff before publishing.")


if __name__ == "__main__":
    main()
