#!/usr/bin/env python3
"""Real KWin glass QA: isolated virtual output, synthetic messages, fixed capture.
Run in the validation environment authorized for this task. No session restart,
notification daemon takeover, or changes to the user's compositor configuration.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--build-dir', type=Path, default=repo / '.build/kosctl')
parser.add_argument('--output-dir', type=Path, default=repo / '.build/qa/notification-history')
parser.add_argument('--screenshots', action='store_true')
parser.add_argument('--width', type=int, default=1120)
parser.add_argument('--height', type=int, default=1080)
args = parser.parse_args()
args.output_dir.mkdir(parents=True, exist_ok=True)
plugin = args.build_dir / 'kwin-effects-glass/src/glass.so'
if not plugin.is_file():
    raise SystemExit(f'Build the glass effect first, or pass --build-dir: {plugin}')
with tempfile.TemporaryDirectory(prefix='kos-notification-native-') as directory:
    stage = Path(directory)
    for module in ('Kos', 'shared'):
        (stage / module).symlink_to(repo / 'shell' / module, target_is_directory=True)
    desktop = stage / 'desktop'
    desktop.mkdir()
    for entry in (repo / 'shell/desktop').iterdir():
        if entry.name != 'modules': (desktop / entry.name).symlink_to(entry)
    modules = desktop / 'modules'
    modules.mkdir()
    for entry in (repo / 'shell/desktop/modules').iterdir():
        if entry.name != 'platform': (modules / entry.name).symlink_to(entry)
    platform = modules / 'platform'
    platform.mkdir()
    for entry in (repo / 'shell/desktop/modules/platform').iterdir():
        if entry.name != 'PlatformClient.qml': (platform / entry.name).symlink_to(entry)
    shutil.copy2(Path(__file__).with_name('NativePlatformFixture.qml'), platform / 'PlatformClient.qml')
    shutil.copy2(Path(__file__).with_name('native.qml'), stage / 'shell.qml')
    plugins = stage / 'plugins/kwin/effects/plugins'
    plugins.mkdir(parents=True)
    (plugins / 'glass.so').symlink_to(plugin.resolve())
    config = stage / 'config'
    config.mkdir()
    (config / 'kwinrc').write_text('[Plugins]\nglassEnabled=true\nblurEnabled=false\nscaleEnabled=false\nfadeEnabled=false\nfadingpopupsEnabled=false\nslidingpopupsEnabled=false\nsquashEnabled=false\n[Effect-glass]\nBlurStrength=6\nLiquidStrength=10\n')
    (config / 'kdeglobals').write_text('[KDE]\nAnimationDurationFactor=0\n')
    socket = f'kos-notification-native-{os.getpid()}'
    session = stage / 'session.sh'
    # Paths are passed as argv/env, never interpolated as shell code.
    session.write_text('''#!/bin/sh
export QT_QPA_PLATFORM=wayland
export WAYLAND_DISPLAY="$KOS_QA_SOCKET"
quickshell --path "$KOS_QA_STAGE" --no-color &
qa_pid=$!
sleep 4
quickshell --path "$KOS_QA_STAGE" ipc call preview outerScroll
sleep 0.3
quickshell --path "$KOS_QA_STAGE" ipc call preview sample
quickshell --path "$KOS_QA_STAGE" ipc call preview stats
if [ "$KOS_QA_SCREENSHOTS" = 1 ]; then
    timeout 5s spectacle -b -n -f -o "$KOS_QA_OUTPUT/dark-collapsed.png"
fi
quickshell --path "$KOS_QA_STAGE" ipc call preview expand true
sleep 1
quickshell --path "$KOS_QA_STAGE" ipc call preview stats
if [ "$KOS_QA_SCREENSHOTS" = 1 ]; then
    timeout 5s spectacle -b -n -f -o "$KOS_QA_OUTPUT/dark-expanded.png"
fi
quickshell --path "$KOS_QA_STAGE" ipc call preview scroll
sleep 1
quickshell --path "$KOS_QA_STAGE" ipc call preview expand false
sleep 1
quickshell --path "$KOS_QA_STAGE" ipc call preview stats
if [ "$KOS_QA_SCREENSHOTS" = 1 ]; then
    quickshell --path "$KOS_QA_STAGE" ipc call preview theme light
    sleep 1
    timeout 5s spectacle -b -n -f -o "$KOS_QA_OUTPUT/light-collapsed.png"
fi
kill "$qa_pid"
wait "$qa_pid"
''')
    session.chmod(0o755)
    env = dict(os.environ, XDG_CONFIG_HOME=str(config), QT_PLUGIN_PATH=str(stage / 'plugins'),
               QML_IMPORT_PATH=str(args.build_dir / 'qml'), QML2_IMPORT_PATH=str(args.build_dir / 'qml'),
               QT_QPA_PLATFORM='offscreen', QT_FORCE_STDERR_LOGGING='1', LIBGL_ALWAYS_SOFTWARE='1',
               KOS_GLASS_TRACE='1', QS_DISABLE_FILE_WATCHER='1', KOS_QA_SOCKET=socket,
               KOS_QA_STAGE=str(stage), KOS_QA_OUTPUT=str(args.output_dir.resolve()),
               KOS_QA_SCREENSHOTS='1' if args.screenshots else '0')
    command = ['dbus-run-session', '--', 'kwin_wayland', '--virtual', '--width', str(args.width),
               '--height', str(args.height), '--scale', '1', '--socket', socket, '--no-lockscreen',
               '--no-global-shortcuts', '--no-kactivities', '--exit-with-session', str(session)]
    log = args.output_dir / ('screenshots.log' if args.screenshots else 'capture.log')
    with log.open('w') as output:
        process = subprocess.Popen(command, env=env, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            process.wait(timeout=35)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=5)
    text = log.read_text(errors='replace')
    assert not re.search(r'ReferenceError|TypeError|Binding loop|Unable to assign|Failed to load configuration|does not match the blur region', text), log
    snapshots = [json.loads(line) for line in text.splitlines() if line.startswith('{"open":')]
    assert len(snapshots) == 3 and all(item['open'] and item['scale'] == 1 for item in snapshots), (snapshots, log)
    assert all(item['fixedCapture'] for item in snapshots), (snapshots, log)
    assert snapshots[0]['retained'] and snapshots[1]['retained'], (snapshots, log)
    assert snapshots[0]['keys'] == snapshots[-1]['keys'], (snapshots, log)
    assert [item['preview'] for item in snapshots] == [3, 8, 3], (snapshots, log)
    assert all(item['height'] <= args.height - 110 for item in snapshots), (snapshots, log)
    allocations = re.findall(r'allocating capture chain QSize\((\d+), (\d+)\)', text)
    if not args.screenshots:
        assert len(allocations) == 1, (allocations, log)
    else:
        for name in ('dark-collapsed.png', 'dark-expanded.png', 'light-collapsed.png'):
            assert (args.output_dir / name).is_file(), f'Screenshot unavailable: {name}; {log}'
    frames = sorted(snapshots[-1]['frames'])
    timings = {'samples':len(frames), 'median_ms':round(frames[len(frames)//2], 2) if frames else None,
               'p95_ms':round(frames[min(len(frames)-1, int(len(frames)*0.95))], 2) if frames else None}
    report = {'capture_allocations':allocations, 'frame_intervals':timings,
              'output':[args.width,args.height], 'renderer':'isolated KWin / software OpenGL',
              'checks':['three independent cards', 'stable identities', 'unfold', 'kinetic scroll', 'fold after scrolling', 'bounded popup', 'no shape/capture mismatch']}
    (args.output_dir / ('screenshots.json' if args.screenshots else 'capture.json')).write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
