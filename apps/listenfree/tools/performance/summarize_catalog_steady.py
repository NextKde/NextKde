"""Validate paired full-app catalog runs and summarize stage tail medians."""

import argparse
import json
import statistics
from pathlib import Path


def load_run(directory: Path) -> tuple[dict, dict]:
    summary = json.loads((directory / "summary.json").read_text(encoding="utf-8"))
    objects = json.loads((directory / "objects.json").read_text(encoding="utf-8"))
    with (directory / "samples.jsonl").open(encoding="utf-8") as stream:
        samples = [json.loads(line) for line in stream]
    if summary["exit"] != 0 or not summary["finished"]:
        raise ValueError(f"incomplete run: {directory}")
    if not objects or not all(row["windowVisible"] and row["windowExposed"] for row in objects):
        raise ValueError(f"window was not continuously visible and exposed: {directory}")
    if not objects[-1]["catalogReady"]:
        raise ValueError(f"catalog was not ready: {directory}")
    if not samples:
        raise ValueError(f"no process samples: {directory}")
    conditions = {
        "sessionLocked": sorted({row["sessionLocked"] for row in samples}),
        "foregroundSamples": sum(row["ownForeground"] for row in samples),
        "sampleCount": len(samples),
    }
    return summary, conditions


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--rounds", type=int, default=3)
    args = parser.parse_args()
    root = args.root.resolve()
    data = {"runs": {}, "stages": {}}
    for version in ("baseline", "optimized"):
        runs = []
        for index in range(1, args.rounds + 1):
            directory = root / f"{version}-paired{'' if index == 1 else '-' + str(index)}"
            summary, conditions = load_run(directory)
            runs.append(summary)
            data["runs"][directory.name] = conditions
        data[version] = runs
    all_conditions = list(data["runs"].values())
    if any(item["sessionLocked"] != all_conditions[0]["sessionLocked"] for item in all_conditions):
        raise ValueError("session lock state differed between runs")
    stages = [row["stage"] for row in data["baseline"][0]["stages"]]
    if any([row["stage"] for row in run["stages"]] != stages
           for version in ("baseline", "optimized") for run in data[version]):
        raise ValueError("stage order differed between runs")
    for stage in stages:
        result = {}
        for version in ("baseline", "optimized"):
            rows = [next(row for row in run["stages"] if row["stage"] == stage)
                    for run in data[version]]
            result[version] = {}
            for key in ("pws_median", "commit_median", "gpu_dedicated_mib"):
                values = [row[key] for row in rows if row[key] is not None]
                result[version][key] = {
                    "median": statistics.median(values) if values else None,
                    "range": [min(values), max(values)] if values else None,
                }
        data["stages"][stage] = result
    del data["baseline"], data["optimized"]
    target = root / "catalog-steady-summary.json"
    target.write_text(json.dumps(data, indent=2), encoding="utf-8")
    print(target)


if __name__ == "__main__":
    main()
