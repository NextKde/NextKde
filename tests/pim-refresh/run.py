#!/usr/bin/env python3
"""Exercise the real PIM adapter using isolated, in-memory application records."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[2]

with tempfile.TemporaryDirectory(prefix="kos-pim-refresh-") as directory:
    root = Path(directory)
    for name in ["desktop", "Kos", "shared"]:
        (root / name).symlink_to(REPO / "shell" / name, target_is_directory=True)
    shutil.copy(Path(__file__).with_name("shell.qml"), root / "shell.qml")
    env = dict(os.environ, XDG_CONFIG_HOME=str(root / "config"),
               XDG_STATE_HOME=str(root / "state"),
               KOS_PLATFORM_SOCKET=str(root / "absent-platform.sock"),
               KOS_DATA_SOCKET=str(root / "absent-data.sock"))
    executable = sys.argv[1] if len(sys.argv) > 1 else "quickshell"
    result = subprocess.run([executable, "--path", str(root), "--no-color"],
                            env=env, capture_output=True, text=True, timeout=15)
    output = result.stdout + result.stderr
    print(output, end="")
    assert result.returncode == 0, result.returncode
    assert "PIM_REFRESH_PASS" in output
    assert not re.search(r"PIM_REFRESH_FAIL|ReferenceError|TypeError|Cannot assign|Unable to assign", output)
