"""Hidden ordinary lyrics must not retain row blur render targets."""
import json
import pathlib
import sys

rows = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
checked = 0
for row in rows:
    if row['label'] != 'end' or not row['immersive']:
        continue
    assert row.get('lyricLines', 0) > 0, (row['stage'], 'missing lyric workload')
    checked += 1
    hidden = [layer for layer in row['layers'] if layer['scope'] == 'nowplayingUnderlay'
              and layer['ownerName'].startswith('lyricRow') and not layer['visible']]
    assert not hidden, (row['stage'], len(hidden), 'hidden lyric row layers still enabled')
assert checked > 0, 'No immersive workload was measured'
print(f'PASS: hidden ordinary lyric blur layers released in {checked} immersive stages')
