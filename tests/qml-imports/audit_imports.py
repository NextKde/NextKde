#!/usr/bin/env python3
"""Audit QML files for types used without the import that provides them.

A missing import in a shell module is fatal: Quickshell fails to load the
whole configuration, and the user gets a desktop with nothing but the
wallpaper. This happened for real — IslandCalendarWidget.qml used RowLayout
without importing QtQuick.Layouts, and the entire desktop went blank.

The script lists every QML type used in a file and reports the ones that
nothing available to that file can supply. Locally visible types count as
available: a sibling .qml file in the same directory, and the .qml files of a
directory imported by path.
"""
import re
import sys
from pathlib import Path

# Type -> the module that provides it. Types not listed are assumed to come
# from QtQuick or from a project module.
PROVIDERS = {
    # QtQuick.Layouts
    "RowLayout": "QtQuick.Layouts",
    "ColumnLayout": "QtQuick.Layouts",
    "GridLayout": "QtQuick.Layouts",
    "Row": "QtQuick",
    "Column": "QtQuick",
    "Grid": "QtQuick",
    # QtQuick.Controls
    "TextField": "QtQuick.Controls",
    "TextArea": "QtQuick.Controls",
    "Button": "QtQuick.Controls",
    "ToolTip": "QtQuick.Controls",
    "ComboBox": "QtQuick.Controls",
    "Switch": "QtQuick.Controls",
    "Label": "QtQuick.Controls",
    "ScrollBar": "QtQuick.Controls",
    "CheckBox": "QtQuick.Controls",
    "RadioButton": "QtQuick.Controls",
    "ProgressBar": "QtQuick.Controls",
    "MenuItem": "QtQuick.Controls",
    "Menu": "QtQuick.Controls",
    "Dialog": "QtQuick.Controls",
    "Popup": "QtQuick.Controls",
    "ItemDelegate": "QtQuick.Controls",
    "ApplicationWindow": "QtQuick.Controls",
    "Slider": "QtQuick.Controls",
    "SpinBox": "QtQuick.Controls",
    "RoundButton": "QtQuick.Controls",
    "Pane": "QtQuick.Controls",
    "Frame": "QtQuick.Controls",
    "GroupBox": "QtQuick.Controls",
    "Separator": "QtQuick.Controls",
    # QtQuick
    "Item": "QtQuick",
    "Rectangle": "QtQuick",
    "Text": "QtQuick",
    "TextInput": "QtQuick",
    "Image": "QtQuick",
    "AnimatedImage": "QtQuick",
    "MouseArea": "QtQuick",
    "HoverHandler": "QtQuick",
    "DragHandler": "QtQuick",
    "TapHandler": "QtQuick",
    "WheelHandler": "QtQuick",
    "Flickable": "QtQuick",
    "ListView": "QtQuick",
    "GridView": "QtQuick",
    "Repeater": "QtQuick",
    "Row": "QtQuick",
    "Column": "QtQuick",
    "Grid": "QtQuick",
    "Loader": "QtQuick",
    "Timer": "QtQuick",
    "Connections": "QtQuick",
    "Component": "QtQuick",
    "Canvas": "QtQuick",
    "DropArea": "QtQuick",
    "Gradient": "QtQuick",
    "GradientStop": "QtQuick",
    "State": "QtQuick",
    "Transition": "QtQuick",
    "Behavior": "QtQuick",
    "NumberAnimation": "QtQuick",
    "ColorAnimation": "QtQuick",
    "PropertyAnimation": "QtQuick",
    "SequentialAnimation": "QtQuick",
    "ParallelAnimation": "QtQuick",
    "PauseAnimation": "QtQuick",
    "ScriptAction": "QtQuick",
    "FontMetrics": "QtQuick",
    "Shortcut": "QtQuick",
    "FocusScope": "QtQuick",
    "Rotation": "QtQuick",
    "Scale": "QtQuick",
    "SmoothedAnimation": "QtQuick",
    "SpringAnimation": "QtQuick",
    "ShaderEffect": "QtQuick",
    "ShaderEffectSource": "QtQuick",
    "Line": "QtQuick",
    "Shape": "QtQuick",
    "Path": "QtQuick",
    "PathSvg": "QtQuick",
    "Repeater": "QtQuick",
}

# Quickshell / project types
KNOWN_OTHER = {
    "Scope", "Variants", "PanelWindow", "PopupWindow", "FloatingWindow",
    "IpcHandler", "Process", "DataStreamParser", "DataStreamSink",
    "DesktopEntries", "StatusNotifierItem", "SystemTray", "Clipboard",
    "XdgDesktopPortal", "AppLauncherService", "WeatherService",
    "IslandService", "IslandConfigService", "IslandQuickLaunchModel",
    "IslandPomodoroService", "IslandContent", "IslandWidgetSlot",
    "IslandTodoWidget", "IslandWeatherWidget", "IslandClockWidget",
    "IslandPomodoroWidget", "IslandNotesWidget", "IslandBatteryWidget",
    "IslandCalendarWidget", "IslandWindow", "Island", "AppIcon",
    "ScreenLifecycle", "JsonConfigStore", "PlatformClient", "I18n",
    "ConfigService", "AppearanceTokens", "ThemeService", "BundledIcons",
    "AppActionService", "DockService", "SettingsBridge",
}

