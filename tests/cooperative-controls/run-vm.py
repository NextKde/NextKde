#!/usr/bin/env python3
"""VM-only real nested KWin test for cooperative controls and self-drawn fallback."""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LEGACY_APPS = {name: {'showButtons': False} for name in ['kos-calendar', 'kos-weather', 'org.nextkde.Kos.Calendar', 'org.nextkde.Kos.Weather']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bridge', type=Path, required=True)
    parser.add_argument('--qml', type=Path, required=True, help='Build-tree QML import directory')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--installed-layout', action='store_true', help='Load the native module from the deployed Shell path via QML2_IMPORT_PATH only')
    parser.add_argument('--capture-only', action='store_true')
    parser.add_argument('--session', action='store_true')
    parser.add_argument('--outer-x11', help='Use an outer X11 display for real pointer acceptance')
    parser.add_argument('--apps', type=Path, help='Optional build directory containing Calendar and Weather')
    parser.add_argument('--legacy-service', action='store_true', help='Expect self rendering against a protocol-v1 candidate')
    parser.add_argument('--without-service', action='store_true', help='Check self rendering with the effect disabled')
    args = parser.parse_args()
    output = args.output.resolve()
    if args.session:
        session(args, output)
        return
    output.mkdir(parents=True, exist_ok=False)
    plugins = output / 'plugins/kwin/effects/plugins'
    plugins.mkdir(parents=True)
    shutil.copy2(args.bridge, plugins / 'kos_bridge.so')
    config = output / 'config'
    (config / 'kos').mkdir(parents=True)
    # Deliberately use Breeze: cooperative CSD must not depend on KOS decoration.
    (config / 'kwinrc').write_text('[org.kde.kdecoration2]\nlibrary=org.kde.breeze\n[Plugins]\nkos_bridgeEnabled=true\n')
    if args.without_service:
        (config / 'kwinrc').write_text('[Plugins]\nkos_bridgeEnabled=false\n')
    (config / 'kos/window-appearance.json').write_text('{"version":2,"enabled":true}')
    # Upgrade regression: installed desktops exclude self-drawn apps from the
    # legacy overlay. This must not reject their explicit cooperative requests.
    (config / 'kos/window-buttons.json').write_text(json.dumps({'default': {'showButtons': False}, 'apps': LEGACY_APPS}))
    wrapper = output / 'session.sh'
    sessionArgs = [sys.executable, str(Path(__file__).resolve()),
        '--session', '--bridge', str(args.bridge.resolve()), '--qml', str(args.qml.resolve()), '--output', str(output)]
    if args.outer_x11: sessionArgs += ['--outer-x11', args.outer_x11]
    if args.capture_only: sessionArgs += ['--capture-only']
    if args.apps: sessionArgs += ['--apps', str(args.apps.resolve())]
    if args.legacy_service: sessionArgs += ['--legacy-service']
    if args.without_service: sessionArgs += ['--without-service']
    wrapper.write_text('#!/bin/sh\nexec ' + shlex.join(sessionArgs) + '\n')
    wrapper.chmod(0o700)
    env = dict(os.environ, XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(output/'data'),
               QT_PLUGIN_PATH=str(output/'plugins'), QML2_IMPORT_PATH=str(args.qml.resolve()),
               QML_IMPORT_PATH=str(args.qml.resolve()), QT_DEBUG_PLUGINS='1')
    if args.installed_layout:
        # Match the desktop launcher environment: the user Shell module takes
        # precedence over /usr. Never let the build-tree import hide stale or
        # missing deployment files in this acceptance mode.
        shell_import = config/'quickshell/kos'
        module = shell_import/'Kos/SurfaceShape'
        shutil.copytree(args.qml.resolve()/'Kos/SurfaceShape', module)
        env.pop('QML_IMPORT_PATH', None)
        env['QML2_IMPORT_PATH'] = str(shell_import)
    backend = ['--x11-display', args.outer_x11] if args.outer_x11 else ['--wayland-display', env.get('WAYLAND_DISPLAY', 'wayland-0')]
    cmd = ['dbus-run-session', 'kwin_wayland', *backend,
           '--socket', f'cooperative-{os.getpid()}', '--width', '1100', '--height', '760',
           '--no-lockscreen', '--no-global-shortcuts', '--no-kactivities', '--exit-with-session', str(wrapper)]
    with (output/'kwin.log').open('w') as log, subprocess.Popen(cmd, env=env, stdout=log, stderr=subprocess.STDOUT,
                                                             start_new_session=True) as process:
        try:
            process.wait(timeout=100)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=5)
            raise
    assert (output/'passed').exists(), (output/'kwin.log').read_text()[-4000:]
    if not args.without_service:
        assert any(str(plugins/'kos_bridge.so') in line and 'loaded library' in line for line in (output/'kwin.log').read_text().splitlines())
    print(f'PASS: cooperative controls; evidence: {output}')


