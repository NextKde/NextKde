#!/usr/bin/env python3
"""Exercise isolated VM Dock clicks, Super skip, launcher overlap and reduced motion.

Requires isolated-platform.py and .build/replay prepared for recording. Super
checks global input cancellation; the project's launcher shortcut is Meta+Space.
Launcher overlap uses IPC because the isolated proxy rejects shortcut changes.
"""
import json
import os
from pathlib import Path
from process_lines import ProcessLines
import subprocess
import time

root = Path(__file__).resolve().parents[2]
entry = root / '.build/replay'
state = Path.home() / '.local/state/quickshell/kos-startup-reveal-astra'
out = root / '.build/startup-evidence'
out.mkdir(exist_ok=True)
env = dict(os.environ, XDG_RUNTIME_DIR='/run/user/1000',
           DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/1000/bus', WAYLAND_DISPLAY='wayland-0',
           QT_QPA_PLATFORM='wayland', QT_FORCE_STDERR_LOGGING='1',
           QML_IMPORT_PATH=str(root / '.build/native/qml'),
           KOS_PLATFORM_SOCKET='/run/user/1000/kos-startup-test.sock')


def run(*args):
    return subprocess.run(args, env=env, text=True, capture_output=True, timeout=8, check=True)


def ipc(target, method, *args):
    return json.loads(run('quickshell', 'ipc', '--path', str(entry),
                          'call', target, method, *args).stdout)


def exercise(mode):
    config = json.loads(original)
    config['reduceMotion'] = mode == 'reduced'
    config_path.write_text(json.dumps(config))
    # Current 1280x800 VM layout. Check rest-click first to validate this slot.
    run('ydotool', 'mousemove', '--absolute', '-x', '429', '-y', '764')
    process = subprocess.Popen(['quickshell', '--path', str(entry), '--no-color'], env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    lines = []
    result = dict(mode=mode, before=None, after=None, launcher=None)
    try:
        output = ProcessLines(process)
        deadline = time.monotonic() + 35
        trigger = ('[StartupReveal] done' if mode in ('rest-click', 'reduced')
                   else 'Configuration Loaded' if mode == 'zero-click'
                   else '[StartupReveal] fading')
        while time.monotonic() < deadline:
            event = output.get()
            if event is None:
                continue
            _, line = event
            if line is None:
                raise RuntimeError('shell exited before interaction')
            lines.append(line)
            if trigger not in line:
                continue
            before = ipc('integration-status', 'snapshot')['startupReveal']
            result['before'] = before
            if mode == 'zero-click':
                assert before['progress'] == 0, 'missed the progress=0 input window'
            elif mode in ('click', 'super', 'launcher'):
                assert before['progress'] < 1, 'missed the animation input window'
            if mode.endswith('click'):
                run('ydotool', 'click', '-D', '100', '0xC0')
            elif mode == 'super':
                run('ydotool', 'key', '125:1', '125:0')
            elif mode == 'launcher':
                run('quickshell', 'ipc', '--path', str(entry), 'call', 'applauncher', 'toggle')
            result['after'] = ipc('integration-status', 'snapshot')['startupReveal']
            if mode.endswith('click') or mode == 'launcher':
                time.sleep(.5)
                result['launcher'] = ipc('applauncher', 'inspectGlass')
            break
        assert result['after'] and result['after']['phase'] == 'done', result
        if mode.endswith('click') or mode == 'launcher':
            assert result['launcher'] and result['launcher']['open'], result
        if mode == 'reduced':
            assert not any('[StartupReveal] fading' in line for line in lines)
        result['passed'] = True
    except Exception as error:
        result.update(passed=False, error=str(error))
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
        (out / f'{mode}.log').write_text(''.join(lines))
        (out / f'{mode}.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result), flush=True)
    return result


config_path = state / 'appearance/config.json'
original = config_path.read_text()
results = []
try:
    for mode in ('rest-click', 'zero-click', 'click', 'super', 'launcher', 'reduced'):
        results.append(exercise(mode))
        time.sleep(1)
finally:
    config_path.write_text(original)
raise SystemExit(0 if all(result['passed'] for result in results) else 1)
