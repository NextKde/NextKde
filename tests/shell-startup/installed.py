#!/usr/bin/env python3
"""Load deployed Shell trees after destroying the source aliases (VM/CI only)."""
import importlib.util
import os
import time
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MODULES = ('colorize', 'controls', 'foundation', 'i18n', 'wallpapers')


def load(shell, env, log_path, expected_missing=None):
    quickshell = shutil.which('qs') or shutil.which('quickshell')
    with log_path.open('w+') as log:
        process = subprocess.Popen([quickshell, '--path', str(shell), '--no-color'],
                                   env=dict(env, QT_QPA_PLATFORM='wayland'),
                                   stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline:
                log.seek(0)
                text = log.read()
                if (expected_missing and 'Failed to load configuration' in text
                        and expected_missing in text):
                    print(f'PASS: missing {expected_missing} rejected by real QML engine', flush=True)
                    return
                if process.poll() is not None:
                    raise RuntimeError(f'Shell exited before readiness: {text}')
                if 'Configuration Loaded' in text:
                    if expected_missing:
                        raise RuntimeError('Broken installed module unexpectedly loaded')
                    break
                time.sleep(0.2)
            else:
                raise RuntimeError(f'Shell did not load: {text}')
            time.sleep(4)
            if process.poll() is not None:
                raise RuntimeError('Shell died after loading')
            print(f'PASS: {shell} loaded and stayed alive', flush=True)
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            log.seek(0)
            print(log.read(), flush=True)


def run(base_env=None):
    env = dict(os.environ if base_env is None else base_env)
    for kind in ('original', 'empty-directory', 'link-text', 'dangling'):
        with tempfile.TemporaryDirectory(prefix='kos-installed-startup-') as temporary:
            base = Path(temporary)
            source = base / 'source'
            shell = source / 'shell'
            shared = source / 'shared/qml'
            shutil.copytree(ROOT / 'shell', shell, symlinks=True)
            shutil.copytree(ROOT / 'shared/qml', shared)
            shutil.copytree(ROOT / 'shared/Icons', source / 'shared/Icons')
            aliases = [shell / 'shared/qml' / name
                       for name in ('controls', 'foundation', 'i18n')]
            aliases += [shell / 'Kos/Ui' / name for name in MODULES]
            for alias in ([] if kind == 'original' else aliases):
                if alias.is_symlink() or alias.is_file():
                    alias.unlink()
                elif alias.exists():
                    shutil.rmtree(alias)
                if kind == 'empty-directory':
                    alias.mkdir()
                elif kind == 'link-text':
                    alias.write_text('../../../shared/qml/' + alias.name)
                else:
                    alias.symlink_to(source / 'does-not-exist')
            installed = base / 'installed'
            subprocess.run(['python3', str(ROOT / 'tools/deploy/deploy-shell-qml.py'),
                            'deploy', '--shell', str(shell), '--shared', str(shared),
                            '--destination', str(installed)], check=True)
            # A successful load must not be rescued by files in the input tree.
            shutil.rmtree(source)
            print(f'Loading installed Shell after {kind} damage', flush=True)
            load(installed, env, base / 'shell.log')
            if kind == 'original':
                # Prove this is a runtime regression gate, not merely a file
                # copier check: removing a real imported catalog must fail.
                (installed / 'shared/qml/i18n/ZhCatalog.mjs').unlink()
                load(installed, env, base / 'missing-catalog.log', 'ZhCatalog.mjs')


if __name__ == '__main__':
    # Reuse the existing isolated KWin/bus launcher, which does not activate
    # the real desktop's services or write its configuration.
    spec = importlib.util.spec_from_file_location('fixture', ROOT / 'tests/widget-experience/run.py')
    fixture = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fixture)
    fixture.run = run
    fixture.__file__ = __file__
    fixture.main()
