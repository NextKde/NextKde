#!/usr/bin/env python3
"""Report identifiers used in QML files that nothing in scope defines.

A QML file that calls a function on an id that does not exist does not fail
to load: it throws a ReferenceError the first time the line runs. In the
island's spring animation that meant a 125 Hz timer kept running after the
animation had settled, throwing on every tick and flooding the shell log.
qmllint reports it as "Unqualified access", mixed in with dozens of harmless
warnings, so it is easy to miss.

The check is deliberately conservative. An identifier counts as resolved when
it is:

  * an id declared in the same file (inline components see the enclosing
    file's ids, and a separate file never may),
  * a property, signal, method or readonly property declared in the file,
  * a type name, a module import, or a model-injected name (index,
    modelData),
  * one of the QML/JS globals.

Everything else is reported. A file that only uses what it declares produces
no output.
"""
import re
import sys
from pathlib import Path

GLOBALS = {
    # JavaScript
    "console", "Math", "JSON", "Object", "Array", "String", "Number",
    "Boolean", "Date", "RegExp", "Error", "TypeError", "RangeError",
    "parseInt", "parseFloat", "isNaN", "isFinite", "decodeURIComponent",
    "encodeURIComponent", "decodeURI", "encodeURI", "Infinity", "NaN",
    "undefined", "null", "true", "false", "this", "arguments",
    "Symbol", "Map", "Set", "Promise", "globalThis",
    # QML
    "Qt", "parent", "self", "window", "application", "screen", "font",
    "palette", "layer", "visible", "enabled", "width", "height", "x", "y",
    "z", "opacity", "rotation", "scale", "anchors", "transform", "opacity",
    "clip", "smooth", "antialiasing", "renderType", "children", "data",
    "resources", "states", "transitions", "signals", "properties",
    # model-injected / context names
    "index", "modelData", "model", "control", "delegate", "label",
    "value", "currentIndex", "currentValue", "displayText", "text",
    # translation helper used by the shared foundation components
    "qsTr", "qsTrId", "qsTranslate",
    # methods QQuickItem and friends provide on the enclosing object
    "mapToItem", "mapToGlobal", "mapFromItem", "mapToScene", "mapFromScene",
    "mapFromGlobal", "getContext", "requestPaint", "toDataURL", "markDirty",
    "forceActiveFocus", "releaseMouse", "grabMouse", "setProperty",
    "createObject", "destroy", "contains", "childrenRect", "tag",
    # QML singletons and project modules (matched case-sensitively below)
}

# Names that are module imports in the file, plus any PascalCase identifier
# (a type) and any SCREAMING_CASE constant.
IDENT_RE = re.compile(r'(?<![\w.$])([A-Za-z_][A-Za-z0-9_]*)\s*(?:\.|\()')
ID_DECL_RE = re.compile(r'\bid\s*:\s*([A-Za-z_][A-Za-z0-9_]*)')
PROP_DECL_RE = re.compile(
    r'\b(?:property|readonly\s+property|signal|required\s+property)\s+'
    r'(?:[A-Za-z_][A-Za-z0-9_]*\s+)*([A-Za-z_][A-Za-z0-9_]*)\s*[:(]')
FUNC_DECL_RE = re.compile(r'\bfunction\s+([A-Za-z_][A-Za-z0-9_]*)')
# Function parameters: `function name(a, b)` and `function(a, b)`.
PARAM_RE = re.compile(r'\bfunction\s+[A-Za-z_][A-Za-z0-9_]*\s*\(([^)]*)\)')
ANON_PARAM_RE = re.compile(r'\bfunction\s*\(([^)]*)\)')
# Local variables.
VAR_RE = re.compile(r'\b(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)')
# Destructuring: `const { a, b } = x` and `const [a, b] = x`.
DESTRUCTURE_RE = re.compile(r'\b(?:const|let|var)\s*[{[]([^}\]]*)[}\]]')
# Catch clauses: `catch (error)`.
CATCH_RE = re.compile(r'\bcatch\s*\(([^)]*)\)')
IMPORT_MODULE_RE = re.compile(r'^\s*import\s+([A-Za-z0-9_.]+)', re.M)
IMPORT_PATH_RE = re.compile(r'^\s*import\s+"([^"]+)"', re.M)
BUILTIN_MEMBER_RE = re.compile(
    r'\b(?:console|Math|JSON|Object|Array|String|Number|Boolean|Date|'
    r'RegExp|Error|parseInt|parseFloat|isNaN|isFinite|Qt)\.')


