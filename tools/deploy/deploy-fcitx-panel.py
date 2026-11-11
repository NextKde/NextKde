#!/usr/bin/env python3
"""Install NextKde's inert-by-default Fcitx adapter in userspace."""
import argparse
import os
from pathlib import Path
import shutil
import tempfile


def install(library, template, prefix, addon_dir):
    destination = prefix.absolute() / 'lib/fcitx5/libnextkde-inputpanel.so'
    # Fcitx uses semicolons to separate libraries in this field.
    if any(character in str(destination) for character in (';', '\n', '\r')):
        raise ValueError('Fcitx addon library path cannot contain semicolons or newlines')
    content = template.read_text().replace('@NEXTKDE_PANEL_LIBRARY@', str(destination)[:-3])
    if not library.is_file():
        raise FileNotFoundError(library)
    destination.parent.mkdir(parents=True, exist_ok=True)
    addon_dir.mkdir(parents=True, exist_ok=True)
    # Replace directory entries: Fcitx may still have the old library mapped.
    fd, pending = tempfile.mkstemp(prefix='.nextkde-panel-', dir=destination.parent)
    os.close(fd)
    try:
        shutil.copyfile(library, pending)
        os.chmod(pending, 0o755)
        os.replace(pending, destination)
    finally:
        Path(pending).unlink(missing_ok=True)
    fd, pending = tempfile.mkstemp(prefix='.nextkde-panel-', dir=addon_dir)
    try:
        with os.fdopen(fd, 'w') as output:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(pending, 0o644)
        os.replace(pending, addon_dir / 'nextkde-inputpanel.conf')
    finally:
        Path(pending).unlink(missing_ok=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('library', 'template', 'prefix', 'addon-dir'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    install(args.library, args.template, args.prefix, args.addon_dir)
