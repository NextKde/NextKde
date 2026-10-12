"""T09 session-scoped static display contract. No commands or supplied paths."""
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import stat
import time
import uuid
from wallpaper import Reader

MAX_JSON = 16384
APP = Path(__file__).resolve().parents[1]
PUBLIC_ROOT = APP / 'public-display' if APP == Path('/usr/local/lib/kos-greeter/app') else Path('/var/lib/kos/greeter/display')


def keys(value, expected):
    if type(value) is not dict or set(value) != set(expected.split()):
        raise ValueError('fields')


def number(value, low, high):
    if type(value) not in (int, float) or not low <= value <= high or not math.isfinite(value):
        raise ValueError('numeric-range')


def parse(raw):
    if type(raw) is not bytes or len(raw) > MAX_JSON:
        raise ValueError('json-budget')
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('duplicate-field')
            result[key] = value
        return result
    try:
        return json.loads(raw.decode('utf-8'), object_pairs_hook=pairs)
    except (UnicodeError, RecursionError) as error:
        raise ValueError('invalid-json') from error


def validate(desc, session, uid, root=PUBLIC_ROOT, owner=0, now=None):
    keys(desc, 'schemaVersion sessionId issuedAt expiresAt user resource wallpaper outputs transition')
    if type(desc['schemaVersion']) is not int or desc['schemaVersion'] != 1:
        raise ValueError('schema')
    if not re.fullmatch(r'[0-9a-f]{32}', session) or desc['sessionId'] != session:
        raise ValueError('session')
    keys(desc['user'], 'uid')
    if type(desc['user']['uid']) is not int or desc['user']['uid'] != uid:
        raise ValueError('uid')
    now = time.time() if now is None else now
    a, b = desc['issuedAt'], desc['expiresAt']
    if type(a) is not int or type(b) is not int or not a <= now < b <= a + 120:
        raise ValueError('expired')
    keys(desc['wallpaper'], 'kind fit phase')
    w = desc['wallpaper']
    if w['kind'] != 'image' or w['fit'] not in ('crop', 'fit', 'stretch', 'center') or w['phase'] is not None:
        raise ValueError('static-only')
    keys(desc['transition'], 'suppressInitialWallpaperTransition exitDurationMs revealDurationMs')
    t = desc['transition']
    if t['suppressInitialWallpaperTransition'] is not True:
        raise ValueError('transition')
    for k in ('exitDurationMs', 'revealDurationMs'):
        if type(t[k]) is not int or not 0 <= t[k] <= 1000:
            raise ValueError('duration')
    if type(desc['outputs']) is not list or len(desc['outputs']) > 16:
        raise ValueError('outputs')
    connectors = set()
    for o in desc['outputs']:
        keys(o, 'connector hardwareId width height refreshHz scale rotation position crop vrr hdr')
        for k in ('connector', 'hardwareId'):
            if type(o[k]) is not str or not re.fullmatch(r'[A-Za-z0-9_.:-]{1,128}', o[k]):
                raise ValueError('output-id')
        if o['connector'] in connectors:
            raise ValueError('duplicate-output')
        connectors.add(o['connector'])
        for k in ('width', 'height'):
            if type(o[k]) is not int or not 1 <= o[k] <= 16384:
                raise ValueError('dimensions')
        number(o['refreshHz'], 1, 1000); number(o['scale'], .5, 4)
        if type(o['rotation']) is not int or o['rotation'] not in (0, 90, 180, 270):
            raise ValueError('rotation')
        if type(o['position']) is not list or len(o['position']) != 2 or any(type(v) is not int or abs(v) > 32768 for v in o['position']):
            raise ValueError('position')
        if type(o['crop']) is not list or len(o['crop']) != 4:
            raise ValueError('crop')
        for v in o['crop']: number(v, 0, 1)
        x, y, width, height = o['crop']
        if width <= 0 or height <= 0 or x + width > 1 or y + height > 1:
            raise ValueError('crop')
        if o['vrr'] not in ('never', 'automatic', 'always') or type(o['hdr']) is not bool:
            raise ValueError('output-policy')
    r = desc['resource']
    keys(r, 'version sha256')
    if r == {'version': 'default', 'sha256': ''}:
        if w['fit'] != 'crop': raise ValueError('default-fit')
        return desc
    if type(r['version']) is not str or not re.fullmatch(r'v-[0-9a-f]{32}', r['version']) or type(r['sha256']) is not str or not re.fullmatch(r'[0-9a-f]{64}', r['sha256']):
        raise ValueError('resource-id')
    current = Reader(root, owner).consume(uid)
    if not current:
        raise ValueError('resource-unavailable')
    manifest, images = current
    if manifest['version'] != r['version'] or hashlib.sha256(images['wallpaper']).hexdigest() != r['sha256'] or manifest['fit'] != w['fit']:
        raise ValueError('resource-replaced')
    return desc


def build(session, uid, root=PUBLIC_ROOT, owner=0):
    now = int(time.time())
    d = dict(schemaVersion=1, sessionId=session, issuedAt=now, expiresAt=now+120,
             user={'uid': uid}, resource={'version': 'default', 'sha256': ''},
             wallpaper={'kind': 'image', 'fit': 'crop', 'phase': None}, outputs=[],
             transition={'suppressInitialWallpaperTransition': True, 'exitDurationMs': 240, 'revealDurationMs': 240})
    try:
        current = Reader(root, owner).consume(uid)
        if current:
            m, _ = current
            d['resource'] = {'version': m['version'], 'sha256': m['resources']['wallpaper']['sha256']}
            d['wallpaper']['fit'] = m['fit']
    except (OSError, ValueError):
        pass
    return d


