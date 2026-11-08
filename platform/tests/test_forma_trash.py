#!/usr/bin/env python3
"""VM/CI-only KIO launch regression with fake apps and isolated XDG roots."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

FINDER_ID = "io.github.egely1337.Mayonnaise.Finder.desktop"
SCREENSHOT_ID = "io.github.skjsbsnq.Forma.Screenshot.desktop"


def main():
    binary, sycoca = map(os.path.abspath, sys.argv[1:3])
    with tempfile.TemporaryDirectory(prefix="kos-forma-trash-") as temporary:
        root = Path(temporary)
        for name in ("config", "data/applications", "state", "cache", "runtime", "bin"):
            (root / name).mkdir(parents=True, exist_ok=True)
        (root / "runtime").chmod(0o700)
        log = root / "launches.jsonl"
        fake_app = """#!/usr/bin/env python3
import json, os, sys
with open(os.environ['KOS_FORMATEST_LOG'], 'a', encoding='utf-8') as out:
    out.write(json.dumps({'app': os.path.basename(sys.argv[0]), 'args': sys.argv[1:]}) + '\\n')
"""
        for name in ("fake-finder", "fake-screenshot", "dolphin"):
            executable = root / "bin" / name
            executable.write_text(fake_app, encoding="utf-8")
            executable.chmod(0o700)
        for desktop_id, name, argument in ((FINDER_ID, "fake-finder", "%f"),
                                           (SCREENSHOT_ID, "fake-screenshot", "--region")):
            (root / "data/applications" / desktop_id).write_text(
                "[Desktop Entry]\nType=Application\nName=Fake Forma\n"
                f"Exec={root / 'bin' / name} {argument}\n"
                "MimeType=inode/directory;\n", encoding="utf-8")
        # The pre-existing default is Finder: disabling the opt-in integration
        # must still open its native Trash, not force an absent Dolphin.
        (root / "config/mimeapps.list").write_text(
            f"[Default Applications]\ninode/directory={FINDER_ID};\n", encoding="utf-8")
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                   XDG_CONFIG_HOME=str(root / "config"), XDG_DATA_HOME=str(root / "data"),
                   XDG_CACHE_HOME=str(root / "cache"), XDG_STATE_HOME=str(root / "state"),
                   XDG_RUNTIME_DIR=str(root / "runtime"), KOS_FORMATEST_LOG=str(log),
                   PATH=str(root / "bin") + os.pathsep + os.environ.get("PATH", ""))
        subprocess.run(["dbus-run-session", "--", sycoca, "--noincremental"], env=env,
                       check=True, timeout=20, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        output = root / "daemon.log"
        with output.open("w") as stream:
            proc = subprocess.Popen(["dbus-run-session", "--", binary, "daemon"], env=env,
                                    stdout=stream, stderr=subprocess.STDOUT)
            try:
                path = root / "runtime/kos-platform.sock"
                deadline = time.monotonic() + 15
                while not path.exists():
                    if proc.poll() is not None or time.monotonic() >= deadline:
                        raise AssertionError("daemon did not start: " + output.read_text())
                    time.sleep(0.05)

                def request(operation, payload=None):
                    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
                        connection.settimeout(10)
                        connection.connect(str(path))
                        connection.sendall((json.dumps({"version": 1, "requestId": operation,
                            "operation": operation, "payload": payload or {}}) + "\n").encode())
                        with connection.makefile("rb") as reply:
                            return json.loads(reply.readline())

                def launches(count):
                    deadline = time.monotonic() + 5
                    while time.monotonic() < deadline:
                        records = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
                        if len(records) >= count:
                            return records
                        time.sleep(0.05)
                    raise AssertionError("fake application did not start: " + output.read_text())

                enabled = request("integration.forma.set", {"enabled": True})
                assert enabled["ok"] and enabled["result"]["enabled"], enabled
                assert not enabled["result"].get("error"), enabled
                assert request("file.open-trash")["ok"]
                trash = root / "data/Trash/files"
                assert trash.is_dir(), "an empty native Trash must be prepared"
                assert launches(1)[0] == {"app": "fake-finder", "args": [str(trash)]}

                assert request("screenshot.capture")["ok"]
                assert launches(2)[1] == {"app": "fake-screenshot", "args": ["--region"]}
                disabled = request("integration.forma.set", {"enabled": False})
                assert disabled["ok"] and not disabled["result"]["enabled"], disabled
                assert request("file.open-trash")["ok"]
                assert launches(3)[2] == {"app": "fake-finder", "args": [str(trash)]}

                trash.rmdir()
                escape = root / "outside-trash"
                escape.mkdir()
                trash.symlink_to(escape, target_is_directory=True)
                refused = request("file.open-trash")
                assert not refused["ok"] and refused["error"]["code"] == "trash-unavailable", refused
                assert len(log.read_text().splitlines()) == 3, "refused paths must not launch an app"
                print("Forma native Trash: local argv, empty directory, default-manager routing and symlink rejection passed")
            finally:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=5)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
