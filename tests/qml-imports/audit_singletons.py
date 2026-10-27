#!/usr/bin/env python3
"""Audit cross-module singleton references against the file's imports.

Why this exists
---------------
`audit_imports.py` resolves *types* (Rectangle, Item, ...). It cannot see a
singleton, because a singleton is a value, not a type. So a file that calls
`I18n.tr(...)` without importing the i18n module passes every existing check
and then fails at load time with a ReferenceError.

On a shell, a load-time error in one module takes the whole desktop with it:
the user gets a wallpaper and nothing else. That happened on 2026-10-22 with
three island cards, and this script is the gate that would have caught it.

How scope is decided
--------------------
QML module scope is what the module's own qmldir lists, so that is what this
script uses:

* a singleton is in scope without an import when the referencing file and the
  singleton are listed by the same module, or live in the same directory;
* a module can be imported by name (`qs.desktop.modules.dock`) or by relative
  path (`import "../../../Kos/Ui"`), so both forms count;
* the i18n module is imported by relative path from several places, so it is
  matched on the tail of that path.
"""

from __future__ import annotations

import os
import re
import sys

# The shared/qml folder is mounted into several modules, so a file there
# inherits the scope of whichever module imported it -- a topology this script
# does not model. The default scope is therefore the modules with their own
# qmldir: the shell's feature modules and the settings application.
ROOTS = ("shell/desktop/modules/island", "apps/settings")
I18N_DIR = "i18n"

IMPORT_RE = re.compile(r'^\s*import\s+(?:[A-Za-z0-9_.]+\s+as\s+\w+\s*)?([A-Za-z0-9_.]+|"[^"]+")')
SINGLETON_USE_RE = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\s*\.")


def read_qmldir(path: str) -> tuple[str, dict[str, str], list[str]]:
    module = ""
    singletons: dict[str, str] = {}
    listed: list[str] = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("module "):
                module = line.split(None, 1)[1].strip()
                continue
            parts = line.split()
            # `singleton Name Version File` and `Type Version File`.
            if len(parts) >= 4 and parts[0] == "singleton":
                singletons[parts[1]] = parts[3]
                listed.append(parts[3])
            elif len(parts) >= 3:
                listed.append(parts[2])
    return module, singletons, listed


def collect(roots: tuple[str, ...]):
    """singleton -> [(module, file)], module -> {files it lists}."""
    owners: dict[str, list[tuple[str, str]]] = {}
    module_files: dict[str, set[str]] = {}
    # Some qmldir entries point at files that live in the shared folder (it is
    # mounted into more than one module), so the real location of every file
    # is looked up by name as well.
    by_name: dict[str, list[str]] = {}
    for root in roots:
        for base, _dirs, files in os.walk(root):
            for entry in files:
                if entry.endswith(".qml"):
                    by_name.setdefault(entry[:-4], []).append(
                        os.path.join(base, entry))
    for root in roots:
        for base, _dirs, files in os.walk(root):
            if "qmldir" not in files:
                continue
            qmldir = os.path.join(base, "qmldir")
            module, singletons, listed = read_qmldir(qmldir)
            if not module:
                continue
            resolved = set()
            for target in listed:
                resolved.add(os.path.normpath(os.path.join(base, target)))
            module_files[module] = resolved
            for name, target in singletons.items():
                path = os.path.normpath(os.path.join(base, target))
                if not os.path.exists(path):
                    for candidate in by_name.get(name, []):
                        if os.path.basename(candidate) == os.path.basename(target):
                            path = candidate
                            break
                owners.setdefault(name, []).append((module, path))
    return owners, module_files


def imports_of(source: str) -> list[str]:
    found: list[str] = []
    for line in source.splitlines():
        match = IMPORT_RE.match(line)
        if match:
            found.append(match.group(1).strip('"'))
    return found


def module_imported(imported: list[str], module: str, module_files: dict) -> bool:
    if module in imported:
        return True
    # A relative import of the module's directory: `import "../../../Kos/Ui"`.
    directories = {os.path.dirname(item) for item in module_files.get(module, set())}
    for item in imported:
        if not item.startswith("."):
            continue
        tail = item.split("/")[-1]
        for directory in directories:
            if os.path.basename(directory) == tail:
                return True
    return False


def main(argv: list[str]) -> int:
    roots = tuple(argv[1:]) or ROOTS
    owners, module_files = collect(roots)
    if not owners:
        print("no singletons found; is the tree laid out as expected?", file=sys.stderr)
        return 2

    problems: list[str] = []
    checked = 0
    for root in roots:
        for base, _dirs, files in os.walk(root):
            for name in sorted(files):
                if not name.endswith(".qml"):
                    continue
                path = os.path.join(base, name)
                with open(path, encoding="utf-8") as handle:
                    source = handle.read()
                checked += 1
                imported = imports_of(source)
                for used in sorted(set(SINGLETON_USE_RE.findall(source))):
                    if used == "I18n":
                        if os.path.dirname(path).endswith(os.path.join("qml", I18N_DIR)):
                            continue
                        if not any(
                            item.replace(os.sep, "/").endswith("/" + I18N_DIR)
                            or item.replace(os.sep, "/").endswith("shared/qml/" + I18N_DIR)
                            for item in imported
                        ):
                            problems.append(
                                f"{path}: uses {used} but no import of the i18n module")
                        continue
                    candidates = owners.get(used)
                    if not candidates:
                        continue
                    resolved = False
                    for module, target in candidates:
                        if os.path.dirname(path) == os.path.dirname(target):
                            resolved = True  # same directory
                            break
                        if path in module_files.get(module, set()):
                            resolved = True  # listed by the same module
                            break
                        if module_imported(imported, module, module_files):
                            resolved = True
                            break
                    if not resolved:
                        modules = ", ".join(sorted({m for m, _ in candidates}))
                        problems.append(
                            f"{path}: uses {used} but does not import {modules}")

    for problem in problems:
        print(problem)
    print(f"{len(problems)} problem(s) out of {checked} file(s) checked")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
