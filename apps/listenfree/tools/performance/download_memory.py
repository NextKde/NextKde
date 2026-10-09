"""Isolated real DownloadService benchmark with synthetic history and loopback I/O.
The external HTTP fixture is not part of the measured application process tree.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("mode", choices=["prepare", "run", "visual", "verify"])
parser.add_argument("--output", type=Path, default=ROOT / "build/download-memory-20260927")
parser.add_argument("--profile", type=Path, default=ROOT / "build/catalog-steady-ab/profile-1k.sqlite")
parser.add_argument("--sizes", nargs="+", type=int, default=[100, 5000])
parser.add_argument("--rounds", type=int, default=3)
parser.add_argument("--start-round", type=int, default=1,
                    help="First output round number, for repeating rejected runs without replacing earlier rounds")
parser.add_argument("--versions", nargs="+", default=["before", "after"])
args = parser.parse_args()
base = args.output.resolve()
base.mkdir(parents=True, exist_ok=True)

def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")

def verify_window_conditions(folder):
    summary = json.loads((folder / "summary.json").read_text(encoding="utf-8"))
    if not summary["finished"] or summary["exit"] != 0:
        raise RuntimeError(f"{folder.name}: application did not finish successfully")
    case = json.loads((folder / "case.json").read_text(encoding="utf-8"))
    ends = [row for row in json.loads((folder / "objects.json").read_text(encoding="utf-8"))
            if row["label"] == "end"]
    if [row["stage"] for row in ends] != [step["name"] for step in case["steps"]]:
        raise RuntimeError(f"{folder.name}: incomplete stages")
    samples = [json.loads(line) for line in (folder / "samples.jsonl").read_text(encoding="utf-8").splitlines()]
    for end in ends:
        stage = end["stage"]
        rows = [row for row in samples if row["stage"] == stage]
        tail = [row for row in rows if row["seconds"] >= rows[-1]["seconds"] - 5] if rows else []
        if len(tail) < 7 or not all(row["ownForeground"] and row["sessionLocked"] is False for row in tail):
            raise RuntimeError(f"{folder.name}/{stage}: insufficient unlocked foreground samples; preserve and repeat the pair")
        interactive = stage in {"cold-idle", "download-open", "download-scroll", "download-closed", "download-reopen", "download-cleared"}
        if not end["windowVisible"] or not end["windowExposed"] or (interactive and end["frameCount"] <= 0):
            raise RuntimeError(f"{folder.name}/{stage}: window did not render the interaction; preserve and repeat the pair")

if args.mode == "verify":
    for count in args.sizes:
        for number in range(args.start_round, args.start_round + args.rounds):
            for version in args.versions:
                folder = base / f"{version}-{count}-{number}"
                verify_window_conditions(folder)
                print(folder.name, "window/exit checks passed", flush=True)
    sys.exit(0)

if args.mode == "prepare":
    for count in args.sizes:
        rows = [{"id": f"history-{i}", "state": "completed", "title": f"历史下载 {i + 1}",
                 "artist": f"艺术家 {i % 40}", "artwork": "", "quality": "128k",
                 "received": 4000000, "total": 4000000, "created": 1700000000000 - i,
                 "track": {"trackId": f"kw:history-{i}", "rid": str(1000 + i), "source": "kw",
                           "title": f"历史下载 {i + 1}", "artist": f"艺术家 {i % 40}",
                           "album": f"专辑 {i // 10}", "durationMs": 240000}}
                for i in range(count)]
        with sqlite3.connect(args.profile.resolve().as_uri() + "?mode=ro", uri=True) as source:
            with sqlite3.connect(base / f"profile-{count}.sqlite") as target:
                source.backup(target)
                values = {"downloads.v1": json.dumps(rows, ensure_ascii=False),
                          "source.custom": "[]", "source.activeId": "", "portable.queue": "{}",
                          "download.maxConcurrent": "1", "download.lyrics.externalFile": "false"}
                for key, value in values.items():
                    target.execute("INSERT INTO settings(key,value,value_type) VALUES(?,?,'string') "
                                   "ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, value))
        print("prepared", count, flush=True)
    sys.exit(0)

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *unused):
        pass

    def do_GET(self):
        total = 512 * 1024 * 1024
        match = re.match(r"bytes=(\d+)-", self.headers.get("Range", ""))
        offset = int(match.group(1)) if match else 0
        self.send_response(206 if offset else 200)
        self.send_header("Content-Type", "audio/mpeg")
        self.send_header("Content-Length", str(total - offset))
        self.send_header("ETag", '"download-audit-v1"')
        self.send_header("Connection", "close")
        if offset:
            self.send_header("Content-Range", f"bytes {offset}-{total-1}/{total}")
        self.end_headers()
        # Bounded chunks, no complete audio allocation. Paused before finalizing.
        try:
            while offset < total:
                chunk = b"\0" * min(8192, total - offset)
                self.wfile.write(chunk)
                self.wfile.flush()
                offset += len(chunk)
                time.sleep(0.0625)
        except (ConnectionError, OSError):
            pass

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
script = base / "fixture-source.js"
script.write_text("lx.on(lx.EVENT_NAMES.request, () => Promise.resolve('http://127.0.0.1:"
                  + str(server.server_port) + "/audit.mp3'));"
                  "lx.send(lx.EVENT_NAMES.inited,{status:true,sources:{kw:{type:'music',"
                  "actions:['musicUrl'],qualitys:['128k']}}});", encoding="utf-8")
try:
    for count in args.sizes:
        for number in range(args.start_round, args.start_round + args.rounds):
            for version in args.versions:
                name = f"{version}-{count}-{number}" if args.mode == "run" else f"{version}-visual-{count}"
                folder = base / name
                steps = [dict(name="cold-idle", action="setup", ms=15000),
                         dict(name="source-ready", action="importSource", value=str(script), ms=3000),
                         dict(name="download-hidden", action="downloadAdd", ms=8000, expectedCatalogRows=1000),
                         dict(name="download-open", action="downloadPanel", open=True, ms=8000),
                         dict(name="download-scroll", action="noop", ms=6000, mutations=[
                             dict(within="downloadPanel", name="", type="QQuickListView", property="contentY", value=1680)]),
                         dict(name="download-closed", action="downloadPanel", open=False, ms=8000),
                         dict(name="download-paused", action="downloadsPause", ms=6000),
                         dict(name="download-reopen", action="downloadPanel", open=True, ms=6000),
                         dict(name="download-cleared", action="downloadsClear", ms=6000)]
                if args.mode == "visual":
                    steps = [dict(name="cold-idle", action="setup", ms=8000),
                             dict(name="history-open", action="downloadPanel", open=True, ms=4000, capture=True),
                             dict(name="history-scroll", action="noop", ms=4000, capture=True, mutations=[
                                 dict(within="downloadPanel", name="", type="QQuickListView", property="contentY", value=1680)]),
                             dict(name="history-closed", action="downloadPanel", open=False, ms=4000, capture=True),
                             dict(name="history-reopen", action="downloadPanel", open=True, ms=4000, capture=True)]
                config = dict(profile=str(base / f"profile-{count}.sqlite"), width=1066, height=709,
                              renderLoop="threaded", renderReadbackMs=0, foreground=True, requireUnlocked=True,
                              inspectObjects=False, ignoreUserInput=True, runtime=str(base / f"{version}-runtime"),
                              report=str(folder / "objects.json"), steps=steps)
                write_json(folder / "input.json", config)
                with (folder / "run.log").open("w", encoding="utf-8") as log:
                    subprocess.run([sys.executable, str(ROOT / "tools/performance/measure.py"), str(folder / "input.json")],
                                   cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
                summary = json.loads((folder / "summary.json").read_text(encoding="utf-8"))
                assert summary["finished"] and summary["exit"] == 0, (name, summary)
                if args.mode == "run":
                    verify_window_conditions(folder)
                print(name, "completed", flush=True)
finally:
    server.shutdown()
    server.server_close()
