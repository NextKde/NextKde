#!/usr/bin/env python3
"""Fail on missing UI translations or damaged substitution placeholders."""
import collections
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

REPO = Path(__file__).resolve().parents[2]
LUPDATE = shutil.which("lupdate") or "/usr/lib/qt6/bin/lupdate"
placeholder = re.compile(r"%(?:L?\d+|L?n)")

def sources(paths):
    with tempfile.TemporaryDirectory() as directory:
        target = Path(directory) / "catalog.ts"
        subprocess.run([LUPDATE, *[str(REPO / p) for p in paths], "-no-obsolete", "-silent", "-ts", str(target)], check=True, capture_output=True)
        return ET.parse(target).getroot()

def check_placeholders(source, translated):
    assert collections.Counter(placeholder.findall(source)) == collections.Counter(placeholder.findall(translated)), (source, translated)

def app_catalog(language):
    root = ET.parse(REPO / f"apps/common/translations/kos_apps_{language}.ts").getroot()
    translations = {}
    for context in root.findall("context"):
        for message in context.findall("message"):
            source = message.findtext("source")
            translation = message.find("translation")
            assert translation.get("type") not in ("unfinished", "vanished", "obsolete"), (language, source)
            texts = [n.text for n in translation.findall("numerusform")] or [translation.text]
            assert all(texts), (language, source)
            for text in texts:
                check_placeholders(source, text)
            translations[(context.findtext("name"), source)] = texts
    return translations

app_translations = app_catalog("zh_CN")
portuguese_translations = app_catalog("pt_BR")
current = sources(["apps/calendar", "apps/calculator", "apps/todo", "apps/weather", "shared/qml/foundation", "shared/pim"])
# zh_CN must stay complete; pt_BR may lag behind and falls back to English.
portuguese_missing = 0
for context in current.findall("context"):
    for message in context.findall("message"):
        key = (context.findtext("name"), message.findtext("source"))
        assert key in app_translations, key
        portuguese_missing += key not in portuguese_translations

music = json.loads((REPO / "apps/listenfree/music_player_desktop/translations/en_US.json").read_text())
current = sources(["apps/listenfree/music_player_desktop", "apps/listenfree/src"])
missing = set()
for message in current.findall(".//message"):
    source = message.findtext("source")
    if re.search("[\u4e00-\u9fff]", source or ""):
        if not music.get(source): missing.add(source)
        else: check_placeholders(source, music[source])
assert not missing, sorted(missing)
print(f"PASS: {len(app_translations)} app messages ({portuguese_missing} untranslated in pt_BR) and {len(music)} music translations; no missing messages or placeholder mismatches")
