#!/usr/bin/env python3
"""Read-only system-bus identity snapshot. No authentication or home access."""
import base64
import io
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import time

SERVICE = 'org.freedesktop.Accounts'

def call(*args):
    result = subprocess.run(['/usr/bin/busctl', '--system', '--timeout=1', '--json=short', *args],
                            capture_output=True, timeout=2, check=True)
    return json.loads(result.stdout)['data']

def avatar(path):
    # Only administrator-managed icons; never follow links or read users' homes.
    try:
        source = Path(path)
        if source.parent != Path('/var/lib/AccountsService/icons'):
            return ''
        for parent in reversed(source.parents):
            info = parent.lstat()
            # AccountsService commonly provisions icons as root:root 0775.
            # Only these fixed directories permits root-group write; files remain
            # root-owned and non-writable by any group or other user.
            allowed = 0o020 if parent in (Path('/var/lib/AccountsService'), Path('/var/lib/AccountsService/icons')) and info.st_gid == 0 else 0
            if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_mode & (0o022 & ~allowed):
                return ''
        fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, 'rb') as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022 or info.st_size > 1048576:
                return ''
            raw = stream.read(1048577)
        from PIL import Image, ImageDraw, ImageOps, ImageChops
        with Image.open(io.BytesIO(raw)) as image:
            if image.format not in ('PNG', 'JPEG') or image.width * image.height > 1048576 or getattr(image, 'n_frames', 1) != 1:
                return ''
            image.load()
            image = ImageOps.fit(image.convert('RGBA'), (96, 96), method=Image.Resampling.LANCZOS)
            mask = Image.new('L', (384, 384))
            ImageDraw.Draw(mask).ellipse((0, 0, 383, 383), fill=255)
            mask = mask.resize((96, 96), Image.Resampling.LANCZOS)
            image.putalpha(ImageChops.multiply(image.getchannel('A'), mask))
            output = io.BytesIO()
            image.save(output, format='PNG')
        return 'data:image/png;base64,' + base64.b64encode(output.getvalue()).decode('ascii')
    except Exception:
        return ''

def normalize(fields):
    uid, name = fields.get('Uid'), fields.get('UserName')
    if type(uid) is not int or not 0 <= uid <= 4294967295:
        return None
    if not isinstance(name, str) or not name or len(name) > 256 or any(ord(c) < 32 for c in name):
        return None
    real = fields.get('RealName', '')
    if not isinstance(real, str):
        real = ''
    real = ''.join(c for c in real if ord(c) >= 32).strip()[:256]
    return {'uid': uid, 'username': name, 'displayName': real or name, 'avatar': avatar(fields.get('IconFile', ''))}

def snapshot(reader=call):
    users, seen = [], set()
    deadline = time.monotonic() + 6
    try:
        paths = reader('call', SERVICE, '/org/freedesktop/Accounts', SERVICE, 'ListCachedUsers')[0]
        for path in paths[:32]:
            if time.monotonic() > deadline:
                break
            if not isinstance(path, str) or not re.fullmatch(r'/org/freedesktop/Accounts/User[0-9]+', path):
                continue
            try:
                fields = {key: reader('get-property', SERVICE, path, SERVICE + '.User', key)
                          for key in ('Uid', 'UserName', 'RealName', 'IconFile')}
                user = normalize(fields)
                if user and user['uid'] not in seen:
                    seen.add(user['uid']); users.append(user)
            except Exception:
                continue
    except Exception:
        pass
    return users

if __name__ == '__main__':
    print(json.dumps(snapshot(), ensure_ascii=True))