def application_binary(args, output, name):
    binary=args.apps/f'apps/{name}/kos-{name}'
    if name != 'settings': return binary
    # Settings reads installed QML before its compiled-in source path.
    prefix=output/'installed-settings'
    if not prefix.exists():
        (prefix/'bin').mkdir(parents=True)
        shutil.copy2(binary,prefix/'bin/kos-settings')
        shutil.copytree(ROOT/'apps/settings',prefix/'share/kos/settings')
        shutil.copytree(ROOT/'shared/qml',prefix/'share/shared/qml')
    return prefix/'bin/kos-settings'


def capture_apps(args, output):
    from x11_pointer import click
    from PIL import Image
    assert args.apps and args.outer_x11
    env=dict(os.environ, KOS_WEATHER_DISABLE_SERVICE_AUTOSTART='1')
    for name in ['calendar','weather','settings']:
        with (output/f'{name}.log').open('w') as log, subprocess.Popen(
            [str(application_binary(args, output, name))],env=env,stdout=log,stderr=subprocess.STDOUT) as app:
            try:
                deadline=time.monotonic()+20
                while time.monotonic()<deadline:
                    data=json.loads(subprocess.check_output(['qdbus6','org.kde.KWin','/Effects','org.kde.kwin.Effects.debug','kos_bridge','window-controls'],text=True))
                    windows=[w for w in data['windows'] if name in w['windowClass'].lower() and w.get('painted') and w.get('cooperative')]
                    if windows: break
                    time.sleep(.15)
                assert windows, name+' never acquired controls'
                time.sleep(1.2) # Let the initial placement/size animation settle.
                data=json.loads(subprocess.check_output(['qdbus6','org.kde.KWin','/Effects','org.kde.kwin.Effects.debug','kos_bridge','window-controls'],text=True))
                window=next(w for w in data['windows'] if name in w['windowClass'].lower() and w.get('painted'))
                (output/f'{name}-geometry.json').write_text(json.dumps(window,indent=2))
                buttons=window['buttons']
                cx=(buttons[0][0]+buttons[0][2]/2)
                cy=(buttons[0][1]+buttons[0][3]/2)
                for state,point in [('normal',(20,400)),('hover',(cx,cy)),('leave',(20,400))]:
                    click(args.outer_x11,point,move_only=True)
                    time.sleep(.6)
                    (output/f'{name}-{state}-state.json').write_text(subprocess.check_output(['qdbus6','org.kde.KWin','/Effects','org.kde.kwin.Effects.debug','kos_bridge','window-controls'],text=True))
                    path=output/f'{name}-{state}.png'
                    click(args.outer_x11,capture_path=str(path))
                    left=min(b[0] for b in buttons)
                    top=min(b[1] for b in buttons)
                    right=max(b[0]+b[2] for b in buttons)
                    bottom=max(b[1]+b[3] for b in buttons)
                    bounds=(int(left)-8,int(top)-8,int(right)+9,int(bottom)+9)
                    crop=Image.open(path).crop(bounds)
                    if state != 'normal':
                        baseline=Image.open(output/f'{name}-normal-crop.png')
                        box=(4,4,baseline.width-4,baseline.height-4)
                        deadline=time.monotonic()+8
                        while time.monotonic()<deadline:
                            same=crop.crop(box).tobytes()==baseline.crop(box).tobytes()
                            if same == (state == 'leave'): break
                            time.sleep(.2)
                            click(args.outer_x11,capture_path=str(path))
                            crop=Image.open(path).crop(bounds)
                    crop.save(output/f'{name}-{state}-crop.png')
                normal=Image.open(output/f'{name}-normal-crop.png')
                hover=Image.open(output/f'{name}-hover-crop.png')
                leave=Image.open(output/f'{name}-leave-crop.png')
                # Compare the dots plus their 4-logical-pixel paint gutter;
                # weather content below the control strip can animate.
                trim=4
                box=(trim,trim,normal.width-trim,normal.height-trim)
                assert normal.crop(box).tobytes()==leave.crop(box).tobytes(), 'Hover left stale pixels: '+name
                assert normal.crop(box).tobytes()!=hover.crop(box).tobytes(), 'Pointer did not reach the hover halo: '+name
            finally:
                app.terminate(); app.wait(timeout=5)
    (output/'passed').write_text('Real application capture, cooperative controls and hover cleanup passed.\n')