IMPORT_RE = re.compile(r'^\s*import\s+([A-Za-z0-9_.]+)\s*(?:as\s+[A-Za-z0-9_]+)?\s*$')
# A path import: import "../components" — the directory's .qml files become
# visible as types.
PATH_IMPORT_RE = re.compile(r'^\s*import\s+"([^"]+)"')
# A type use: an identifier that starts with an uppercase letter, followed by
# an optional generic-ish list and then "{".
TYPE_RE = re.compile(r'(?:^|[\s{(,;:\[])([A-Z][A-Za-z0-9_]*)\s*(?:<[^>]*>)?\s*\{')
# A qualified use: Foo.Bar { — the provider is Foo.
QUALIFIED_RE = re.compile(r'(?:^|[\s{(,;:\[])([A-Z][A-Za-z0-9_]*)\.[A-Z][A-Za-z0-9_]*\s*\{')

SKIP_WORDS = {
    "Q", "QQml", "Qt", "QtQuick", "QtQml", "QUrl", "QString",
}


def scrub(text: str) -> str:
    """Remove string literals and comments so they cannot fake a type use."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == '"' or c == "'":
            quote = c
            i += 1
            while i < n and text[i] != quote:
                if text[i] == "\\":
                    i += 1
                i += 1
            i += 1
            out.append('""')
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def local_types(path: Path) -> set:
    """Types visible without a module import.

    A .qml file in the same directory is visible to its siblings, and a
    directory imported by path exposes every .qml file it contains.
    """
    names = set()
    directory = path.parent
    try:
        for sibling in directory.glob("*.qml"):
            names.add(sibling.stem)
    except OSError:
        pass
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return names
    for line in raw.splitlines():
        m = PATH_IMPORT_RE.match(line)
        if not m:
            continue
        target = (directory / m.group(1)).resolve()
        if target.is_dir():
            for member in target.glob("*.qml"):
                names.add(member.stem)
    return names


def audit(path: Path):
    raw = path.read_text(encoding="utf-8", errors="replace")
    imports = set()
    for line in raw.splitlines():
        m = IMPORT_RE.match(line)
        if m:
            imports.add(m.group(1))
    text = scrub(raw)
    used = set()
    for m in TYPE_RE.finditer(text):
        name = m.group(1)
        if name in SKIP_WORDS:
            continue
        used.add(name)
    for m in QUALIFIED_RE.finditer(text):
        used.add(f"{m.group(1)}.*")

    visible = local_types(path)
    problems = []
    for name in sorted(used):
        if "." in name:
            owner = name.split(".")[0]
            if owner in imports or owner in visible:
                continue
            # A qualified use names a type from some imported module, and
            # which module provides it is not knowable from the file alone.
            # Only a standard Qt type can be checked: a project singleton
            # (ConfigService, ScreenLifecycle, ...) comes from one of the
            # module imports, and a typo would not be a known name at all.
            provider = PROVIDERS.get(owner)
            if provider is not None and provider.startswith("QtQuick") \
                    and provider not in imports:
                problems.append((name, f"qualified use of {owner}.* but "
                                       f"'{provider}' is not imported"))
            continue
        if name in visible:
            continue
        provider = PROVIDERS.get(name)
        if provider is None:
            continue
        if provider in imports:
            continue
        # The provider might come in through a project module that re-exports
        # it; only flag the standard Qt modules here.
        if provider.startswith("QtQuick"):
            problems.append((name, f"uses {name} but does not import {provider}"))
    return problems, imports


def main() -> int:
    roots = [Path(p) for p in sys.argv[1:]] or [Path("shell"), Path("apps"), Path("shared")]
    files = []
    for root in roots:
        if root.is_file() and root.suffix == ".qml":
            files.append(root)
            continue
        for path in sorted(root.rglob("*.qml")):
            files.append(path)
    bad = 0
    for path in files:
        try:
            problems, imports = audit(path)
        except Exception as error:  # noqa: BLE001 - report, do not crash
            print(f"audit error: {path}: {error}", file=sys.stderr)
            return 2
        if not problems:
            continue
        bad += 1
        print(f"\n{path}")
        print("  imports: " + ", ".join(sorted(imports)) or "  imports: <none>")
        for name, why in problems:
            print(f"  MISSING: {name} — {why}")
    print(f"\n{bad} file(s) with unresolved types out of {len(files)} checked")
    return 1 if bad else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as error:  # noqa: BLE001
        print(f"audit error: {error}", file=sys.stderr)
        raise SystemExit(2)
