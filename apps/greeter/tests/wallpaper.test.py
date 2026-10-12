#!/usr/bin/env python3
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'companion'))
from resources import Store, NOTICE
from wallpaper import snapshot

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp) / 'store'
    store = Store(root)
    out = io.BytesIO(); Image.new('RGB', (913, 557), '#dd6633').save(out, format='PNG')
    manifest = store.publish(1000, out.getvalue(), consent=True, notice=NOTICE)
    state = snapshot(root, 1000, os.getuid())
    assert state['sha256'] == manifest['resources']['wallpaper']['sha256']
    assert state['source'].startswith('data:image/png;base64,')
    before = sorted(str(p.relative_to(root)) for p in root.rglob('*'))
    assert snapshot(root, 1001, os.getuid())['version'] == 'default'
    assert sorted(str(p.relative_to(root)) for p in root.rglob('*')) == before
    file = root / '1000/manifest.json'
    for mutation in ('unknown', 'version', 'missing', 'corrupt', 'revoke'):
        store.publish(1000, out.getvalue(), consent=True, notice=NOTICE)
        m = json.loads(file.read_text()); image = file.parent / m['version'] / 'wallpaper.png'
        if mutation == 'unknown': m['unexpected'] = True; file.write_text(json.dumps(m))
        elif mutation == 'version': m['schemaVersion'] = 99; file.write_text(json.dumps(m))
        elif mutation == 'missing': image.unlink()
        elif mutation == 'corrupt': image.write_bytes(b'broken')
        else: store.revoke(1000)
        assert snapshot(root, 1000, os.getuid())['version'] == 'default', mutation
    assert snapshot(root, 1000, os.getuid() + 1)['version'] == 'default'
print('PASS T07 read-only hash, unknown fields/version, absent/corrupt/revoked/untrusted resources')
