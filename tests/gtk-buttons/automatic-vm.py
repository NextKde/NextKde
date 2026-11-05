#!/usr/bin/env python3
"""VM-only automatic GTK 3 ownership on Wayland and XWayland; no app rules."""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--plugin', type=Path)
parser.add_argument('--module', type=Path)
parser.add_argument('--settings', type=Path)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--session', action='store_true')
parser.add_argument('--upgrade', action='store_true')
args = parser.parse_args()
out = args.output.resolve()
if args.session:
    for backend in ['wayland', 'x11']:
        env = dict(os.environ, GDK_BACKEND=backend, G_DEBUG='fatal-criticals')
        with (out / f'ownership-{backend}.log').open('w') as log:
            subprocess.run([sys.executable, str(ROOT/'tests/gtk-buttons/ownership.py')],
                env=env, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=35)
        with (out / f'native-{backend}.log').open('w') as log:
            subprocess.run([sys.executable, str(ROOT/'tests/gtk-buttons/native_controls.py'), '3.0'],
                env=env, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=25)
        with (out / f'appearance-{backend}.log').open('w') as log:
            subprocess.run([sys.executable, str(ROOT/'tests/gtk-buttons/appearance.py'),
                '--output', str(out/f'appearance-{backend}')], env=env,
                stdout=log, stderr=subprocess.STDOUT, check=True, timeout=20)
    # A real GTK application, with fresh configuration and no saved connections.
    with (out/'remmina.log').open('w') as log:
        app = subprocess.Popen(['remmina'], env=dict(os.environ, GDK_BACKEND='wayland'), stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                time.sleep(.3)
                state = json.loads(subprocess.check_output(['qdbus6', 'org.kde.KWin', '/Effects',
                    'org.kde.kwin.Effects.debug', 'kos_bridge', 'window-controls'], text=True))
                windows = [w for w in state['windows'] if 'remmina' in w['windowClass'].lower()]
                if windows and any(w['declared'] and not w.get('painted') for w in windows):
                    (out/'remmina-state.json').write_text(json.dumps(state, indent=2))
                    sys.path.insert(0, str(ROOT/'tests/cooperative-controls'))
                    from x11_pointer import click
                    time.sleep(3)
                    nested_auth = os.environ.get('XAUTHORITY')
                    try:
                        os.environ['XAUTHORITY'] = os.environ.get('KOS_OUTER_XAUTHORITY', '')
                        click(os.environ.get('KOS_OUTER_DISPLAY', ':0'), point=(20, 400), move_only=True)
                        time.sleep(1)
                        click(os.environ.get('KOS_OUTER_DISPLAY', ':0'), capture_path=str(out/'remmina.png'))
                    finally:
                        if nested_auth is None: os.environ.pop('XAUTHORITY', None)
                        else: os.environ['XAUTHORITY'] = nested_auth
                    break
            else:
                raise AssertionError(state)
        finally:
            app.terminate()
            app.wait(timeout=5)
    (out/'passed').write_text('Wayland, XWayland, removal/restoration, and Remmina passed without app rules.\n')
else:
    out.mkdir(parents=True, exist_ok=False)
    config = out/'config'
    (config/'kos').mkdir(parents=True)
    (config/'kwinrc').write_text('[org.kde.kdecoration2]\nlibrary=kos_decoration\n[Plugins]\nkos_bridgeEnabled=true\n')
    (config/'kos/window-buttons.json').write_text('{"default":{"glyphMode":"always"}}')
    plugins = out/'plugins/kwin/effects/plugins'
    plugins.mkdir(parents=True)
    shutil.copy2(args.plugin, plugins/'kos_bridge.so')
    env = dict(os.environ, XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(out/'data'),
        KOS_OUTER_DISPLAY=os.environ.get('DISPLAY', ':0'),
        KOS_OUTER_XAUTHORITY=os.environ.get('XAUTHORITY', ''),
        XDG_CACHE_HOME=str(out/'cache'), GSETTINGS_BACKEND='keyfile', QT_PLUGIN_PATH=str(out/'plugins'))
    setup = dict(env, DBUS_SESSION_BUS_ADDRESS='unix:path=/nonexistent/gtk-auto')
    if args.upgrade:
        subprocess.run([sys.executable, str(ROOT/'tools/gtk-window-buttons.py'), 'sync',
            '--enabled','true','--glyph-mode','always'], env=setup, check=True)
        (config/'kos/window-integration.json').write_text('{"originalDecoration":"org.kde.breeze"}')
    if args.settings:
        subprocess.run([str(args.settings.resolve()), '--install-window-defaults'], env=setup, check=True)
    else:
        subprocess.run([sys.executable, str(ROOT/'tools/gtk-window-buttons.py'), 'sync',
            '--enabled','true','--glyph-mode','always','--gtk3-module',str(args.module.resolve())], env=setup, check=True)
    # Apply exactly the startup script Plasma will source on next login.
    startup = config/'plasma-workspace/env/kos-gtk-window-controls.sh'
    env['GTK_MODULES'] = subprocess.check_output(['sh','-c', '. \"$1\"; printf %s \"${GTK_MODULES:-}\"', 'sh', str(startup)], env=env, text=True)
    # There must be no application qualification list in either fresh-install path.
    assert not json.loads((config/'kos/window-buttons.json').read_text()).get('rules')
    wrapper = out/'session.sh'
    wrapper.write_text('#!/bin/sh\nexec '+shlex.join([sys.executable,str(Path(__file__).resolve()),'--session','--output',str(out)])+'\n')
    wrapper.chmod(0o700)
    with (out/'kwin.log').open('w') as log:
        subprocess.run(['dbus-run-session','kwin_wayland','--x11-display',os.environ.get('DISPLAY',':0'),
            '--xwayland','--socket',f'gtk-auto-{os.getpid()}','--width','1100','--height','760',
            '--no-lockscreen','--no-global-shortcuts','--no-kactivities','--exit-with-session',str(wrapper)],
            env=env, stdout=log, stderr=log, check=True, timeout=100)
    assert (out/'passed').exists(), (out/'kwin.log').read_text()[-3000:]
    print((out/'passed').read_text())
