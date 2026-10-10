#!/usr/bin/env python3
"""Check Bridge/Dock translation units against an alternate KWin header tree.

Uses compiler options from an already configured Ninja build. This checks C++
API compatibility; it does not link against or run the alternate KWin version.
Generated KWin headers and Qt/KF dependencies come from the installed SDK.
"""

import argparse
import pathlib
import re
import shlex
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", required=True, type=pathlib.Path)
    parser.add_argument("--kwin-headers", required=True, type=pathlib.Path,
                        help="KWin source src/ directory or installed include/kwin")
    args = parser.parse_args()
    build = args.build_dir.resolve()
    headers = args.kwin_headers.resolve()
    effect = (headers / "effect/effect.h").read_text()
    timed = bool(re.search(r"prePaintWindow\([^;]*std::chrono::milliseconds", effect))
    commands = subprocess.check_output(
        ["ninja", "-C", str(build), "-t", "commands",
         "kos_bridge", "kos_dock_window_animation"], text=True).splitlines()
    count = 0
    for command in commands:
        tokens = shlex.split(command)
        if "-c" not in tokens:
            continue
        source = tokens[tokens.index("-c") + 1]
        if "mocs_compilation.cpp" in source:
            continue
        options = []
        index = 0
        while index < len(tokens):
            token = tokens[index]
            if token in ("-o", "-MF", "-MT"):
                index += 2
                continue
            if token not in ("-c", "-MD", "-DKOS_KWIN_PAINT_TIME_API"):
                options.append(token)
            index += 1
        extra = ["-I" + str(headers), "-fsyntax-only"]
        if timed:
            extra.append("-DKOS_KWIN_PAINT_TIME_API")
        options[1:1] = extra
        print(source, flush=True)
        subprocess.run(options, cwd=build, check=True)
        count += 1
    if not count:
        raise SystemExit("No translation units found; configure the plugin targets first")
    print(f"Passed: {count} translation units; timed paint API: {timed}")


if __name__ == "__main__":
    main()
