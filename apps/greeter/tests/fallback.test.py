#!/usr/bin/env python3
"""T12 public static fallback: production preparation and consumer helpers."""
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from PIL import Image
APP = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(APP/'companion'))
from kos_wallpaper import current, NOTICE as ACCOUNT_NOTICE
from resources import Store, NOTICE, image_copy
from entry import published_bytes

class Fallback(unittest.TestCase):
    def test_all_modes_and_revocation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); config=root/'quickshell/kos'; config.mkdir(parents=True)
            consent=config/'greeter-display.json'
            consent.write_text(json.dumps(dict(schemaVersion=1,uid=os.getuid(),enabled=True,notice=ACCOUNT_NOTICE))); consent.chmod(0o600)
            ini=config/'wallpaper.ini'; store=Store(root/'public')
            for theme in ('starfield','blackhole','weather','forest','underwater','file:///untrusted.qml'):
                ini.write_text('[Wallpaper]\nmode=theme\ntakeoverEnabled=true\nfitMode=crop\nthemeId='+theme+'\n')
                start=time.perf_counter(); state=current(root,True)
                data=base64.b64decode(state['image']); im=Image.open(io.BytesIO(data)); im.load()
                manifest=store.publish(os.geteuid(),data,consent=True,notice=NOTICE,fit=state['fit'])
                digest=manifest['resources']['wallpaper']['sha256']; version=manifest['version']
                args=(digest,version,state['fit'],root/'public',os.geteuid())
                self.assertEqual(published_bytes(*args), image_copy(data)[0])
                self.assertIsNone(published_bytes(digest,'v-'+'0'*32,state['fit'],root/'public',os.geteuid()))
                self.assertIsNone(published_bytes(digest,version,'fit',root/'public',os.geteuid()))
                store.revoke(os.geteuid()); self.assertIsNone(published_bytes(*args))
                print(f'{theme}: static {im.size}, {len(data)} bytes, prepare/publish/consume {time.perf_counter()-start:.3f}s')
            # Spatial mode uses the original 2D source at neutral perspective.
            original=root/'space.png'; Image.new('RGB',(96,64),'#345678').save(original)
            ini.write_text('[Wallpaper]\nmode=image\ntakeoverEnabled=true\nfitMode=crop\nimage='+str(original)+'\n')
            self.assertEqual(base64.b64decode(current(root,True)['image']),image_copy(original.read_bytes())[0])
            consent.unlink(); self.assertEqual(current(root,True),dict(schemaVersion=1,enabled=False))

    def test_corruption_replacement_and_expiry(self):
        with tempfile.TemporaryDirectory() as temp:
            store=Store(Path(temp)/'public'); out=io.BytesIO(); Image.new('RGB',(12,8)).save(out,format='PNG')
            old=store.publish(os.geteuid(),out.getvalue(),consent=True,notice=NOTICE)
            args=(old['resources']['wallpaper']['sha256'],old['version'],'crop',store.root,os.geteuid())
            uid=store.root/str(os.geteuid())
            manifest_path=uid/'manifest.json'
            m=json.loads(manifest_path.read_text()); m['expiresAt']=0; manifest_path.write_text(json.dumps(m))
            self.assertIsNone(published_bytes(*args))
            new=store.publish(os.geteuid(),out.getvalue(),consent=True,notice=NOTICE)
            self.assertIsNone(published_bytes(*args))
            resource=uid/new['version']/new['resources']['wallpaper']['file']; resource.write_bytes(b'broken')
            self.assertIsNone(published_bytes(new['resources']['wallpaper']['sha256'],new['version'],'crop',store.root,os.geteuid()))

if __name__=='__main__': unittest.main()
