#!/usr/bin/env python3
"""Lease KWin's TabBox layout without changing its shortcuts or other options."""
import json
import os
from pathlib import Path
import subprocess
import sys

LAYOUT = "kos-glass"


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def configure(enabled, package, state):
    state = Path(state)
    current = run("kreadconfig6", "--file", "kwinrc", "--group", "TabBox",
                  "--key", "LayoutName", "--default", "__kos_absent__")
    saved = json.loads(state.read_text()) if state.exists() else None
    if enabled:
        destination = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "kwin/tabbox" / LAYOUT
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.is_symlink():
            if destination.resolve() != Path(package).resolve():
                destination.unlink()
                destination.symlink_to(Path(package).resolve(), target_is_directory=True)
        elif destination.exists():
            raise RuntimeError(f"Refusing to overwrite {destination}")
        else:
            destination.symlink_to(Path(package).resolve(), target_is_directory=True)
        if current != LAYOUT:
            saved = {"layout": current}
            state.parent.mkdir(parents=True, exist_ok=True)
            temporary = state.with_suffix(".tmp")
            temporary.write_text(json.dumps(saved))
            temporary.replace(state)
        elif saved is None:
            raise RuntimeError("KOS layout has no recovery record")
        value = LAYOUT
    else:
        if current != LAYOUT:
            # A later explicit choice in KDE Settings wins over our backup.
            if state.exists():
                state.unlink()
            return
        if saved is None:
            raise RuntimeError("Cannot restore KWin layout without recovery record")
        value = saved["layout"]
    command = ["kwriteconfig6", "--file", "kwinrc", "--group", "TabBox", "--key", "LayoutName"]
    command += ["--delete"] if value == "__kos_absent__" else [value]
    run(*command)
    run("qdbus6", "org.kde.KWin", "/KWin", "org.kde.KWin.reconfigure")
    if not enabled and state.exists():
        state.unlink()


if __name__ == "__main__":
    try:
        configure(sys.argv[1] == "true", sys.argv[2], sys.argv[3])
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
