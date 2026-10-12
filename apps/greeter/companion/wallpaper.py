"""Read-only T03 consumer; emits bytes, never filesystem URLs or theme code."""
import base64
import contextlib
import json
import os
from pathlib import Path
import sys
from resources import Store

class Reader(Store):
    def __init__(self, root, owner=0):
        self.root = Path(root)
        self.owner = owner
        self._directory(self.root)

    def _directory(self, path):
        import stat
        s = path.lstat()
        if not stat.S_ISDIR(s.st_mode) or s.st_uid != self.owner or s.st_mode & 0o022:
            raise ValueError('untrusted display directory')

    @contextlib.contextmanager
    def locked(self, uid):
        if type(uid) is not int or not 0 <= uid <= 2**32 - 2:
            raise ValueError('uid')
        self._directory(self.root)
        d = self.root / str(uid)
        self._directory(d)
        # Atomic manifest replacement; a concurrent GC fails closed. No writes.
        yield d


def snapshot(root, uid, owner=0):
    try:
        current = Reader(root, owner).consume(uid)
        if current:
            manifest, images = current
            return dict(uid=uid, source='data:image/png;base64,' + base64.b64encode(images['wallpaper']).decode(),
                        fit=manifest['fit'], sha256=manifest['resources']['wallpaper']['sha256'],
                        version=manifest['version'])
    except (OSError, ValueError):
        pass
    return dict(uid=uid, source='', fit='crop', sha256='', version='default')

def temporary_snapshot(app, uid, owner=0):
    """A root-owned temporary app provides its own T03 public copies."""
    try:
        reader = Reader(app, owner)
        reader._directory(Path(app) / 'config')
        metadata = json.loads(reader._file(Path(app) / 'config/wallpaper.json', 256))
        if set(metadata) != {'schemaVersion', 'defaultUid'} or type(metadata['schemaVersion']) is not int or metadata['schemaVersion'] != 1:
            raise ValueError('temporary display schema')
        default = metadata['defaultUid']
        if type(default) is not int or not 0 <= default <= 2**32 - 2:
            raise ValueError('default UID')
        actual = default if uid == -1 else uid
        result = snapshot(Path(app) / 'public-display', actual, owner)
        result['uid'] = uid
        return result
    except (OSError, ValueError, TypeError):
        return dict(uid=uid, source='', fit='crop', sha256='', version='default')

if __name__ == '__main__':
    uid = int(sys.argv[1]) if len(sys.argv) == 2 else -1
    app = Path(__file__).resolve().parents[1]
    if app in (Path('/run/kos-greeter-test/app'), Path('/usr/local/lib/kos-greeter/app')):
        result = temporary_snapshot(app, uid)
    else:
        result = snapshot('/var/lib/kos/greeter/display', uid)
    print(json.dumps(result, separators=(',', ':')))
