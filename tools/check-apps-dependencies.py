#!/usr/bin/env python3
"""Compatibility notice: dependency requirements belong to independent apps."""
import sys


def main():
    print("Application dependency checks moved to the independent repositories:", file=sys.stderr)
    for repo in ("kos-apps", "ListenFree"):
        print("  https://github.com/NextKde/" + repo, file=sys.stderr)
    print("Use tools/kosctl install apps --backend=source --app APP check for stable Release availability.", file=sys.stderr)
    print("This removed monorepo preflight cannot validate independent application dependencies.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