def session(args, output):
    if args.capture_only:
        capture_apps(args,output); return
    env = dict(os.environ, QT_DEBUG_PLUGINS='0')
    fixture = output / 'client'
    fixture.mkdir()
    (fixture / 'shared').symlink_to(ROOT / 'shared', target_is_directory=True)
    (fixture / 'shell.qml').write_text((HERE/'shell.qml').read_text().replace('../../shared/qml/foundation', 'shared/qml/foundation'))
    script = output/'place.js'
    script.write_text('workspace.windowAdded.connect(function(w) { if (w.caption.indexOf("Cooperative controls") !== 0) return; '
                      'var r=w.frameGeometry; r.x=w.caption.endsWith("A")?20:620; r.y=w.caption.endsWith("A")?140:450; w.frameGeometry=r; });')
    subprocess.run(['qdbus6','org.kde.KWin','/Scripting','org.kde.kwin.Scripting.loadScript',str(script),'cooperative-place'], check=True)
    subprocess.run(['qdbus6','org.kde.KWin','/Scripting','org.kde.kwin.Scripting.start'], check=True)
    with (output/'client.log').open('w') as log, subprocess.Popen(
            ['quickshell', '--path', str(fixture), '--no-color'], env=env, stdout=log, stderr=subprocess.STDOUT) as client:
        def ipc(method):
            result = subprocess.run(['quickshell', 'ipc', '--path', str(fixture), 'call', 'cooperative', method],
                                    env=env, capture_output=True, text=True, timeout=3)
            if result.returncode:
                raise RuntimeError(result.stdout + result.stderr)
            return result.stdout.strip()

        def wait_for(predicate):
            deadline = time.monotonic() + 8
            last = None
            while time.monotonic() < deadline:
                try:
                    last = json.loads(ipc('state'))
                    if predicate(last):
                        return last
                except (ValueError, RuntimeError):
                    pass
                time.sleep(.1)
            raise AssertionError(f'Unmet state: {last}\n' + (output/'client.log').read_text()[-3000:])

        def appearance(enabled):
            path = output/'config/kos/window-appearance.json'
            new = path.with_suffix('.tmp')
            new.write_text(json.dumps({'version':2, 'enabled':enabled}))
            new.replace(path)

        def diagnostics():
            return json.loads(subprocess.check_output(['qdbus6', 'org.kde.KWin', '/Effects',
                'org.kde.kwin.Effects.debug', 'kos_bridge', 'window-controls'], text=True))

        def rendered_at(x, y):
            for _ in range(40):
                state = diagnostics()
                assert state['samplingWindows'] == 0, state
                for window in state['windows']:
                    if window.get('painted') and abs(window['localRect'][0]-x)<.02 and abs(window['localRect'][1]-y)<.02:
                        assert window['cooperative'] and not window['background'] and not window['sampling'], window
                        return window
                time.sleep(.1)
            raise AssertionError(state)

        try:
            if args.without_service or args.legacy_service:
                time.sleep(1)
                wait_for(lambda state: state['supported'] == args.legacy_service and not state['a'] and not state['b'] and state['aw'] == 78)
                ipc('moveSlot')
                wait_for(lambda state: state['ay'] == 58 and not state['a'])
                (output/'passed').write_text('Unavailable/old service client fallback passed.\n')
                return
            initial = wait_for(lambda state: state['a'] and state['b'])
            assert initial['ax'] != initial['bx'] and initial['aw'] == 78
            rendered_at(initial['ax'], initial['ay'])
            rendered_at(initial['bx'], initial['by'])
            if args.outer_x11:
                from x11_pointer import click
                from PIL import Image
                ipc('maximize')
                wait_for(lambda state: state['visibility'] == 4 and state['a'])
                time.sleep(.5)
                state = json.loads(ipc('state'))
                maximized = rendered_at(state['ax'], state['ay'])
                close = maximized['buttons'][2]
                closePoint = (close[0]+close[2]/2, close[1]+close[3]/2)
                assert 2 < closePoint[1] < 27, maximized
                # The nested VM output may present at a low frame rate. Wait
                # for the mask's accompanying pixels, not a guessed delay.
                capture = output/'shell-input.png'
                click(args.outer_x11, capture_path=str(capture))
                with Image.open(capture) as image:
                    baselinePixels = [image.getpixel((550, y)) for y in [10, 30]]

                def panel_presented(covered):
                    deadline = time.monotonic() + 8
                    while time.monotonic() < deadline:
                        click(args.outer_x11, capture_path=str(capture))
                        with Image.open(capture) as image:
                            changed = [image.getpixel((550, y)) != pixel
                                       for y, pixel in zip([10, 30], baselinePixels)]
                        if changed == covered:
                            return
                        time.sleep(.1)
                    raise AssertionError(f'Panel frame not presented: {changed}, expected {covered}')

                ipc('showPanel')
                panel_presented([True, True])
                for button in [1, 2, 3]:
                    before = json.loads(ipc('state'))['panelClicks']
                    click(args.outer_x11, closePoint, button=button)
                    wait_for(lambda state: state['panelClicks'] == before+1 and state['visibility'] == 4)
                wheels = json.loads(ipc('state'))['panelWheels']
                click(args.outer_x11, closePoint, button=4)
                wait_for(lambda state: state['panelWheels'] > wheels and state['visibility'] == 4)
                ipc('partialPanel')
                panel_presented([True, False])
                before = json.loads(ipc('state'))['panelClicks']
                click(args.outer_x11, closePoint)
                wait_for(lambda state: state['panelClicks'] == before+1 and state['visibility'] == 4)
                # Hidden but still mapped: only the 2px reveal edge owns input.
                ipc('hidePanel')
                panel_presented([False, False])
                maximize = maximized['buttons'][0]
                click(args.outer_x11, (maximize[0]+maximize[2]/2, maximize[1]+maximize[3]/2))
                wait_for(lambda state: state['visibility'] == 2 and state['a'])
                ipc('removePanel')
                (output/'shell-input-passed').write_text(
                    'Shown/partially shown layer surface receives left/middle/right clicks and wheel; '
                    'covered close never fires; hidden mapped surface permits underlying restore.\n')
                initial = json.loads(ipc('state'))
            # Dynamic lists: absent actions must have neither drawn nor hit rectangles.
            originalId = rendered_at(initial['ax'], initial['ay'])['id']
            for method, indices in [('closeOnly', [2]), ('minimizeOnly', [1]), ('maximizeOnly', [0]), ('reversed', [2, 0])]:
                ipc(method)
                current = wait_for(lambda state: len(state['actions']) == len(indices) and state['a'])
                for _ in range(60):
                    window = next(w for w in diagnostics()['windows'] if w['id'] == originalId)
                    present = [i for i, rect in enumerate(window.get('buttons', [])) if rect[2] > 0]
                    if window.get('painted') and present == sorted(indices): break
                    time.sleep(.1)
                else: raise AssertionError(window)
                if len(indices) == 2:
                    assert window['buttons'][2][0] < window['buttons'][0][0], window
                assert diagnostics()['samplingWindows'] == 0
            ipc('noButtons')
            wait_for(lambda state: len(state['actions']) == 0)
            for _ in range(60):
                window = next(w for w in diagnostics()['windows'] if w['id'] == originalId)
                if not window.get('painted'): break
                time.sleep(.1)
            else: raise AssertionError(window)
            ipc('allButtons')
            initial = wait_for(lambda state: len(state['actions']) == 3 and state['aw'] == 78 and state['a'])
            rendered_at(initial['ax'], initial['ay'])
            ipc('moveSlot')
            moved = wait_for(lambda state: state['ay'] == 58 and state['a'])
            assert moved['ax'] != initial['ax']
            rendered_at(moved['ax'], moved['ay'])
            ipc('resize')
            wait_for(lambda state: state['ax'] != moved['ax'] and state['a'])
            appearance(False)
            wait_for(lambda state: not state['a'] and not state['b'])
            appearance(True)
            wait_for(lambda state: state['a'] and state['b'])
            for mode in ['hover', 'always']:
                (output/'config/kos/window-buttons.json').write_text(json.dumps({'version':2, 'default':{'glyphMode':mode, 'showButtons':False}, 'apps':LEGACY_APPS}))
                subprocess.run(['qdbus6','org.kde.KWin','/Effects','org.kde.kwin.Effects.reconfigureEffect','kos_bridge'], check=True)
                wait_for(lambda state: state['a'] and state['hover'] == (mode == 'hover'))
            ipc('fade')
            wait_for(lambda state: not state['a'] and state['b'])
            ipc('unfade')
            wait_for(lambda state: state['a'] and state['b'])
            ipc('fullscreen')
            wait_for(lambda state: not state['a'])
            ipc('restore')
            wait_for(lambda state: state['a'] and state['b'])
            ipc('hidePeer'); ipc('showPeer')
            wait_for(lambda state: state['a'] and state['b'])
            time.sleep(1.2)
            assert diagnostics()['samplingWindows'] == 0
            if args.outer_x11:
                from x11_pointer import click
                current = json.loads(ipc('state'))
                window = rendered_at(current['ax'], current['ay'])
                def press(index):
                    state = json.loads(ipc('state'))
                    data = rendered_at(state['ax'], state['ay'])
                    rect = data['buttons'][index]
                    click(args.outer_x11, (rect[0]+rect[2]/2, rect[1]+rect[3]/2))
                    time.sleep(.3)
                    print('CLICK', index, rect, diagnostics(), flush=True)
                press(0)
                wait_for(lambda state: state['visibility'] == 4)
                press(0)
                wait_for(lambda state: state['visibility'] == 2)
                press(1)
                wait_for(lambda state: any(w['id'] == window['id'] and w['minimized'] for w in diagnostics()['windows']))
                # Wayland does not report compositor-initiated minimization to
                # QWindow. Restore using the nested compositor's scripting API.
                restore = output/'restore.js'
                restore.write_text('workspace.windowList().forEach(function(w) { if (w.caption === "Cooperative controls A") { w.minimized=false; workspace.activeWindow=w; } });')
                subprocess.run(['qdbus6','org.kde.KWin','/Scripting','org.kde.kwin.Scripting.loadScript',str(restore),'cooperative-restore'], check=True)
                subprocess.run(['qdbus6','org.kde.KWin','/Scripting','org.kde.kwin.Scripting.start'], check=True)
                wait_for(lambda state: state['visibility'] == 2 and state['a'] and any(
                    w['id'] == window['id'] and not w['minimized'] for w in diagnostics()['windows']))
                beforeRemoval = rendered_at(*[json.loads(ipc('state'))[k] for k in ['ax', 'ay']])
                ipc('closeOnly')
                wait_for(lambda state: state['actions'] == ['close'] and state['aw'] == 22)
                current = json.loads(ipc('state'))
                only = rendered_at(current['ax'], current['ay'])
                assert only['buttons'][0][2] == 0 and only['buttons'][1][2] == 0
                previousMax = beforeRemoval['buttons'][0]
                clicks = json.loads(ipc('state'))['backgroundClicks']
                click(args.outer_x11, (previousMax[0]+previousMax[2]/2, previousMax[1]+previousMax[3]/2))
                wait_for(lambda state: state['backgroundClicks'] == clicks+1 and state['visibility'] == 2)
                press(2)
                wait_for(lambda state: state['visibility'] == 0)
            if args.apps:
                for name in ['calendar', 'weather', 'settings']:
                    appenv = dict(env, KOS_WEATHER_DISABLE_SERVICE_AUTOSTART='1')
                    with (output/f'{name}.log').open('w') as appLog, subprocess.Popen(
                        [str(application_binary(args, output, name))], env=appenv, stdout=appLog, stderr=subprocess.STDOUT) as app:
                        try:
                            wait_for(lambda state: any(w['active'] and w.get('cooperative') and w.get('painted')
                                and not w['background'] and not w['sampling'] and name in w['windowClass'].lower()
                                for w in diagnostics()['windows']))
                            assert app.poll() is None, (output/f'{name}.log').read_text()
                        finally:
                            app.terminate(); app.wait(timeout=5)
            (output/'passed').write_text('Two surfaces, exact compositor geometry, no background/sampling, switch, lifecycle and optional real pointer passed.\n')
        finally:
            client.terminate()
            client.wait(timeout=5)


if __name__ == '__main__':
    main()
