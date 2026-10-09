"""Build a matched comparison with six resource optimizations disabled.

Temporarily changes only the named optimization lines, saves their exact current
bytes, and restores/rebuilds the production source before returning. Run only
when no benchmark or other build is running. The comparison keeps the remaining
current application code, dependencies, and diagnostic entry identical.
"""
import os
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[2]
work = root/'build/performance-optimization'
backup = work/'matched-baseline-source'
backup.mkdir(parents=True, exist_ok=True)
replacements = {
    'music_player_desktop/components/LyricsPanel.qml': (
        'layer.enabled: panel.visible && panel.inactiveBlurEnabled && nearViewport',
        'layer.enabled: panel.inactiveBlurEnabled && nearViewport'),
    'music_player_desktop/components/NavigationCache.qml': (
        'if (key !== route) { recent.push(key); break }',
        'if (key !== route) { recent.push(key) }'),
    'music_player_desktop/components/FoliaLyrics.qml': (
        'layer.effect: focusSettled ? focusedEffect : depthEffect',
        'layer.effect: depthEffect'),
    'music_player_desktop/components/GlobalBackground.qml': (
        'onFinished: root.releaseOutgoing()',
        'onFinished: {}'),
    'music_player_desktop/components/SongTable.qml': (
        'model: table.sourceModel === null ? table.displayRows.length : 0',
        'model: table.displayRows.length'),
    'music_player_desktop/pages/LibraryPage.qml': (
        'active: page.section === "songs"',
        'active: true\n        visible: page.section === "songs"'),
}
original = {}
modified = {}
for name, (before, after) in replacements.items():
    path = root/name
    raw = path.read_bytes()
    code = raw.decode('utf-8')
    if code.count(before) != 1:
        raise SystemExit(f'Optimization line changed; review before comparing: {name}')
    original[path] = raw
    modified[path] = code.replace(before, after).encode('utf-8')
    (backup/path.name).write_bytes(raw)

env = dict(os.environ)
env['PATH'] = 'F:/QT/Tools/mingw1310_64/bin;F:/QT/6.11.2/mingw_64/bin;'+env['PATH']
build = ['F:/QT/Tools/CMake_64/bin/cmake.exe', '--build', str(root/'build/performance-verify'), '--target', 'listenfree', '-j', '6']
try:
    for path, raw in modified.items():
        path.write_bytes(raw)
    with (work/'matched-baseline-build.log').open('w', encoding='utf-8') as log:
        subprocess.run(build, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    subprocess.run([sys.executable, str(root/'tools/performance/build_probe.py'), '--link-only',
                    '--runtime', str(work/'matched-baseline-runtime')], cwd=root, env=env, check=True)
finally:
    conflicts = []
    for path, raw in original.items():
        if path.read_bytes() in (modified[path], raw):
            path.write_bytes(raw)
        else:
            conflicts.append(str(path))
    if conflicts:
        raise RuntimeError(f'Concurrent edits preserved; recover optimization lines using {backup}: {conflicts}')
    with (work/'matched-restored-build.log').open('w', encoding='utf-8') as log:
        subprocess.run(build, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
print('Comparison built; all six production files restored and Release rebuilt.')
