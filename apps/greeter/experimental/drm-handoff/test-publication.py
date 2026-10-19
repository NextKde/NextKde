#!/usr/bin/env python3
"""Native C++ publication parser tests in a synthetic root-user/mount namespace."""
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import zlib

probe = str(Path(sys.argv[1]).resolve())

def chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 16, 16, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress((b'\0' + b'\x16\x28\x3b' * 16) * 16)) + chunk(b'IEND', b'')
now = int(time.time())
version = 'v-' + '1' * 32
base = dict(schemaVersion=1, uid=0, version=version, issuedAt=now-1, expiresAt=now+120, mode='image', fit='crop', crop=[0,0,1,1], resources={'wallpaper': {'file':'wallpaper.png', 'sha256':hashlib.sha256(png).hexdigest(), 'size':[16,16]}})

def run(name, mutate, expected):
    with tempfile.TemporaryDirectory(prefix='kos-publication-', dir=str(Path.home()/'.cache/nextkde-builds/drm-handoff')) as temp:
        root = Path(temp); account=root/'0'; account.mkdir(mode=0o755); image_dir=account/version; image_dir.mkdir(mode=0o755)
        (image_dir/'wallpaper.png').write_bytes(png)
        manifest=copy.deepcopy(base)
        mutate(manifest, account)
        (account/'manifest.json').write_text(json.dumps(manifest))
        if name=='writable-manifest': (account/'manifest.json').chmod(0o666)
        if name=='revoked': (account/'manifest.json').unlink()
        command=['bwrap','--unshare-all','--uid','0','--gid','0','--tmpfs','/','--ro-bind','/usr','/usr','--tmpfs','/usr/local','--symlink','usr/bin','/bin','--symlink','usr/lib','/lib','--symlink','usr/lib','/lib64','--dir','/var/lib/kos/greeter/display','--ro-bind',temp,'/var/lib/kos/greeter/display','--ro-bind',probe,'/probe','--dev','/dev','--proc','/proc','/probe']
        result=subprocess.run(command,capture_output=True,text=True,timeout=5)
        if result.returncode != expected:
            raise AssertionError((name, result.returncode, result.stdout, result.stderr))
        print(name+': PASS')

run('valid-cover',lambda m,d:None,0)
run('valid-contain',lambda m,d:m.update(fit='fit'),0)
run('wrong-uid',lambda m,d:m.update(uid=1),1)
run('bad-hash',lambda m,d:m['resources']['wallpaper'].update(sha256='0'*64),1)
run('bad-dimensions',lambda m,d:m['resources']['wallpaper'].update(size=[15,16]),1)
run('unsupported-fit',lambda m,d:m.update(fit='stretch'),1)
run('too-soon-expiry',lambda m,d:m.update(expiresAt=now+20),1)
run('future-issued',lambda m,d:m.update(issuedAt=now+20),1)
run('unknown-field',lambda m,d:m.update(command='unused'),1)
run('writable-manifest',lambda m,d:None,1)
run('revoked',lambda m,d:None,1)
def symlink(m,d):
    shutil.rmtree(d/version); (d/version).symlink_to('/usr')
run('symlink-version',symlink,1)
run('malformed-avatar',lambda m,d:m['resources'].update(avatar={'file':'avatar.png','sha256':'0'*64,'size':[2048,2048]}),1)
run('missing-avatar',lambda m,d:m['resources'].update(avatar={'file':'avatar.png','sha256':'0'*64,'size':[16,16]}),1)
print('14 native publication scenarios passed; no host authentication/display access')