def scrub(text: str) -> str:
    """Blank out string literals, comments and property names.

    Property names are blanked because `text: foo` names a property, it does
    not read an identifier.
    """
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
    text = "".join(out)
    # Blank the left side of a binding: `someProperty: value` names a
    # property of the enclosing object.
    text = re.sub(r'(?m)^(\s*)([A-Za-z_][A-Za-z0-9_.]*)\s*:', r'\1: ', text)
    # Blank grouped property keys anywhere: `border.width: 1` names a group,
    # not an identifier in scope.
    text = re.sub(r'\b([a-z][A-Za-z0-9_]*)\.([a-z][A-Za-z0-9_]*)\s*:',
                  r': ', text)
    # Blank object literal keys: `{ id: 1 }` names a key.
    text = re.sub(r'(?m)([{,]\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:', r'\1: ', text)
    # Blank signal handler names: `onDropped: ...` is a property of the
    # object, not an identifier in scope.
    text = re.sub(r'\b(on[A-Z][A-Za-z0-9_]*)\s*:', r': ', text)
    return text


def declared_names(path: Path) -> set:
    raw = path.read_text(encoding="utf-8", errors="replace")
    names = set()
    for m in ID_DECL_RE.finditer(raw):
        names.add(m.group(1))
    for m in PROP_DECL_RE.finditer(raw):
        names.add(m.group(1))
    for m in FUNC_DECL_RE.finditer(raw):
        names.add(m.group(1))
    for m in VAR_RE.finditer(raw):
        names.add(m.group(1))
    for m in DESTRUCTURE_RE.finditer(raw):
        for part in m.group(1).split(","):
            name = part.split(":")[-1].strip()
            if name:
                names.add(name)
    for pattern in (PARAM_RE, ANON_PARAM_RE, CATCH_RE):
        for m in pattern.finditer(raw):
            for part in m.group(1).split(","):
                name = part.split("=")[0].strip()
                if name:
                    names.add(name)
    for m in IMPORT_MODULE_RE.finditer(raw):
        names.add(m.group(1).split(".")[0])
    for m in IMPORT_PATH_RE.finditer(raw):
        names.add(m.group(1).split("/")[-1])
    return names


def local_component_names(path: Path) -> set:
    names = set()
    for sibling in path.parent.glob("*.qml"):
        names.add(sibling.stem)
    raw = path.read_text(encoding="utf-8", errors="replace")
    for m in IMPORT_PATH_RE.finditer(raw):
        target = (path.parent / m.group(1)).resolve()
        if target.is_dir():
            for member in target.glob("*.qml"):
                names.add(member.stem)
    return names


def check(path: Path):
    raw = path.read_text(encoding="utf-8", errors="replace")
    text = scrub(raw)
    known = declared_names(path) | GLOBALS | local_component_names(path)
    # Names of the file's own root object: `Rectangle { id: root }` also
    # allows `root`, already covered by id declarations.
    problems = []
    seen = set()
    for m in IDENT_RE.finditer(text):
        name = m.group(1)
        if name in known or name in seen:
            continue
        # A PascalCase name is a type; a SCREAMING_CASE name is a constant.
        if name[0].isupper() or (name.isupper() and "_" in name):
            continue
        # Skip anything that directly follows a dot (member access).
        start = m.start(1)
        if start > 0 and text[start - 1] == ".":
            continue
        # Skip names that are part of a larger expression keyword.
        if name in ("function", "return", "if", "else", "for", "while", "var",
                    "let", "const", "new", "typeof", "in", "of", "do", "try",
                    "catch", "throw", "switch", "case", "break", "continue",
                    "default", "delete", "void", "instanceof", "yield", "await",
                    "async", "import", "export", "class", "extends", "super",
                    "this", "null", "true", "false"):
            continue
        seen.add(name)
        line = text.count("\n", 0, m.start()) + 1
        problems.append((name, line))
    return problems


def main() -> int:
    roots = [Path(p) for p in sys.argv[1:]] or [Path("shell")]
    files = []
    for root in roots:
        if root.is_file() and root.suffix == ".qml":
            files.append(root)
            continue
        for path in sorted(root.rglob("*.qml")):
            files.append(path)
    bad = 0
    for path in files:
        problems = check(path)
        if not problems:
            continue
        bad += 1
        print(f"\n{path}")
        for name, line in problems:
            print(f"  UNDEFINED?: {name} (line {line})")
    print(f"\n{bad} file(s) with unresolved identifiers out of {len(files)} checked")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
