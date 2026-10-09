"""Materialize native benchmark cases with an isolated, fixed library snapshot."""
import argparse
import json
import pathlib
import sqlite3

root = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--track', type=pathlib.Path, required=True)
parser.add_argument('--profile', type=pathlib.Path, default=root/'dist/ListenFree-Portable/data/library.sqlite')
parser.add_argument('--video', type=pathlib.Path, default=root.parent/'reference/upstream/reference-hx-music/pyTool/src/data/empty.mp4')
parser.add_argument('--output', type=pathlib.Path, default=root/'build/performance-optimization/cases')
parser.add_argument('--results', type=pathlib.Path, default=root/'build/performance-optimization/results')
args = parser.parse_args()
for path in [args.track, args.profile, args.video]:
    if not path.is_file():
        parser.error(f'Missing fixture: {path}')
args.output.mkdir(parents=True, exist_ok=True)
snapshot = args.output.resolve()/'profile.sqlite'
if not snapshot.exists():
    with sqlite3.connect(args.profile.resolve().as_uri()+'?mode=ro', uri=True) as source:
        with sqlite3.connect(snapshot) as target:
            source.backup(target)
values = {
    '@REPO@': str(root), '@REPO_URI@': root.as_uri(),
    '@TRACK@': str(args.track.resolve()), '@VIDEO@': str(args.video.resolve()),
    '@PROFILE@': str(snapshot), '@RESULTS@': str(args.results.resolve()),
}

def substitute(value):
    if isinstance(value, dict):
        return {key: substitute(item) for key, item in value.items()}
    if isinstance(value, list):
        return [substitute(item) for item in value]
    if isinstance(value, str):
        for token, replacement in values.items():
            value = value.replace(token, replacement)
    return value

for template in pathlib.Path(__file__).with_name('cases').glob('*.json'):
    case = substitute(json.loads(template.read_text(encoding='utf-8')))
    (args.output/template.name).write_text(json.dumps(case, indent=2, ensure_ascii=False), encoding='utf-8')
print(args.output.resolve())
