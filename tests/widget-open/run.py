#!/usr/bin/env python3
"""Exercise the real widget singleton against an isolated platform socket."""
import json
import os
from pathlib import Path
import re
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
import time

REPO = Path(__file__).resolve().parents[2]
READY = {"state": "ready", "installed": True, "sourceToken": "a" * 64}
CASES = [
    ("cached-unavailable", {"state": "unavailable"}, READY, "application.widget-open"),
    ("cached-absent", {"state": "not-installed"}, READY, "application.widget-open"),
    ("cached-conflict", {"state": "ambiguous"}, READY, "application.widget-open"),
    ("cached-loading", {"state": "loading"}, READY, "application.widget-open"),
    ("confirmed-absent", {"state": "not-installed"}, {"state": "not-installed"}, "settings.launch"),
    ("confirmed-conflict", {"state": "ambiguous"}, {"state": "ambiguous"}, "settings.launch"),
    ("still-unavailable", {"state": "unavailable"}, {"state": "unavailable"}, None),
    ("query-timeout", {"state": "unavailable"}, None, None),
    ("already-ready", READY, READY, "application.widget-open"),
    ("in-flight-poll", {"state": "unavailable"}, READY, "application.widget-open"),
]


class Platform(socketserver.StreamRequestHandler):
    def handle(self):
        for line in self.rfile:
            request = json.loads(line)
            op = request["operation"]
            reply = {"version": 1, "requestId": request["requestId"], "ok": True, "result": {}}
            if op == "test.begin":
                self.server.started = True
            elif op == "application.widget-snapshot":
                if self.server.started:
                    time.sleep(0.04)
                fresh = self.server.fresh if self.server.started else READY
                if fresh is None:
                    reply.update(ok=False, error={"code": "widget-query-timeout", "message": "Timed out"})
                else:
                    reply["result"] = fresh
            if self.server.started and op != "test.begin":
                self.server.requests.append(request)
            self.wfile.write((json.dumps(reply) + "\n").encode())
            self.wfile.flush()


class Server(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True


with tempfile.TemporaryDirectory(prefix="kos-widget-open-") as directory:
    root = Path(directory)
    for name in ["desktop", "Kos", "shared"]:
        (root / name).symlink_to(REPO / "shell" / name, target_is_directory=True)
    shutil.copy(Path(__file__).with_name("shell.qml"), root / "shell.qml")
    executable = sys.argv[1] if len(sys.argv) > 1 else "quickshell"
    for name, cached, fresh, expected in CASES:
        with Server(str(root / "platform.sock"), Platform) as server:
            server.started, server.fresh, server.requests = False, fresh, []
            threading.Thread(target=server.serve_forever, daemon=True).start()
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       XDG_CONFIG_HOME=str(root / "config"), XDG_STATE_HOME=str(root / "state"),
                       KOS_PLATFORM_SOCKET=str(root / "platform.sock"),
                       KOS_DATA_SOCKET=str(root / "absent-data.sock"),
                       WIDGET_CACHED_STATE=json.dumps(cached),
                       WIDGET_IN_FLIGHT_POLL="1" if name == "in-flight-poll" else "0")
            result = subprocess.run([executable, "--path", str(root), "--no-color"],
                                    env=env, capture_output=True, text=True, timeout=10)
            server.shutdown()
        (root / "platform.sock").unlink()
        output = result.stdout + result.stderr
        assert result.returncode == 0, (name, output)
        assert not re.search(r"ReferenceError|TypeError|Binding loop", output), (name, output)
        match = re.search(r"WIDGET_OPEN_RESULT (\{[^\n]+\})", output)
        assert match, (name, output)
        observed = json.loads(match[1])
        actions = [r for r in server.requests if r["operation"] in ("settings.launch", "application.widget-open")]
        assert [r["operation"] for r in actions] == ([expected] if expected else []), (name, observed, server.requests, output)
        assert not observed["busy"], (name, observed)
        if expected == "application.widget-open":
            options = actions[0]["payload"]["options"]
            assert options == ({"location": "old-location"} if name == "already-ready" else {}), (name, options)
        if expected is None:
            assert observed["error"], (name, observed)
        else:
            assert not observed["error"], (name, observed)
        if name != "already-ready":
            assert server.requests[0]["operation"] == "application.widget-snapshot", (name, server.requests)
        if name == "in-flight-poll":
            before_open = server.requests[:server.requests.index(actions[0])]
            assert len(before_open) == 2, (name, server.requests)
        print("PASS", name)
