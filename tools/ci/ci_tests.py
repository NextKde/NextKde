#!/usr/bin/env python3
"""Check required CTest registrations and account for every selected CI test."""
import argparse
import html
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
    "installed": {"installed"},
}
ROOT = Path(__file__).resolve().parents[2]

# Workflow order, not JSON key order. A downstream summary failure is a report
# of these outcomes, not another independent test failure.
STAGES = [
    ("bootstrap", "Dependency installation"),
    ("checkout", "Source checkout"),
    ("dependencies", "Dependency installation"),
    ("compositor", "Compositor setup"),
    ("cache", "Build cache setup"),
    ("prepare", "Build/configuration"),
    ("inventory", "Test registration"),
    ("data_platform", "Data/platform tests"),
    ("logic", "Logic/translation tests"),
    ("tray_menu", "Tray menu integration"),
    ("tray_color", "Tray rendering"),
    ("status_panels", "Status panel rendering"),
    ("headless", "Offscreen UI tests"),
    ("widgets", "Widget rendering"),
    ("installed", "Installed Shell tests"),
]
STAGE_REPORTS = {
    "data_platform": "data-platform", "logic": "logic", "headless": "headless",
    "widgets": "widgets", "installed": "installed", "tray_color": "tray-color",
    "status_panels": "status-panels",
}


def first_test_failure(path):
    """Use actual JUnit results, not incidental warnings in successful tests."""
    if not path.exists():
        return None
    try:
        cases = ET.parse(path).iter("testcase")
        for case in cases:
            failure = case.find("failure")
            if failure is None:
                failure = case.find("error")
            if failure is None:
                continue
            reason = " ".join(filter(None, [failure.get("message"), failure.get("type"), failure.text]))
            detail = "\n".join(filter(None, [reason, case.findtext("system-out")]))
            category = "Timeout" if "timeout" in reason.lower() or "timed out" in reason.lower() else "Test failure"
            # Keep the summary short; full output remains in the uploaded XML/log.
            useful = [line.strip() for line in detail.splitlines()
                      if any(marker in line for marker in
                             ("FAIL!", "AssertionError", "Actual", "Expected", "Loc:", "Timeout", "timed out"))]
            excerpt = "\n".join(useful[:8]) if useful else detail[:800]
            return case.get("name", "Unnamed test"), category, excerpt[:1200]
    except ET.ParseError:
        return None  # The coverage report below still fails malformed XML.
    return None


def stage_summary(steps, directory):
    failed = [(key, title, steps.get(key, {}).get("outcome")) for key, title in STAGES
              if steps.get(key, {}).get("outcome") in {"failure", "cancelled"}]
    if not failed:
        return "", []
    key, title, outcome = failed[0]
    lines = ["## First unsuccessful stage", "",
             f"**{title}** (`{key}`): **{outcome}**.", ""]
    if outcome == "cancelled":
        lines.append("The stage was cancelled; this is not evidence of a test assertion failure.")
    else:
        report = STAGE_REPORTS.get(key)
        detail = first_test_failure(directory / f"{report}.xml") if report else None
        if detail:
            name, category, excerpt = detail
            lines += [f"{category}: **{html.escape(name)}**.", "",
                      "<pre>" + html.escape(excerpt) + "</pre>"]
        elif key in {"bootstrap", "checkout", "dependencies", "compositor", "cache", "prepare", "inventory"}:
            lines.append("The prerequisite stage failed. Missing downstream results do not mean those tests ran and failed.")
        else:
            lines.append("See this stage's log for the first error; no failed JUnit case was available.")
    if len(failed) > 1:
        lines += ["", "Other unsuccessful stages: " + ", ".join(
            f"{title} (`{key}`, {outcome})" for key, title, outcome in failed[1:]) + "."]
    lines += ["", "The summary reports the same failures; it is not an additional root cause. "
              "See the failed step's full log and the available reports in the test-results artifact.", ""]
    return "\n".join(lines) + "\n", [f"{title}: {outcome}" for _, title, outcome in failed]


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
    lines += ["", "Scope: data, platform, logic, explicitly labelled offscreen UI tests and private-compositor widget and installed Shell regressions.",
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
    try:
        steps = json.loads(os.environ.get("CI_STEP_OUTCOMES", "{}"))
        if not isinstance(steps, dict) or any(not isinstance(value, dict) for value in steps.values()):
            raise ValueError("expected a step-object mapping")
        first, stage_errors = stage_summary(steps, directory)
        summary = first + summary
        errors.extend(stage_errors)
    except (ValueError, TypeError) as error:
        summary = "## Invalid workflow outcomes\n\n" + html.escape(str(error)) + "\n\n" + summary
        errors.append("Invalid workflow outcomes")
    (directory / "summary.md").write_text(summary)
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as stream:
            stream.write(summary)
    return bool(errors)


if __name__ == "__main__":
    raise SystemExit(main())
