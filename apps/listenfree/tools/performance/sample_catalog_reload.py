"""Sample an isolated Qt catalog reload benchmark on Windows.

The JSON file written by the Qt test is authoritative for GUI latency. This
wrapper measures the test process only; it does not open the user's library.
PWS and USS use the same QueryWorkingSet reader as measure.py.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import tempfile
import threading
import time


PHASE_MARKER = re.compile(r"LF_BENCH_PHASE\|([A-Za-z]+_(?:start|end))\|(\d+)")
MEMORY_KEYS = ("pwsMiB", "ussMiB", "privateCommitMiB")


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", required=True, type=Path, help="Portable test executable")
    parser.add_argument("--rows", required=True, type=int, help="Synthetic catalog size")
    parser.add_argument("--report", required=True, type=Path, help="JSON output path")
    parser.add_argument("--warm", action="store_true", help="Measure one metadata-only reload after initial load")
    parser.add_argument("--qt-bin", type=Path, help="Prepend this Qt bin directory to PATH")
    parser.add_argument("--qmmp-plugin-root", type=Path, help="Set QMMP_PLUGINS")
    parser.add_argument("--sample-ms", type=int, default=40, help="Sampling period, 20–50 ms (default: 40)")
    parser.add_argument("--timeout-seconds", type=int, default=180, help="Whole-test timeout (default: 180)")
    args = parser.parse_args()
    if args.rows <= 0:
        parser.error("--rows must be positive")
    if not 20 <= args.sample_ms <= 50:
        parser.error("--sample-ms must be between 20 and 50")
    if args.timeout_seconds <= 0:
        parser.error("--timeout-seconds must be positive")
    if not args.exe.is_file():
        parser.error(f"test executable does not exist: {args.exe}")
    if args.qt_bin is not None and not args.qt_bin.is_dir():
        parser.error(f"Qt bin directory does not exist: {args.qt_bin}")
    if args.qmmp_plugin_root is not None and not args.qmmp_plugin_root.is_dir():
        parser.error(f"Qmmp plugin root does not exist: {args.qmmp_plugin_root}")
    return args


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def memory_summary(samples: list[dict[str, float]], interval_ms: int) -> dict:
    intervals = [1000 * (right["seconds"] - left["seconds"])
                 for left, right in zip(samples, samples[1:])]
    sorted_intervals = sorted(intervals)
    result = {
        "unit": "MiB",
        "sampleCount": len(samples),
        "requestedIntervalMs": interval_ms,
        "actualMedianIntervalMs": round(statistics.median(intervals), 2) if intervals else None,
        "actualP95IntervalMs": round(sorted_intervals[int((len(sorted_intervals) - 1) * 0.95)], 2)
        if intervals else None,
        "actualMaxIntervalMs": round(max(intervals), 2) if intervals else None,
        "pwsMiB": None,
        "ussMiB": None,
        "privateCommitMiB": None,
    }
    for key in MEMORY_KEYS:
        if samples:
            result[key] = {
                "minimum": round(min(sample[key] for sample in samples), 3),
                "median": round(statistics.median(sample[key] for sample in samples), 3),
                "peak": round(max(sample[key] for sample in samples), 3),
                "final": round(samples[-1][key], 3),
            }
    return result


def read_test_output(stream, output, markers: list[dict], errors: list[str]) -> None:
    """Drain stdout continuously so Qt cannot block behind the pipe buffer."""
    try:
        for raw in iter(stream.readline, b""):
            output.write(raw)
            line = raw.decode("utf-8", errors="replace")
            match = PHASE_MARKER.search(line)
            if match:
                marker = {
                    "name": match.group(1),
                    "epochNs": int(match.group(2)),
                    "observedEpochNs": time.time_ns(),
                }
                marker["outputLagMs"] = round(
                    (marker["observedEpochNs"] - marker["epochNs"]) / 1_000_000, 3)
                markers.append(marker)
                print(f"LF_BENCH_PHASE|{marker['name']}|{marker['epochNs']}", flush=True)
    except OSError as exc:
        errors.append(type(exc).__name__)


def phase_statistics(markers: list[dict], samples: list[dict], interval_ms: int,
                     warm: bool) -> tuple[dict, dict, str | None]:
    names = ["fixture", "preSteady", "cold", "coldValidation"]
    if warm:
        names += ["warm", "warmValidation"]
    names += ["postSteady"]
    expected = [f"{name}_{edge}" for name in names for edge in ("start", "end")]
    actual = [marker["name"] for marker in markers]
    if actual != expected:
        return {}, {}, f"Incomplete or out-of-order phase markers: expected {expected}, got {actual}"
    if any(left["epochNs"] > right["epochNs"] for left, right in zip(markers, markers[1:])):
        return {}, {}, "Phase timestamps are out of order"
    result = {}
    for index, name in enumerate(names):
        start, end = markers[2 * index:2 * index + 2]
        selected = [sample for sample in samples
                    if start["epochNs"] <= sample["epochNs"] < end["epochNs"]]
        result[name] = {
            "startEpochNs": start["epochNs"],
            "endEpochNs": end["epochNs"],
            "durationMs": round((end["epochNs"] - start["epochNs"]) / 1_000_000, 3),
            "memory": memory_summary(selected, interval_ms),
        }
    before = result["preSteady"]["memory"]
    after = result["postSteady"]["memory"]
    steady = {
        "preSampleCount": before["sampleCount"],
        "postSampleCount": after["sampleCount"],
        "medianMiB": {},
        "postMinusPreMedianMiB": {},
    }
    for key in MEMORY_KEYS:
        pre = before[key]["median"] if before[key] else None
        post = after[key]["median"] if after[key] else None
        steady["medianMiB"][key] = {"pre": pre, "post": post}
        steady["postMinusPreMedianMiB"][key] = round(post - pre, 3) if pre is not None and post is not None else None
    if before["sampleCount"] < 5 or after["sampleCount"] < 5:
        return result, steady, "Too few steady samples for a reliable pre/post median"
    return result, steady, None


def main() -> int:
    args = arguments()
    if sys.platform != "win32":
        print("This sampler requires Windows QueryWorkingSet and Private Commit.", file=sys.stderr)
        return 2
    try:
        import psutil
    except ImportError:
        print("psutil is required for Private Commit sampling; install psutil before running.", file=sys.stderr)
        return 2
    from windows_memory import footprint

    exe = args.exe.resolve()
    report_path = args.report.resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report = {
        "schemaVersion": 2,
        "benchmark": "catalogReloadGuiLatencyBenchmark",
        "args": {
            "executableName": exe.name,
            "rows": args.rows,
            "warm": args.warm,
            "sampleMs": args.sample_ms,
            "timeoutSeconds": args.timeout_seconds,
            "qtBinProvided": args.qt_bin is not None,
            "qmmpPluginRootProvided": args.qmmp_plugin_root is not None,
        },
        "executableSha256": sha256_file(exe),
        "samplingScope": "benchmark process only",
        "pwsDefinition": "QueryWorkingSet pages with Shared=0; USS includes shareable pages with ShareCount<=1",
        "exitCode": None,
        "timedOut": False,
        "wallMs": None,
        "memory": memory_summary([], args.sample_ms),
        "samples": [],
        "phaseMarkers": [],
        "phases": {},
        "steadyState": {},
        "instrumentationLimits": [
            "Actual SQL query count and hydrated domain-track count require hooks inside the reload worker; "
            "the benchmark validates every projected published row instead."
        ],
        "testReport": None,
        "error": None,
    }
    env = os.environ.copy()
    env["LISTENFREE_CATALOG_BENCH_ROWS"] = str(args.rows)
    if args.warm:
        env["LISTENFREE_CATALOG_BENCH_WARM"] = "1"
    else:
        env.pop("LISTENFREE_CATALOG_BENCH_WARM", None)
    if args.qt_bin is not None:
        env["PATH"] = str(args.qt_bin.resolve()) + os.pathsep + env.get("PATH", "")
    if args.qmmp_plugin_root is not None:
        env["QMMP_PLUGINS"] = str(args.qmmp_plugin_root.resolve())

    samples: list[dict[str, float]] = []
    markers: list[dict] = []
    reader_errors: list[str] = []
    started = time.perf_counter()
    try:
        with tempfile.TemporaryDirectory(prefix="listenfree-catalog-bench-") as scratch:
            test_path = Path(scratch) / "test-report.json"
            env["LISTENFREE_CATALOG_BENCH_REPORT"] = str(test_path)
            output_path = Path(scratch) / "test-output.log"
            with output_path.open("wb") as output:
                process = subprocess.Popen(
                    [str(exe), "catalogReloadGuiLatencyBenchmark", "-o", "-,txt"],
                    cwd=exe.parent,
                    env=env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    creationflags=subprocess.CREATE_NO_WINDOW,
                )
                assert process.stdout is not None
                reader = threading.Thread(target=read_test_output,
                                          args=(process.stdout, output, markers, reader_errors), daemon=True)
                reader.start()
                sampled_process = psutil.Process(process.pid)
                next_sample = time.perf_counter()
                deadline = started + args.timeout_seconds
                while process.poll() is None:
                    now = time.perf_counter()
                    if now >= deadline:
                        report["timedOut"] = True
                        process.kill()
                        break
                    if now < next_sample:
                        time.sleep(min(next_sample - now, deadline - now))
                        continue
                    try:
                        sample_start_ns = time.time_ns()
                        # Windows psutil's private field is process Private Commit.
                        commit = sampled_process.memory_info().private / 1048576
                        native = footprint(process.pid)
                        sample_end_ns = time.time_ns()
                        samples.append({
                            "seconds": round(now - started, 6),
                            "epochNs": (sample_start_ns + sample_end_ns) // 2,
                            "sampleDurationMs": round((sample_end_ns - sample_start_ns) / 1_000_000, 3),
                            "pwsMiB": native["pwsMiB"],
                            "ussMiB": native["ussMiB"],
                            "privateCommitMiB": commit,
                        })
                    except (psutil.NoSuchProcess, psutil.AccessDenied, OSError) as exc:
                        # Windows can deny QueryWorkingSet after the process
                        # has begun exiting but before Popen.poll notices it.
                        try:
                            process.wait(timeout=0.1)
                        except subprocess.TimeoutExpired:
                            report["error"] = f"Memory sampling failed: {type(exc).__name__}"
                            process.kill()
                        break
                    next_sample = max(next_sample + args.sample_ms / 1000, time.perf_counter())
                report["exitCode"] = process.wait()
                reader.join(timeout=5)
                if reader.is_alive() and report["error"] is None:
                    report["error"] = "Qt output reader did not finish"
                process.stdout.close()
            if reader_errors and report["error"] is None:
                report["error"] = f"Qt output reader failed: {reader_errors[0]}"
            if test_path.is_file():
                report["testReport"] = json.loads(test_path.read_text(encoding="utf-8"))
            elif not report["timedOut"] and report["error"] is None:
                report["error"] = "Qt test did not write its benchmark JSON report"
            if report["exitCode"] != 0:
                report["testOutputTail"] = output_path.read_bytes()[-8000:].decode("utf-8", errors="replace")
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        # Error strings from OS APIs can contain private absolute paths.
        report["error"] = f"Benchmark execution failed: {type(exc).__name__}"
    finally:
        report["wallMs"] = round((time.perf_counter() - started) * 1000, 2)
        report["memory"] = memory_summary(samples, args.sample_ms)
        report["samples"] = samples
        report["phaseMarkers"] = markers
        report["phases"], report["steadyState"], phase_error = phase_statistics(
            markers, samples, args.sample_ms, args.warm)
        if phase_error and report["error"] is None:
            report["error"] = phase_error
        test_report = report["testReport"]
        if test_report is not None and (
            not isinstance(test_report, dict)
            or test_report.get("rows") != args.rows
            or not isinstance(test_report.get("loadMs"), (int, float))
            or not isinstance(test_report.get("maxGuiGapMs"), (int, float))
        ):
            report["error"] = "Qt benchmark JSON is missing expected rows, loadMs, or maxGuiGapMs"
        if args.warm and test_report is not None and (
            not isinstance(test_report, dict)
            or not isinstance(test_report.get("warmReloadMs"), (int, float))
            or not isinstance(test_report.get("warmMaxGuiGapMs"), (int, float))
            or not isinstance(test_report.get("warmModelResets"), int)
        ):
            report["error"] = "Qt benchmark JSON is missing warm reload metrics"
        if not samples and report["error"] is None:
            report["error"] = "Process exited before a memory sample could be taken"
        if report["exitCode"] not in (None, 0) and report["error"] is None:
            report["error"] = "Qt benchmark process failed"
        report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"report": str(report_path), "exitCode": report["exitCode"],
                      "error": report["error"]}, ensure_ascii=False))
    return 0 if report["exitCode"] == 0 and report["error"] is None else 1


if __name__ == "__main__":
    raise SystemExit(main())
