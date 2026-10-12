#!/usr/bin/env python3
"""No graphical/server discovery: canonical cache preserves live security checks."""
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'companion'))
import resources
from resources import Store,NOTICE
from wallpaper import Reader
from handoff import Runtime,build,read_reference

class OptimizedReferences(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
  self.store=Store(self.root/'store');self.uid=os.geteuid()
  image=io.BytesIO();Image.new('RGB',(320,200),'#b3652a').save(image,format='PNG')
  self.m=self.store.publish(self.uid,image.getvalue(),consent=True,notice=NOTICE)
  self.path=self.store.root/str(self.uid)/self.m['version']/'wallpaper.png'
  self.reader=Reader(self.store.root,self.uid);resources._CANONICAL_DIMENSIONS.clear()
 def tearDown(self):self.tmp.cleanup()
 def test_repeated_consumes_only_encode_once(self):
  with patch.object(resources,'image_copy',wraps=resources.image_copy) as encode:
   first=self.reader.consume(self.uid);second=self.reader.consume(self.uid)
   self.assertEqual(first,second);self.assertEqual(encode.call_count,1)
  self.assertTrue(all(isinstance(size,tuple) for size in resources._CANONICAL_DIMENSIONS.values()))
 def test_cached_validation_does_not_bypass_permissions_or_hash(self):
  self.assertIsNotNone(self.reader.consume(self.uid))
  self.path.chmod(0o666);self.assertIsNone(self.reader.consume(self.uid))
  self.path.chmod(0o644);old=self.path.read_bytes();self.path.write_bytes(old[:-1]+bytes([old[-1]^1]))
  self.assertIsNone(self.reader.consume(self.uid))
 def test_cached_validation_does_not_bypass_manifest_revoke_or_size(self):
  self.reader.consume(self.uid)
  manifest=self.store.root/str(self.uid)/'manifest.json'
  modified=dict(self.m);modified['resources']=json.loads(json.dumps(self.m['resources']))
  modified['resources']['wallpaper']['size']=[319,200];manifest.write_text(json.dumps(modified))
  self.assertIsNone(self.reader.consume(self.uid))
  manifest.write_text(json.dumps(self.m));self.assertIsNotNone(self.reader.consume(self.uid))
  self.store.revoke(self.uid);self.assertIsNone(self.reader.consume(self.uid))
 def test_metadata_only_wrapper_no_image_encode_but_consumer_still_validates(self):
  runtime_dir=self.root/'runtime';runtime_dir.mkdir(mode=0o700);r=Runtime(str(runtime_dir))
  try:
   with patch.object(resources,'image_copy',wraps=resources.image_copy) as encode:
    desc=build(r.session,self.uid,self.store.root,self.uid,verify_resources=False)
    r.write(desc,self.store.root,self.uid,verify_resources=False)
    r.consume(self.store.root,self.uid,remove=False,verify_resources=False)
    self.assertEqual(encode.call_count,0)
   self.path.write_bytes(b'not a PNG')
   self.assertIsNone(read_reference(str(runtime_dir),r.session,r.digest.hex(),self.store.root,self.uid))
  finally:r.close()
 def test_metadata_rejects_symlink_and_expired_publication(self):
  old=self.path.read_bytes();self.path.unlink();self.path.symlink_to(self.root/'elsewhere')
  self.assertIsNone(self.reader.manifest(self.uid))
  self.path.unlink();self.path.write_bytes(old)
  self.m['issuedAt']=1;self.m['expiresAt']=2
  (self.store.root/str(self.uid)/'manifest.json').write_text(json.dumps(self.m))
  self.assertIsNone(self.reader.manifest(self.uid))

if __name__=='__main__':unittest.main()
