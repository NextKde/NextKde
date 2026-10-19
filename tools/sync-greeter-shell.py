#!/usr/bin/env python3
"""Explicit user-only QML synchronization; no service or process changes."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import tempfile
import time
import uuid

REPO = Path(__file__).resolve().parents[1]


def inventory(directory):
    return {str(p.relative_to(directory)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in directory.rglob('*') if p.is_file()}


def synchronize(target, check=False):
    if target.is_symlink() or not target.is_dir() or not (target/'shell.qml').is_file():
        raise RuntimeError('Expected an existing user Shell installation: ' + str(target))
    # Preserve native plugins and unrelated installed directories.
    if (target/'desktop').is_symlink() or (target/'Kos').is_symlink():
        raise RuntimeError('Managed desktop/Kos directories must not be symlinks')
    with tempfile.TemporaryDirectory(prefix='.kos-shell-stage-', dir=target.parent) as temp:
        stage = Path(temp)
        shutil.copytree(REPO/'shell/desktop', stage/'desktop', symlinks=False)
        shutil.copytree(target/'Kos', stage/'Kos', symlinks=False)
        shutil.rmtree(stage/'Kos/Ui', ignore_errors=True)
        shutil.copytree(REPO/'shell/Kos/Ui', stage/'Kos/Ui', symlinks=False)
        before = {k: v for k,v in inventory(target).items() if k.startswith(('desktop/', 'Kos/'))}
        after = inventory(stage)
        for key in sorted(before.keys() | after.keys()):
            if before.get(key) != after.get(key):
                print(('ADD ' if key not in before else 'REMOVE ' if key not in after else 'UPDATE ') + key)
        backup = target.parent / ('kos-shell-backup-' + time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8])
        print('Backup: ' + str(backup))
        if check: return
        if before == after:
            print('Shell QML already synchronized.'); return
        backup.mkdir(mode=0o700)
        replaced = []
        try:
            for name in ('desktop', 'Kos'):
                os.rename(target/name, backup/name)
                replaced.append(name)
                os.rename(stage/name, target/name)
        except BaseException:
            for name in reversed(replaced):
                if (target/name).exists(): shutil.rmtree(target/name)
                os.rename(backup/name, target/name)
            raise
        print('Synchronized. Current session was not restarted. Backup retained.')
        print('Restore while Shell is stopped: replace desktop and Kos with those in ' + str(backup))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', '--dry-run', action='store_true', dest='check')
    parser.add_argument('--target', type=Path, default=Path.home()/'.config/quickshell/kos')
    args = parser.parse_args()
    if os.geteuid() == 0: parser.error('Run as the desktop user, without sudo')
    try: synchronize(args.target.absolute(), args.check)
    except (OSError, RuntimeError) as error: parser.exit(1, str(error) + '\n')
