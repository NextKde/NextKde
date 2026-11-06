#!/usr/bin/env python3
"""Back up installed runtime trees, then prepare clean trees for deployment."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import tempfile


def present(path):
    return path.exists() or path.is_symlink()


def prepare(prefix, config, state):
    settings = prefix / 'share/kos/settings'
    shell = config / 'quickshell/kos'
    record = prefix / 'share/kos/release.json'
    backups = state / 'kos/install-backups'
    sources = {'settings': settings, 'shell': shell, 'config-kos': config / 'kos'}
    # Do not recursively back up a destination that contains the backups.
    for path in sources.values():
        if backups.resolve().is_relative_to(path.resolve()):
            raise ValueError('Install backup directory must be outside runtime/configuration trees')
    backup = None
    if any(present(path) for path in sources.values()) or record.exists():
        backups.mkdir(parents=True, exist_ok=True)
        backup = Path(tempfile.mkdtemp(prefix=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ-'), dir=backups))
        # Finish every backup before invalidating the old installation or
        # deleting any runtime file. Preserve symlinks without following them.
        for name, path in sources.items():
            if path.is_symlink():
                (backup / name).symlink_to(path.readlink())
            elif path.exists():
                shutil.copytree(path, backup / name, symlinks=True)
        if record.exists():
            shutil.copy2(record, backup / 'release.json')
        (backup / 'backup.json').write_text(json.dumps({
            'complete': True,
            'paths': {name: str(path) for name, path in sources.items()},
            'note': 'Runtime trees and kos settings only; not a complete application-data or system-plugin backup.',
        }, indent=2) + '\n')
    # A failure after this point must not report a complete old installation.
    record.unlink(missing_ok=True)
    for path in (settings, shell):
        if path.is_symlink():
            path.unlink()
        elif path.exists():
            shutil.rmtree(path)
        path.mkdir(parents=True, exist_ok=True)
    return backup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--state', type=Path, required=True)
    args = parser.parse_args()
    backup = prepare(args.prefix, args.config, args.state)
    if backup:
        print(f'Previous runtime and kos settings saved to: {backup}')


if __name__ == '__main__':
    main()
