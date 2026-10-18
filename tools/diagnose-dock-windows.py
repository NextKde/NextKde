#!/usr/bin/env python3
"""Read Dock's KWin snapshot on the affected VM without restarting anything.

Run as the desktop session user: python3 tools/diagnose-dock-windows.py
Only subscribes to the platform socket and queries KWin's script-loaded flag.
No scripts, effects, window commands, or service restarts are requested.
Window titles, application IDs, and UUIDs are omitted from the output.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import time


def script_loaded():
    if not shutil.which("gdbus"):
        return {"error": "gdbus is not installed"}
    try:
        result = subprocess.run(
            ["gdbus", "call", "--session", "--dest", "org.kde.KWin",
             "--object-path", "/Scripting", "--method",
             "org.kde.kwin.Scripting.isScriptLoaded", "kos-window-bridge"],
            capture_output=True, text=True, timeout=3, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"error": str(error)}
    if result.returncode:
        return {"error": result.stderr.strip()}
    return {"reply": result.stdout.strip()}


def read_snapshot(path, timeout):
    summary = {"connected": False, "subscribed": False, "snapshotReceived": False}
    deadline = time.monotonic() + timeout
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(timeout)
            connection.connect(path)
            summary["connected"] = True
            request = {"version": 1, "requestId": "dock-diagnostic",
                       "operation": "kwin.subscribe", "payload": {}}
            connection.sendall((json.dumps(request) + "\n").encode())
            buffer = b""
            while time.monotonic() < deadline:
                connection.settimeout(max(0.01, deadline - time.monotonic()))
                chunk = connection.recv(65536)
                if not chunk:
                    summary["connectionClosed"] = True
                    break
                buffer += chunk
                if len(buffer) > 8 * 1024 * 1024:
                    summary["error"] = "platform message exceeds diagnostic limit"
                    break
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    if not line.strip():
                        continue
                    message = json.loads(line)
                    if message.get("requestId") == "dock-diagnostic":
                        summary["subscribed"] = message.get("ok") is True
                        if not summary["subscribed"]:
                            summary["subscriptionError"] = message.get("error")
                            return summary
                    if message.get("event") == "window.snapshot":
                        windows = message.get("payload", {}).get("windows")
                        summary["snapshotReceived"] = True
                        summary["windowsIsJsonArray"] = isinstance(windows, list)
                        if isinstance(windows, list):
                            summary["windowCount"] = len(windows)
                        return summary
    except socket.timeout:
        pass
    except (OSError, ValueError) as error:
        summary["error"] = str(error)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", default=os.environ.get("KOS_PLATFORM_SOCKET")
                        or str(Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
                               / "kos-platform.sock"))
    parser.add_argument("--timeout", type=float, default=5)
    args = parser.parse_args()
    if not 0 < args.timeout <= 30:
        parser.error("--timeout must be greater than 0 and at most 30 seconds")
    report = {"kwinScript": script_loaded(),
              "platform": read_snapshot(args.socket, args.timeout)}
    platform = report["platform"]
    if not platform["connected"]:
        report["next"] = "Inspect kos-platform startup/socket errors."
    elif not platform["subscribed"]:
        report["next"] = "Inspect platform subscription errors or timeouts."
    elif not platform["snapshotReceived"]:
        report["next"] = "No cached/live snapshot: inspect KWin script evaluation and D-Bus Publish."
    elif not platform.get("windowsIsJsonArray"):
        report["next"] = "Platform snapshot has an invalid windows field."
    elif platform["windowCount"] == 0:
        report["next"] = "Snapshot is empty: inspect KWin enumeration/filtering with known open application windows."
    else:
        report["next"] = "Platform has windows: inspect WindowService event/rebuild errors and Dock model."
    report["note"] = "A received snapshot may be cached; this does not prove the script is still publishing."
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
