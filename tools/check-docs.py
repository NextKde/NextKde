#!/usr/bin/env python3
"""Validate relative Markdown links in the repository.

The check intentionally ignores web URLs and in-document anchors.  It is a
small, dependency-free guard against documentation drift after a directory
move; it does not try to be a complete Markdown parser.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[1]
LINK_RE = re.compile(r"(?<!!)\[[^\]]*\]\(\s*(<[^>]+>|[^\s)]+)")
REMOTE_PREFIXES = (
    "https://",
    "http://",
    "mailto:",
    "tel:",
    # A few vendored Markdown files use a host without a URL scheme.
    "github.com/",
    "gitlab.com/",
)


def relative_links(path: Path) -> list[tuple[int, str]]:
    links: list[tuple[int, str]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        for match in LINK_RE.finditer(line):
            target = match.group(1).strip("<>")
            if not target or target.startswith("#") or target.startswith(REMOTE_PREFIXES):
                continue
            target = unquote(target.split("#", 1)[0].split("?", 1)[0])
            if target:
                links.append((line_number, target))
    return links


def main() -> int:
    failures: list[str] = []
    markdown_files = sorted(ROOT.rglob("*.md"))
    for markdown in markdown_files:
        for line_number, target in relative_links(markdown):
            resolved = (markdown.parent / target).resolve()
            try:
                resolved.relative_to(ROOT)
            except ValueError:
                failures.append(f"{markdown.relative_to(ROOT)}:{line_number}: outside repository: {target}")
                continue
            if not resolved.exists():
                failures.append(f"{markdown.relative_to(ROOT)}:{line_number}: missing: {target}")

    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1
    print(f"markdown links: ok ({len(markdown_files)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
