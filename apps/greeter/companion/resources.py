"""T03 bounded display-copy store. No privileged service is installed.

Caller supplies bytes read under the requesting account's credentials, never a
path for a root process to open. A future authenticated broker must bind uid to
its peer credentials. This module must only run in a trusted store owner process.
"""
import contextlib
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import stat
import time
import uuid
import warnings
from PIL import Image

MAX_BYTES = 16 * 1024 * 1024
MAX_PIXELS = 16_000_000
NOTICE = '所选图片和头像将在认证前向这台机器的其他使用者展示。'


def image_copy(data, avatar=False):
    if not isinstance(data, bytes) or not 0 < len(data) <= MAX_BYTES:
        raise ValueError('image byte budget')
    with warnings.catch_warnings():
        warnings.simplefilter('error', Image.DecompressionBombWarning)
        with Image.open(io.BytesIO(data)) as im:
            if im.format not in ('PNG', 'JPEG') or im.width * im.height > MAX_PIXELS or max(im.size) > 8192:
                raise ValueError('image decode budget/format')
            if getattr(im, 'n_frames', 1) != 1:
                raise ValueError('animated input')
            im.load()
            if avatar and max(im.size) > 512:
                im.thumbnail((512, 512))
            clean = Image.new('RGB', im.size)
            clean.paste(im.convert('RGB'))
            out = io.BytesIO()
            clean.save(out, format='PNG')
            result = out.getvalue()
            if len(result) > MAX_BYTES:
                raise ValueError('encoded budget')
            return result, list(clean.size)