class Runtime:
    """Hold directory descriptors; never clean other sessions or follow links."""
    def __init__(self, runtime):
        self.uid = os.geteuid()
        self.session = uuid.uuid4().hex
        self.fd = self.parent = None
        self.identity = None
        path = Path(runtime)
        if not path.is_absolute() or path.resolve() != path:
            raise ValueError('runtime-path')
        self.base = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            self._secure(self.base, directory=True)
            self.parent = os.open('.', os.O_RDONLY | os.O_DIRECTORY, dir_fd=self.base)
            os.mkdir('kos-handoff-' + self.session, 0o700, dir_fd=self.base)
            self.fd = os.open('kos-handoff-' + self.session, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=self.base)
            os.fchmod(self.fd, 0o700)
            s = os.fstat(self.fd); self.identity = (s.st_dev, s.st_ino)
        except BaseException:
            self.close()
            raise

    def _secure(self, fd, directory=False):
        s = os.fstat(fd)
        if s.st_uid != self.uid or s.st_mode & 0o077 or not (stat.S_ISDIR(s.st_mode) if directory else stat.S_ISREG(s.st_mode) and s.st_nlink == 1):
            raise ValueError('runtime-permission')
        return s


    def write(self, desc, root=PUBLIC_ROOT, owner=0):
        validate(desc, self.session, self.uid, root, owner)
        raw = json.dumps(desc, allow_nan=False, separators=(',', ':')).encode()
        if len(raw) > MAX_JSON: raise ValueError('json-budget')
        temp = '.tmp-' + uuid.uuid4().hex
        fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=self.fd)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, 'wb') as out:
                out.write(raw); out.flush(); os.fsync(out.fileno())
            os.replace(temp, 'handoff.json', src_dir_fd=self.fd, dst_dir_fd=self.fd)
            os.fsync(self.fd)
            s = os.stat('handoff.json', dir_fd=self.fd, follow_symlinks=False)
            self.file_identity = (s.st_dev, s.st_ino)
            self.digest = hashlib.sha256(raw).digest()
        finally:
            try: os.unlink(temp, dir_fd=self.fd)
            except FileNotFoundError: pass

    def consume(self, root=PUBLIC_ROOT, owner=0, remove=True):
        fd = os.open('handoff.json', os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=self.fd)
        with os.fdopen(fd, 'rb') as src:
            s = self._secure(src.fileno())
            if (s.st_dev, s.st_ino) != self.file_identity or s.st_size > MAX_JSON:
                raise ValueError('file-replaced')
            raw = src.read(MAX_JSON+1)
        if hashlib.sha256(raw).digest() != self.digest: raise ValueError('file-modified')
        result = validate(parse(raw), self.session, self.uid, root, owner)
        if remove: os.unlink('handoff.json', dir_fd=self.fd)
        return result

    def lock(self):
        # Persistent inode: unlinking a flock file would allow split locks.
        fd = os.open('kos-desktop-session.lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600, dir_fd=self.base)
        try:
            self._secure(fd)
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return fd
        except BaseException:
            os.close(fd)
            raise

    def close(self):
        if self.fd is not None:
            try: os.unlink('handoff.json', dir_fd=self.fd)
            except FileNotFoundError: pass
            os.close(self.fd); self.fd = None
        if self.parent is not None:
            name = 'kos-handoff-' + self.session
            try:
                s = os.stat(name, dir_fd=self.parent, follow_symlinks=False)
                if (s.st_dev, s.st_ino) == self.identity:
                    os.rmdir(name, dir_fd=self.parent)
            except (FileNotFoundError, OSError): pass
            os.close(self.parent); self.parent = None
        if getattr(self, 'base', None) is not None:
            os.close(self.base); self.base = None


def read_reference(runtime_path, session, digest, root=PUBLIC_ROOT, owner=0):
    """T10 entry: local wrapper reference, single-use; invalid input => default.

    Resolve only the derived name below real XDG_RUNTIME_DIR, not a supplied
    filename. Consumers must revalidate the public version on every reload.
    """
    base = directory = file_fd = None
    try:
        if type(session) is not str or not re.fullmatch(r'[0-9a-f]{32}', session): raise ValueError('session')
        if type(digest) is not str or not re.fullmatch(r'[0-9a-f]{64}', digest): raise ValueError('digest')
        path = Path(runtime_path)
        if not path.is_absolute() or path.resolve() != path: raise ValueError('runtime-path')
        def secure(fd, is_dir):
            s = os.fstat(fd)
            if s.st_uid != os.geteuid() or s.st_mode & 0o077 or not (stat.S_ISDIR(s.st_mode) if is_dir else stat.S_ISREG(s.st_mode) and s.st_nlink == 1):
                raise ValueError('runtime-permission')
            return s
        base = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        secure(base, True)
        directory = os.open('kos-handoff-' + session, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=base)
        secure(directory, True)
        file_fd = os.open('handoff.json', os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
        s = secure(file_fd, False)
        if s.st_size > MAX_JSON: raise ValueError('json-budget')
        raw = os.read(file_fd, MAX_JSON + 1)
        if hashlib.sha256(raw).hexdigest() != digest: raise ValueError('file-replaced')
        desc = validate(parse(raw), session, os.geteuid(), root, owner)
        current = os.stat('handoff.json', dir_fd=directory, follow_symlinks=False)
        if (s.st_dev, s.st_ino) != (current.st_dev, current.st_ino): raise ValueError('file-replaced')
        os.unlink('handoff.json', dir_fd=directory)
        return desc
    except (OSError, ValueError, TypeError, KeyError):
        return None
    finally:
        for fd in (file_fd, directory, base):
            if fd is not None: os.close(fd)
