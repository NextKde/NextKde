import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import concurrent.futures
import time
import unittest
from PIL import Image

spec = importlib.util.spec_from_file_location('resources', Path(__file__).parents[1] / 'companion/resources.py')
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)

def png(color='red', size=(32, 24)):
    b = io.BytesIO()
    Image.new('RGB', size, color).save(b, 'PNG')
    return b.getvalue()

class Publication(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = r.Store(Path(self.tmp.name) / 'public')
        self.uid = os.getuid()
        self.d = self.store.root / str(self.uid)
    def tearDown(self):
        self.tmp.cleanup()
    def publish(self, **kw):
        return self.store.publish(self.uid, png(), consent=True, notice=r.NOTICE, **kw)
    def test_consent(self):
        for consent, notice in [(False, r.NOTICE), (True, '')]:
            with self.assertRaises(ValueError):
                self.store.publish(self.uid, png(), consent=consent, notice=notice)
        self.assertIsNone(self.store.consume(self.uid))
    def test_copy_and_permissions(self):
        source = Path(self.tmp.name) / 'source.png'
        source.write_bytes(png())
        m = self.store.publish(self.uid, source.read_bytes(), consent=True, notice=r.NOTICE, avatar=png(size=(1024, 1024)))
        source.unlink()  # Deleted source, absent external drive, unavailable home.
        got = self.store.consume(self.uid)
        self.assertEqual(got[0], m)
        self.assertEqual(m['resources']['avatar']['size'], [512, 512])
        for p in self.store.root.rglob('*'):
            self.assertEqual(p.stat().st_uid, os.getuid())
            self.assertFalse(p.stat().st_mode & 0o022)
        self.assertNotIn(str(source), json.dumps(m))
    def test_invalid_inputs_preserve_previous(self):
        m = self.publish()
        for bad in [b'not an image', b'x' * (r.MAX_BYTES + 1), png(size=(8193, 1))]:
            with self.assertRaises((ValueError, OSError)):
                self.store.publish(self.uid, bad, consent=True, notice=r.NOTICE)
            self.assertEqual(self.store.consume(self.uid)[0], m)
        with self.assertRaises(ValueError):
            self.publish(mode='theme')
    def test_interrupted_publish_and_gc(self):
        m = self.publish()
        for point in ['before-version', 'before-manifest']:
            with self.assertRaises(OSError):
                self.publish(fail=point)
            self.assertEqual(self.store.consume(self.uid)[0], m)
            self.store.recover(self.uid)
            self.assertEqual([p.name for p in self.d.glob('v-*')], [m['version']])
            self.assertFalse(list(self.d.glob('.tmp-*')))
        n = self.publish()
        self.assertFalse((self.d / m['version']).exists())
        self.assertEqual(self.store.consume(self.uid)[0], n)
    def test_revoke_delete_and_cleanup_recovery(self):
        for interrupted in [False, True]:
            self.publish()
            if interrupted:
                with self.assertRaises(OSError):
                    self.store.revoke(self.uid, fail=True)
            else:
                self.store.revoke(self.uid)  # Same operation for account deletion.
            self.assertIsNone(self.store.consume(self.uid))
            self.store.recover(self.uid)
            self.assertFalse(list(self.d.glob('v-*')))
    def test_bad_manifest_and_corruption(self):
        for change in [lambda m: m.update(schemaVersion=2), lambda m: m.update(expiresAt=0),
                       lambda m: m.update(command='forbidden'), lambda m: m.update(version='../home'),
                       lambda m: m['resources']['wallpaper'].update(file='/etc/passwd'),
                       lambda m: m['resources']['wallpaper'].update(size=[1, 1]),
                       lambda m: m.update(crop=[False, False, True, True]),
                       lambda m: m['resources']['wallpaper'].update(size=[32.0, 24.0])]:
            m = self.publish()
            change(m)
            (self.d / 'manifest.json').write_text(json.dumps(m))
            self.assertIsNone(self.store.consume(self.uid))
            self.store.recover(self.uid)
            self.assertFalse(list(self.d.glob('v-*')))
        m = self.publish()
        image = self.d / m['version'] / 'wallpaper.png'
        image.write_bytes(b'broken')
        self.assertIsNone(self.store.consume(self.uid))
        image.unlink()
        self.assertIsNone(self.store.consume(self.uid))
    def test_parallel_publish_and_revoke(self):
        def operation(i):
            if i % 3 == 0:
                self.store.revoke(self.uid)
            else:
                self.publish(fit='center')
            value = self.store.consume(self.uid)
            if value is not None:
                self.assertEqual(value[0]['fit'], 'center')
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(operation, range(24)))
        self.store.revoke(self.uid)
        self.assertIsNone(self.store.consume(self.uid))
        self.assertFalse(list(self.d.glob('v-*')))
        self.assertFalse(list(self.d.glob('.tmp-*')))
    def test_restrictive_umask(self):
        old = os.umask(0o077)
        try:
            m = self.publish()
            for p in [self.d, self.d / m['version']]:
                self.assertEqual(p.stat().st_mode & 0o777, 0o755)
            for p in [self.d / 'manifest.json', self.d / m['version'] / 'wallpaper.png']:
                self.assertEqual(p.stat().st_mode & 0o777, 0o644)
        finally:
            os.umask(old)
    def test_deep_json_fallback(self):
        self.publish()
        (self.d / 'manifest.json').write_text('[' * 1500 + '0' + ']' * 1500)
        self.assertIsNone(self.store.consume(self.uid))
        self.store.recover(self.uid)
        self.assertFalse(list(self.d.glob('v-*')))
    def test_committed_cleanup_interruption(self):
        old = self.publish()
        with self.assertRaises(OSError):
            self.publish(fail='after-manifest')
        current = self.store.consume(self.uid)[0]
        self.assertNotEqual(current['version'], old['version'])
        self.store.recover(self.uid)
        self.assertEqual([p.name for p in self.d.glob('v-*')], [current['version']])
    def test_metadata_removed(self):
        from PIL.PngImagePlugin import PngInfo
        meta = PngInfo()
        meta.add_text('private', 'private-marker')
        b = io.BytesIO()
        Image.new('RGB', (20, 20)).save(b, 'PNG', pnginfo=meta)
        self.store.publish(self.uid, b.getvalue(), consent=True, notice=r.NOTICE)
        data = self.store.consume(self.uid)[1]['wallpaper']
        self.assertNotIn(b'private-marker', data)
        self.assertFalse(Image.open(io.BytesIO(data)).info)
    def test_symlinks_and_writable_store(self):
        m = self.publish()
        image = self.d / m['version'] / 'wallpaper.png'
        image.unlink()
        image.symlink_to('/etc/passwd')
        self.assertIsNone(self.store.consume(self.uid))
        self.store.root.chmod(0o777)
        with self.assertRaises(ValueError):
            r.Store(self.store.root)

if __name__ == '__main__':
    unittest.main(verbosity=2)