class Store:
    def __init__(self, root):
        self.root = Path(root)
        self.owner = os.geteuid()
        # Parent provisioning is an administrator responsibility, not mkdir -p.
        self._directory(self.root)

    def _directory(self, path):
        try:
            path.mkdir(mode=0o755)
            path.chmod(0o755)
        except FileExistsError:
            pass
        s = path.lstat()
        if not stat.S_ISDIR(s.st_mode) or s.st_uid != self.owner or s.st_mode & 0o022:
            raise ValueError('untrusted store directory')

    @contextlib.contextmanager
    def locked(self, uid):
        if type(uid) is not int or not 0 <= uid <= 2**32 - 2:
            raise ValueError('uid')
        d = self.root / str(uid)
        self._directory(d)
        fd = os.open(d / '.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            s = os.fstat(fd)
            if s.st_uid != self.owner or not stat.S_ISREG(s.st_mode) or s.st_nlink != 1 or s.st_mode & 0o077:
                raise ValueError('untrusted lock')
            fcntl.flock(fd, fcntl.LOCK_EX)
            yield d
        finally:
            os.close(fd)

    def _write(self, path, data):
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
        os.fchmod(fd, 0o644)
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())

    def _sync(self, d):
        fd = os.open(d, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)

    def _gc(self, d, keep=None):
        # Sole store of public copies: no separate cache/snapshot directory.
        for p in d.iterdir():
            if (p.name.startswith('v-') or p.name.startswith('.tmp-')) and p.name != keep:
                if p.is_symlink() or not p.is_dir():
                    p.unlink()
                else:
                    shutil.rmtree(p)
        self._sync(d)

    def publish(self, uid, wallpaper, *, consent, notice, mode='image', fit='crop', avatar=None, ttl=86400, fail=None):
        if consent is not True or notice != NOTICE:
            raise ValueError('explicit public-display consent required')
        if mode != 'image' or fit not in ('crop', 'fit', 'stretch', 'center') or type(ttl) is not int or not 1 <= ttl <= 604800:
            raise ValueError('display fields')
        images = {'wallpaper': image_copy(wallpaper)}
        if avatar is not None:
            images['avatar'] = image_copy(avatar, True)
        with self.locked(uid) as d:
            version = 'v-' + uuid.uuid4().hex
            tmp = d / ('.tmp-' + uuid.uuid4().hex)
            tmp.mkdir(mode=0o755)
            tmp.chmod(0o755)
            resources = {}
            for name, (data, size) in images.items():
                self._write(tmp / (name + '.png'), data)
                resources[name] = {'file': name + '.png', 'sha256': hashlib.sha256(data).hexdigest(), 'size': size}
            now = int(time.time())
            manifest = {'schemaVersion': 1, 'uid': uid, 'version': version, 'issuedAt': now, 'expiresAt': now + ttl,
                        'mode': mode, 'fit': fit, 'crop': [0, 0, 1, 1], 'resources': resources}
            self._sync(tmp)
            if fail == 'before-version':
                raise OSError('injected interrupted copy')
            os.rename(tmp, d / version)
            self._sync(d)
            m = d / ('.tmp-' + uuid.uuid4().hex)
            self._write(m, json.dumps(manifest, separators=(',', ':')).encode())
            if fail == 'before-manifest':
                raise OSError('injected interrupted manifest')
            os.replace(m, d / 'manifest.json')
            if fail == 'after-manifest':
                raise OSError('injected interrupted committed cleanup')
            self._sync(d)
            self._gc(d, version)
            return manifest

    def revoke(self, uid, fail=False):
        with self.locked(uid) as d:
            (d / 'manifest.json').unlink(missing_ok=True)
            self._sync(d)
            if fail:
                raise OSError('injected interrupted cleanup')
            self._gc(d)

    def recover(self, uid):
        with self.locked(uid) as d:
            current = self._read(d, uid)
            if current is None:
                (d / 'manifest.json').unlink(missing_ok=True)
            self._gc(d, current[0]['version'] if current else None)

    def _file(self, path, limit):
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, 'rb') as f:
            s = os.fstat(f.fileno())
            if not stat.S_ISREG(s.st_mode) or s.st_uid != self.owner or s.st_nlink != 1 or s.st_mode & 0o022 or s.st_size > limit:
                raise ValueError('untrusted resource')
            return f.read(limit + 1)

    def _read(self, d, uid):
        try:
            m = json.loads(self._file(d / 'manifest.json', 4096))
            if set(m) != {'schemaVersion', 'uid', 'version', 'issuedAt', 'expiresAt', 'mode', 'fit', 'crop', 'resources'}:
                return None
            if type(m['schemaVersion']) is not int or m['schemaVersion'] != 1 or type(m['uid']) is not int or m['uid'] != uid:
                return None
            if not isinstance(m['version'], str) or not re.fullmatch(r'v-[0-9a-f]{32}', m['version']):
                return None
            now = time.time()
            if any(type(m[k]) is not int for k in ('issuedAt', 'expiresAt')) or not m['issuedAt'] <= now < m['expiresAt'] <= m['issuedAt'] + 604800:
                return None
            if type(m['crop']) is not list or any(type(v) is not int for v in m['crop']):
                return None
            if m['mode'] != 'image' or m['fit'] not in ('crop', 'fit', 'stretch', 'center') or m['crop'] != [0, 0, 1, 1]:
                return None
            r = m['resources']
            if not isinstance(r, dict) or set(r) not in ({'wallpaper'}, {'wallpaper', 'avatar'}):
                return None
            version = d / m['version']
            s = version.lstat()
            if not stat.S_ISDIR(s.st_mode) or s.st_uid != self.owner or s.st_mode & 0o022:
                return None
            result = {}
            for name, desc in r.items():
                if not isinstance(desc, dict) or type(desc.get('size')) is not list or any(type(v) is not int for v in desc['size']):
                    return None
                if set(desc) != {'file', 'sha256', 'size'} or desc['file'] != name + '.png':
                    return None
                data = self._file(version / desc['file'], MAX_BYTES)
                if hashlib.sha256(data).hexdigest() != desc['sha256']:
                    return None
                clean, size = image_copy(data, name == 'avatar')
                if size != desc['size'] or clean != data:
                    return None
                result[name] = data
            return m, result
        except (OSError, ValueError, TypeError, KeyError, AttributeError, RecursionError, Image.DecompressionBombError, Image.DecompressionBombWarning):
            return None

    def consume(self, uid):
        # Each reload checks live manifest under the same lock. Returned bytes
        # are scoped to one render; consumers must drop them on revoke/reload.
        with self.locked(uid) as d:
            return self._read(d, uid)
