#!/usr/bin/env python3
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "companion"))
spec = importlib.util.spec_from_file_location('entry', Path(__file__).resolve().parents[1] / 'companion/entry.py')
entry = importlib.util.module_from_spec(spec); spec.loader.exec_module(entry)
class Identity(unittest.TestCase):
    def test_canonical_publication(self):
        import io
        from PIL import Image
        from resources import image_copy
        with tempfile.TemporaryDirectory() as d:
            out = io.BytesIO(); Image.new('RGB', (20, 20), '#123456').save(out, format='JPEG')
            raw = out.getvalue(); canonical, _ = image_copy(raw)
            p = Path(d) / 'private.jpg'; p.write_bytes(raw)
            digest = hashlib.sha256(canonical).hexdigest()
            self.assertEqual(entry.image_bytes(p.as_uri(), digest), canonical)
    def test_identity_and_replacement(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'image with space.png'; p.write_bytes(b'fixture')
            h = hashlib.sha256(b'fixture').hexdigest()
            self.assertTrue(entry.match(p.as_uri(), h))
            p.write_bytes(b'changed'); self.assertFalse(entry.match(p.as_uri(), h))
            self.assertFalse(entry.match('https://example.com/a', h))
            self.assertFalse(entry.match('relative.png', h))
            self.assertFalse(entry.match(str(p), 'invalid'))
            self.assertFalse(entry.match(str(Path(d)), h))
if __name__ == '__main__': unittest.main()
