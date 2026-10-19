#!/usr/bin/env python3
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'companion'))
from kos_wallpaper import current, disable, NOTICE

class KosWallpaper(unittest.TestCase):
    def test_current_fit_urls_consent_and_failures(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); config=root/'quickshell/kos'; config.mkdir(parents=True)
            image=root/'图 100%.png'; Image.new('RGB',(73,51),'#cd8765').save(image)
            ini=config/'wallpaper.ini'; consent=config/'greeter-display.json'
            self.assertEqual(current(root,True),{'schemaVersion':1,'enabled':False})
            consent.write_text(json.dumps(dict(schemaVersion=1,uid=os.getuid(),enabled=True,notice=NOTICE))); consent.chmod(0o600)
            for fit in ('crop','fit','stretch','center'):
                ini.write_text('[Wallpaper]\nmode=image\ntakeoverEnabled=true\nfitMode='+fit+'\nimage='+image.as_uri()+'\n')
                self.assertEqual(current(root,True)['fit'],fit)
            ini.write_text('[Wallpaper]\nmode=theme\ntakeoverEnabled=true\nimage='+str(image)+'\n')
            self.assertEqual(current(root,True)['size'],[1,1])
            ini.write_text('[Wallpaper]\nmode=image\ntakeoverEnabled=false\nimage='+str(image)+'\n')
            with self.assertRaises(ValueError): current(root,True)
            disable(root)
            self.assertEqual(current(root,True),{'schemaVersion':1,'enabled':False})
            self.assertEqual(consent.stat().st_mode & 0o777,0o600)

unittest.main()
