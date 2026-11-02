#!/usr/bin/env python3
"""Run GTK behavior checks against a newly built bridge in a nested KWin (VM only)."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def session(output, glyph_mode):
    subprocess.run(['qdbus6', 'org.kde.KWin', '/Scripting',
                    'org.kde.kwin.Scripting.loadScript', str(HERE / 'minimize-probe.js'), 'gtk201'], check=True)
    subprocess.run(['qdbus6', 'org.kde.KWin', '/Scripting', 'org.kde.kwin.Scripting.start'], check=True)
    failures = []
    for version in ('3.0', '4.0'):
        for dark in (False, True):
            name = f'gtk{version}-' + ('dark' if dark else 'light')
            command = [sys.executable, str(HERE / 'native_controls.py'), version,
                       '--glyph-mode', glyph_mode,
                       '--kwin-log', str(output / 'kwin.log')]
            if dark:
                command.append('--dark')
            with (output / f'{name}.log').open('w') as log:
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=25)
            if result.returncode:
                failures.append(name)
    return bool(failures)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plugin', type=Path, help='Path to newly built kos_bridge.so')
    parser.add_argument('--settings', type=Path, help='Built Settings binary: exercise the shared appearance switch')
    parser.add_argument('--glyph-mode', choices=['always', 'hover'], default='always')
    parser.add_argument('--output', type=Path, required=True, help='New directory for isolated configuration and logs')
    parser.add_argument('--session', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    output = args.output.resolve()
    if args.session:
        return session(output, args.glyph_mode)
    if not args.plugin or not args.plugin.is_file():
        parser.error('--plugin must name the built kos_bridge.so')
    output.mkdir(parents=True, exist_ok=False)
    config = output / 'config'
    (config / 'kos').mkdir(parents=True)
    (config / 'kos/window-buttons.json').write_text(json.dumps({'default': {'glyphMode': args.glyph_mode}}))
    plugins = output / 'plugins'
    destination = plugins / 'kwin/effects/plugins'
    destination.mkdir(parents=True)
    shutil.copy2(args.plugin, destination / 'kos_bridge.so')
    # Separate persistent keyfile settings from the desktop user's dconf database.
    env = dict(os.environ, XDG_CONFIG_HOME=str(config), GSETTINGS_BACKEND='keyfile',
               XDG_DATA_HOME=str(output / 'data'), QT_PLUGIN_PATH=str(plugins),
               QT_LOGGING_RULES='kwin_scripting.debug=true', QT_DEBUG_PLUGINS='1')
    # Setup requires no D-Bus session: avoid reconfiguring the outer compositor.
    setup_env = dict(env, DBUS_SESSION_BUS_ADDRESS='unix:path=/nonexistent/gtk201')
    tool = [sys.executable, str(ROOT / 'tools/gtk-window-buttons.py')]
    if args.settings:
        subprocess.run([str(args.settings.resolve()), '--install-window-defaults'], env=setup_env, check=True)
    else:
        subprocess.run(tool + ['sync', '--enabled', 'true', '--glyph-mode', args.glyph_mode], env=setup_env, check=True)
    for major in (3, 4):
        subprocess.run(tool + ['adapt', f'org.nextkde.Gtk{major}Controls'], env=setup_env, check=True)
    (config / 'kwinrc').write_text('[org.kde.kdecoration2]\nlibrary=kos_decoration\n'
                                  '[Plugins]\nkos_bridgeEnabled=true\n')
    # KWin's session option accepts an executable path, so use an argv-safe wrapper.
    import shlex
    wrapper = output / 'session.sh'
    wrapper.write_text('#!/bin/sh\nexec ' + shlex.join([
        sys.executable, str(Path(__file__).resolve()), '--session', '--output', str(output),
        '--glyph-mode', args.glyph_mode]) + '\n')
    wrapper.chmod(0o700)
    command = ['dbus-run-session', 'kwin_wayland', '--wayland-display',
               os.environ.get('WAYLAND_DISPLAY', 'wayland-0'), '--socket', f'gtk201-{os.getpid()}',
               '--width', '1000', '--height', '650', '--no-lockscreen', '--no-global-shortcuts',
               '--no-kactivities', '--exit-with-session', str(wrapper)]
    with (output / 'kwin.log').open('w') as log:
        with subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT,
                              start_new_session=True) as process:
            try:
                returncode = process.wait(timeout=120)
            except subprocess.TimeoutExpired:
                # Stop only this test's compositor/session, never the desktop.
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                raise
    # KWin can exit successfully even when the session helper fails.
    logs = [output / f'gtk{version}-{mode}.log' for version in ('3.0', '4.0') for mode in ('light', 'dark')]
    loaded_candidate = any(str(destination / 'kos_bridge.so') in line and 'loaded library' in line
                           for line in (output / 'kwin.log').read_text().splitlines())
    ok = loaded_candidate and returncode == 0 and all(path.exists() and '"red closes"' in path.read_text()
                                       and '"failures": []' in path.read_text()
                                       and 'Theme parser error' not in path.read_text()
                                       and 'Theme parsing error' not in path.read_text()
                                       and '"failures": ["' not in path.read_text() for path in logs)
    print(('PASS' if ok else 'FAIL') + f': native GTK controls; logs: {output}')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
