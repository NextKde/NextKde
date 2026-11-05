#!/usr/bin/env python3
"""Prepare (never publish) a stable standalone-app release manifest."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import urllib.parse
import urllib.request

APPS = {
    "calendar": ("kos-apps", "org.nextks.calendar"),
    "calculator": ("kos-apps", "org.nextks.calculator"),
    "weather": ("kos-apps", "org.nextks.weather"),
    "listenfree": ("ListenFree", "org.nextkde.ListenFree"),
}
MAXIMUM_ARCHIVE = 256 * 1024 * 1024


def manifest(app, version, revision, archive_digest):
    if app not in APPS:
        raise ValueError("Unknown application")
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version):
        raise ValueError("Use a stable X.Y.Z version, not a prerelease or branch")
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("A full immutable lowercase commit SHA is required")
    if not re.fullmatch(r"[0-9a-f]{64}", archive_digest):
        raise ValueError("Invalid source archive SHA-256")
    repository, app_id = APPS[app]
    return {
        "schemaVersion": 1,
        "appId": app_id,
        "version": version,
        "revision": revision,
        "archiveSha256": archive_digest,
        "archiveUrl": f"https://codeload.github.com/NextKde/{repository}/tar.gz/{revision}",
    }


def download_digest(url):
    request = urllib.request.Request(url, headers={"User-Agent": "NextKDE-app-release-preparer"})
    digest = hashlib.sha256()
    size = 0
    with urllib.request.urlopen(request, timeout=30) as response:
        parsed = urllib.parse.urlparse(response.url)
        if parsed.scheme != "https" or parsed.netloc != "codeload.github.com":
            raise ValueError("Unexpected source archive download origin")
        while chunk := response.read(128 * 1024):
            size += len(chunk)
            if size > MAXIMUM_ARCHIVE:
                raise ValueError("Source archive exceeds 256 MiB")
            digest.update(chunk)
    if not size:
        raise ValueError("Source archive is empty")
    return digest.hexdigest()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, choices=APPS)
    parser.add_argument("--version", required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    # Validate all supplied metadata before making a request or creating output.
    data = manifest(args.app, args.version, args.revision, "0" * 64)
    if args.output.exists():
        parser.error("Output already exists; inspect it before choosing a new output path")
    data["archiveSha256"] = download_digest(data["archiveUrl"])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as stream:
        json.dump(data, stream, indent=2)
        stream.write("\n")
    print(f"Prepared {args.output}; nothing was published.")
    print(f"Review this manifest and source commit for stable release v{args.version}; use the app-ID-prefixed manifest filename.")
    print("The archive hash detects corruption. GitHub repository publication permissions remain the trust boundary.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f"Release preparation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
