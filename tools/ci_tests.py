#!/usr/bin/env python3
"""Check required CTest registrations and account for every selected CI test."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

GROUPS = {
    "data-platform": {"data", "platform"},
    "logic": {"logic"},
    "headless": {"headless"},
    "widgets": {"widgets"},
}
ROOT = Path(__file__).resolve().parents[1]


def inventory(tests, required):
    groups = {group: [] for group in GROUPS}
    errors = []
    registered = {}
    excluded = []
    for test in tests:
        name = test["name"]
        if name in registered:
            errors.append(f"Duplicate test registration: {name}")
        registered[name] = test
        properties = {p["name"]: p["value"] for p in test.get("properties", [])}
        labels = set(properties.get("LABELS", []))
        selected = [g for g, wanted in GROUPS.items() if labels & wanted]
        if len(selected) > 1:
            errors.append(f"Test selected by multiple groups: {name}")
        if not selected:
            excluded.append(name)
        for group in selected:
            groups[group].append(name)
            if properties.get("DISABLED"):
                errors.append(f"Disabled CI test: {name}")
            if not test.get("command"):
                errors.append(f"Missing executable for CI test: {name}")
    for group, names in required.items():
        if group not in groups:
            errors.append(f"Unknown required group: {group}")
            continue
        for name in names:
            if name not in registered:
                errors.append(f"Required test not registered: {name}")
            elif name not in groups[group]:
                errors.append(f"Required test lacks {group} label: {name}")
    for group, names in groups.items():
        if not names:
            errors.append(f"Empty CI group: {group}")
    return {"groups": groups, "excluded": sorted(excluded), "errors": errors}


def results(report, directory):
    errors = list(report["errors"])
    lines = ["## Test results", "", "| Group | Planned | Passed | Failed | Skipped | Missing |",
             "|---|---:|---:|---:|---:|---:|"]
    for group, names in report["groups"].items():
        path = directory / f"{group}.xml"
        cases = {}
        if path.exists():
            try:
                for case in ET.parse(path).iter("testcase"):
                    name = case.get("name")
                    if name in cases:
                        errors.append(f"Duplicate result in {group}: {name}")
                    cases[name] = case
            except ET.ParseError as error:
                errors.append(f"Invalid {group} report: {error}")
        expected = set(names)
        missing = expected - cases.keys()
        unexpected = cases.keys() - expected
        errors.extend(f"No result in {group}: {name}" for name in sorted(missing))
        errors.extend(f"Unexpected result in {group}: {name}" for name in sorted(unexpected))
        counts = {"passed": 0, "failed": 0, "skipped": 0}
        for name in expected & cases.keys():
            case = cases[name]
            if case.find("failure") is not None or case.find("error") is not None:
                state = "failed"
            elif case.find("skipped") is not None or case.get("status", "run") != "run":
                state = "skipped"
            else:
                state = "passed"
            counts[state] += 1
            if state != "passed":
                errors.append(f"{state.capitalize()} in {group}: {name}")
        lines.append(f"| {group} | {len(names)} | {counts['passed']} | "
                     f"{counts['failed']} | {counts['skipped']} | {len(missing)} |")
    lines += ["", "Scope: data, platform, logic, explicitly labelled offscreen UI tests and private-compositor widget regressions.",
              "Other compositor integration, optional application suites and ListenFree are not guaranteed by this job."]
    if report["excluded"]:
        lines += ["", "Registered but outside this job: " + ", ".join(report["excluded"])]
    if errors:
        lines += ["", "### Problems", ""] + [f"- {error}" for error in errors]
    return "\n".join(lines) + "\n", errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["inventory", "report"])
    parser.add_argument("--build-dir", type=Path, default=ROOT / ".build/tests")
    parser.add_argument("--manifest", type=Path, default=ROOT / ".github/ci-tests.json")
    args = parser.parse_args()
    directory = args.build_dir.resolve() / "test-results"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "inventory.json"
    if args.mode == "inventory":
        output = subprocess.check_output(
            ["ctest", "--test-dir", str(args.build_dir), "--show-only=json-v1"], text=True)
        (directory / "ctest-inventory.json").write_text(output)
        report = inventory(json.loads(output)["tests"], json.loads(args.manifest.read_text()))
        path.write_text(json.dumps(report, indent=2) + "\n")
        for group, names in report["groups"].items():
            print(f"{group}: {len(names)} registered tests")
        for error in report["errors"]:
            print(error)
        return bool(report["errors"])
    if path.exists():
        summary, errors = results(json.loads(path.read_text()), directory)
    else:
        summary = "## Test results\n\nNo inventory: preparation or test discovery failed; coverage is unverified.\n"
        errors = ["Missing inventory"]
    (directory / "summary.md").write_text(summary)
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as stream:
            stream.write(summary)
    return bool(errors)


if __name__ == "__main__":
    raise SystemExit(main())
