#!/usr/bin/env python3
"""Materialize Shell's shared QML from canonical files, never checkout aliases."""
import argparse
from pathlib import Path
import re
import shutil
import tempfile

MODULES = ('colorize', 'controls', 'foundation', 'i18n', 'wallpapers')


def require_file(path):
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f'Missing or empty QML runtime file: {path}')


def check_qmldir(path, root=None):
    require_file(path)
    base = root or path.parent
    for line in path.read_text().splitlines():
        fields = line.split('#', 1)[0].split()
        if fields and fields[-1].endswith(('.qml', '.js', '.mjs')):
            require_file(base / fields[-1])


def check_shared(shared):
    for name in MODULES:
        require_file(shared / name / 'qmldir')
    for qmldir in shared.rglob('qmldir'):
        check_qmldir(qmldir)
    # qmldir alone does not cover JS catalogs imported by I18n.qml, for example.
    for file in shared.rglob('*.qml'):
        for target in re.findall(r'^\s*import\s+"([^"]+)"', file.read_text(), re.M):
            imported = file.parent / target
            if not imported.exists():
                raise ValueError(f'Missing QML import {target!r} in {file}')
            if imported.is_file():
                require_file(imported)


def check_sources(shell, shared):
    require_file(shell / 'shell.qml')
    check_shared(shared)
    check_qmldir(shell / 'Kos/Ui/qmldir', shared)


def check_installed(shell):
    require_file(shell / 'shell.qml')
    check_shared(shell / 'shared/qml')
    check_shared(shell / 'Kos/Ui')
    check_qmldir(shell / 'Kos/Ui/qmldir')


def deploy(shell, shared, destination):
    check_sources(shell, shared)
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Stage and validate before replacing the destination. Ignore the aliases
    # before copytree follows links: even dangling links/plain files are safe.
    with tempfile.TemporaryDirectory(prefix='.kos-qml-', dir=destination.parent) as temporary:
        staged = Path(temporary) / 'shell'
        def ignore(directory, names):
            relative = Path(directory).relative_to(shell)
            if relative == Path('shared'):
                return {'qml'}
            if relative == Path('Kos'):
                return {'Ui'}
            return set()
        shutil.copytree(shell, staged, ignore=ignore)
        # Nix input directories are read-only; enable writing before adding
        # canonical modules into the copied parent directories.
        for path in [staged, *staged.rglob('*')]:
            path.chmod(path.stat().st_mode | (0o700 if path.is_dir() else 0o600))
        def runtime_only(directory, names):
            return {n for n in names if n == 'CMakeLists.txt' or (n.startswith('test_') and n.endswith('.mjs'))}
        shutil.copytree(shared, staged / 'shared/qml', ignore=runtime_only)
        shutil.copytree(shared, staged / 'Kos/Ui', ignore=runtime_only)
        shutil.copy2(shell / 'Kos/Ui/qmldir', staged / 'Kos/Ui/qmldir')
        check_installed(staged)
        # Nix store input may carry read-only modes; the installed runtime must
        # be replaceable on the next deployment, like cp --no-preserve=mode.
        for path in staged.rglob('*'):
            path.chmod(path.stat().st_mode | (0o700 if path.is_dir() else 0o600))
        if destination.is_symlink():
            destination.unlink()
        elif destination.exists():
            shutil.rmtree(destination)
        staged.rename(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('check', 'deploy'))
    parser.add_argument('--shell', type=Path, required=True)
    parser.add_argument('--shared', type=Path, required=True)
    parser.add_argument('--destination', type=Path)
    args = parser.parse_args()
    try:
        if args.action == 'check':
            check_sources(args.shell, args.shared)
        else:
            if args.destination is None:
                parser.error('deploy requires --destination')
            deploy(args.shell, args.shared, args.destination)
    except (OSError, ValueError, shutil.Error) as error:
        parser.exit(1, f'Shell QML deployment failed: {error}\nRestore the complete source/package and retry installation.\n')


if __name__ == '__main__':
    main()
