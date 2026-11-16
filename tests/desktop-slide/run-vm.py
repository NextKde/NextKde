#!/usr/bin/env python3
"""VM-only pixel regression for native Slide and real desktop widget surfaces.

Requires a shared outer X11 display, Quickshell, Konsole, Pillow and built Bridge.
Only the private nested compositor receives window operations or pointer input.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import sys
import threading
import time
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/cooperative-controls'))
from x11_pointer import click
spec = importlib.util.spec_from_file_location('fixture', ROOT / 'tests/widget-experience/run.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


def session(args, out):
    def dbus(path, method, *values):
        return subprocess.check_output(['qdbus6', 'org.kde.KWin', path, method, *values], text=True)
    def script(name, body):
        path = out / (name + '.js'); path.write_text(body)
        dbus('/Scripting', 'org.kde.kwin.Scripting.loadScript', str(path), name)
        dbus('/Scripting', 'org.kde.kwin.Scripting.start')
    def capture(name):
        path = out / (name + '.png')
        click(args.outer_x11, capture_path=str(path))
        with Image.open(path) as image:
            pixels = image.getcolors(image.width * image.height)
            magenta = sum(count for count, (r, g, b) in pixels if r > 220 and g < 40 and b > 220)
            green = sum(count for count, (r, g, b) in pixels if r < 40 and g > 220 and b < 40)
        return {'desktopPixels': magenta, 'panelPixels': green}
    root = out / 'shell'; root.mkdir()
    for name, source in [('desktop', ROOT / 'shell/desktop'), ('Kos', ROOT / 'shell/Kos'), ('shared', ROOT / 'shared')]:
        (root / name).symlink_to(source, target_is_directory=True)
    shutil.copy2(Path(__file__).with_name('shell.qml'), root / 'shell.qml')
    env = dict(os.environ, KOS_PLATFORM_SOCKET=str(out / 'platform.sock'), KOS_DATA_SOCKET=str(out / 'absent-data.sock'))
    with fixture.Server(str(out / 'platform.sock'), fixture.Platform) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        with (out / 'shell.log').open('w') as log, subprocess.Popen(['quickshell', '--path', str(root), '--no-color'], env=env, stdout=log, stderr=log) as shell:
            app = None
            try:
                time.sleep(3)
                assert shell.poll() is None, (out / 'shell.log').read_text()
                bridge = (ROOT / 'kwin/window-bridge.js').read_text()
                script('desktop-stack', bridge.split('// Runtime-dependent bridge helpers')[0] + '\ninstallDesktopStack(workspace);')
                time.sleep(1)
                assert capture('uncovered')['desktopPixels'] > 10000, 'desktop fixture did not render'
                dbus('/Effects', 'org.kde.kwin.Effects.loadEffect', 'slide')
                app = subprocess.Popen(['konsole', '--separate', '--hide-menubar', '--hold', '-e', '/bin/true'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                time.sleep(2)
                script('cover', 'if(workspace.desktops.length<2)workspace.createDesktop(1,"Second");workspace.windowList().forEach(w=>{if(w.resourceClass.indexOf("konsole")>=0){w.desktops=[];w.fullScreen=true;workspace.activeWindow=w;}});')
                time.sleep(3)
                assert capture('covered')['desktopPixels'] == 0, 'application must cover desktop before switching'
                records = []
                for cycle in range(3):
                    script('switch-' + str(cycle), 'workspace.currentDesktop=workspace.desktops[' + str((cycle + 1) % 2) + '];')
                    for frame in range(16):
                        time.sleep(.06)
                        record = capture(f'switch-{cycle}-{frame}')
                        record['activeEffects'] = dbus('/Effects', 'org.kde.kwin.Effects.activeEffects')
                        records.append(record)
                (out / 'frames.json').write_text(json.dumps(records, indent=2))
                active = [record for record in records if 'slide' in record['activeEffects']]
                assert active, 'native Slide did not animate'
                assert max(record['panelPixels'] for record in active) > 1000, 'real panels must retain Slide elevation'
                leaks = [record for record in records if record['desktopPixels'] > 0]
                assert not leaks, f'desktop appeared above the covering app in {len(leaks)} frames'
                (out / 'passed').write_text('PASS: repeated Slide keeps real DeskCenter behind apps and real panels above them.\n')
            finally:
                if app and app.poll() is None: app.terminate(); app.wait(timeout=5)
                shell.terminate(); shell.wait(timeout=5)
                server.shutdown()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bridge', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--outer-x11', default=':0')
    parser.add_argument('--session', action='store_true')
    args = parser.parse_args(); out = args.output.resolve()
    if args.session: session(args, out); return
    out.mkdir(parents=True, exist_ok=False)
    plugin = out / 'plugins/kwin/effects/plugins/kos_bridge.so'
    plugin.parent.mkdir(parents=True); shutil.copy2(args.bridge, plugin)
    config = out / 'config'; config.mkdir()
    (config / 'kwinrc').write_text('[Plugins]\nkos_bridgeEnabled=true\nslideEnabled=true\n[Effect-slide]\nDuration=1500\n')
    (config / 'kdeglobals').write_text('[KDE]\nAnimationDurationFactor=3\n')
    wrapper = out / 'session.sh'
    wrapper.write_text('#!/bin/sh\nexec ' + shlex.join([sys.executable, str(Path(__file__).resolve()), '--session', '--bridge', str(args.bridge.resolve()), '--output', str(out), '--outer-x11', args.outer_x11]) + '\n')
    wrapper.chmod(0o700)
    env = dict(os.environ, XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(out / 'data'), XDG_STATE_HOME=str(out / 'state'), QT_PLUGIN_PATH=str(out / 'plugins'))
    with (out / 'kwin.log').open('w') as log, subprocess.Popen(['dbus-run-session', 'kwin_wayland', '--x11-display', args.outer_x11, '--socket', 'desktop-slide-' + str(os.getpid()), '--width', '1100', '--height', '760', '--no-lockscreen', '--no-global-shortcuts', '--no-kactivities', '--exit-with-session', str(wrapper)], env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True) as proc:
        try: proc.wait(timeout=120)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGTERM); proc.wait(timeout=10); raise
    assert (out / 'passed').exists(), (out / 'kwin.log').read_text()[-3500:]
    print((out / 'passed').read_text().strip())


if __name__ == '__main__': main()
