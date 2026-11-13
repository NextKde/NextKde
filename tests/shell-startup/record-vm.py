#!/usr/bin/env python3
"""Record three isolated real-shell starts on the development VM.

Run after preparing .build/replay, the native plugin and isolated-platform.py.
Uses Spectacle's screen selection and recording tray; changes no preferences.
"""
import json
import os
from pathlib import Path
from process_lines import ProcessLines
import subprocess
import time

root = Path(__file__).resolve().parents[2]
out = root / '.build/startup-evidence'
out.mkdir(exist_ok=True)
env = dict(os.environ, XDG_RUNTIME_DIR='/run/user/1000',
           DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/1000/bus',
           WAYLAND_DISPLAY='wayland-0', QT_QPA_PLATFORM='wayland',
           QT_FORCE_STDERR_LOGGING='1', QML_IMPORT_PATH=str(root / '.build/native/qml'),
           KOS_PLATFORM_SOCKET='/run/user/1000/kos-startup-test.sock')

def run(*args, **kwargs):
    return subprocess.run(args, env=env, text=True, capture_output=True, timeout=15, **kwargs)

def trays():
    return set(run('qdbus6', 'org.kde.StatusNotifierWatcher', '/StatusNotifierWatcher',
                   'RegisteredStatusNotifierItems').stdout.splitlines())

for attempt in range(1, 4):
    raw = out / f'arrival-{attempt}-raw.webm'
    before = trays()
    log = (out / f'recorder-{attempt}.log').open('w')
    recorder = subprocess.Popen(['spectacle', '-i', '-b', '-n', '-R', 'screen', '-o', str(raw)],
                                env=env, stdout=log, stderr=log)
    shell = None
    try:
        time.sleep(3)
        run('ydotool', 'mousemove', '--absolute', '-x', '640', '-y', '400')
        run('ydotool', 'click', '0xC0')
        deadline = time.monotonic() + 12
        recording_tray = None
        while time.monotonic() < deadline:
            candidates = trays() - before
            if candidates:
                recording_tray = next(iter(candidates))
                break
            time.sleep(.1)
        if not recording_tray:
            raise RuntimeError('Spectacle recording tray never appeared')
        run('qdbus6', 'org.kde.KWin', '/KWin', 'showDesktop', 'true')
        time.sleep(.5)
        shell = subprocess.Popen(['quickshell', '--path', str(root / '.build/replay'), '--no-color'],
                                 env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 text=True, bufsize=1)
        output = ProcessLines(shell)
        phases = []
        lines = []
        started = None
        ended = None
        deadline = time.monotonic() + 35
        while time.monotonic() < deadline:
            if shell.poll() is not None:
                raise RuntimeError('shell exited during recording')
            event = output.get()
            if event is None:
                if ended and time.monotonic() - ended > 2.5:
                    break
                continue
            observed, line = event
            if line is None:
                raise RuntimeError('shell output closed during recording')
            lines.append(line)
            if '[StartupReveal]' in line:
                phase = line.strip().split()[-1]
                phases.append(phase)
                if phase == 'fading': started = observed
                if phase == 'done': ended = observed
        (out / f'arrival-{attempt}.log').write_text(''.join(lines))
        service, path = recording_tray.split('/', 1)
        stop = time.monotonic()
        run('qdbus6', service, '/' + path, 'org.kde.StatusNotifierItem.Activate', '0', '0')
        recorder.wait(timeout=15)
        duration = float(run('ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                             '-of', 'default=noprint_wrappers=1:nokey=1', str(raw)).stdout.strip())
        if not started or not ended:
            raise RuntimeError(f'missing sequence: {phases}')
        offset = max(0, duration - (stop - started) - .5)
        clip = out / f'arrival-{attempt}.webm'
        encoded = run('ffmpeg', '-y', '-v', 'error', '-ss', str(offset), '-i', str(raw),
                      '-t', '4', '-c:v', 'libvpx-vp9', '-crf', '30', '-b:v', '0', str(clip))
        if encoded.returncode:
            raise RuntimeError(encoded.stderr)
        clip_duration = float(run('ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                                  '-of', 'default=noprint_wrappers=1:nokey=1', str(clip)).stdout.strip())
        result = dict(attempt=attempt, phases=phases, observed_elapsed_ms=round((ended-started)*1000),
                      video=str(clip), duration=clip_duration, raw_duration=duration, trim_start=offset)
        (out / f'arrival-{attempt}.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(result), flush=True)
        assert phases == ['idle', 'fading', 'bar', 'dock', 'icons', 'done'], phases
        assert 3 <= clip_duration <= 5, clip_duration
        assert 600 <= result['observed_elapsed_ms'] <= 900, result
    finally:
        if shell and shell.poll() is None:
            shell.terminate()
            try: shell.wait(timeout=5)
            except subprocess.TimeoutExpired: shell.kill()
        if recorder.poll() is None:
            recorder.terminate()
        log.close()
    time.sleep(1)
