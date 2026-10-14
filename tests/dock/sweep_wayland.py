"""Native commit coverage for the shared Dock label; does not move the mouse."""
import os
from pathlib import Path
import re
import statistics
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[2]
for edge in ['bottom', 'left', 'right']:
    with tempfile.TemporaryDirectory(prefix='kos-dock-label-sweep-') as directory:
        root = Path(directory)
        runtime = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
        wayland = os.environ.get('WAYLAND_DISPLAY', 'wayland-0')
        for name in ['config', 'state', 'runtime']:
            (root / name).mkdir(mode=0o700)
        (root / 'runtime' / wayland).symlink_to(runtime / wayland)
        for name in ['desktop', 'Kos', 'shared']:
            (root / name).symlink_to(REPO / 'shell' / name, target_is_directory=True)
        source = Path(__file__).with_name('sweep.qml').read_text().replace(
            'property string edge: "bottom"', f'property string edge: "{edge}"')
        (root / 'shell.qml').write_text(source)
        env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'),
                   XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(root / 'runtime'),
                   KOS_PLATFORM_SOCKET=str(root / 'no-platform.sock'),
                   KOS_DATA_SOCKET=str(root / 'no-data.sock'), QT_QPA_PLATFORM='wayland',
                   WAYLAND_DEBUG='client')
        result = subprocess.run(['quickshell', '--path', str(root), '--no-color'],
                                env=env, capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        assert result.returncode == 0 and 'SWEEP_PASS' in output, output
        assert not re.search(r'ReferenceError|TypeError|Cannot assign|Unable to assign|Binding loop', output), output
        Path('/tmp/dock-label-sweep-' + edge + '.log').write_text(output)
        surfaces = re.findall(r'-> wl_compositor[#@]\d+\.create_surface\(', output)
        commits = re.findall(r'-> wl_surface[#@]\d+\.commit\(', output)
        layers = re.findall(r'get_layer_surface\(.*"dock-label-sweep-probe"', output)
        assert len(layers) == 1, f'{edge}: label must share exactly one mapped layer surface'
        # Qt creates and immediately destroys a temporary unroled EGL surface
        # before constructing its real layer surface. It is not a label window.
        assert len(surfaces) <= 2, f'{edge}: unexpected extra surfaces: {len(surfaces)}'
        assert not re.search(r'xdg_surface[#@]\d+\.get_popup|xdg_popup[#@]\d+\.reposition', output), output
        requested_sizes = re.findall(r'zwlr_layer_surface_v1[#@]\d+\.set_size\((\d+, \d+)\)', output)
        assert len(set(requested_sizes)) == 1, f'{edge}: synthetic sweeps resize the layer surface'
        assert len(commits) >= 30, f'{edge}: too few real commits: {len(commits)}'
        report = next(line[line.index('SWEEP_PASS'):] for line in output.splitlines() if 'SWEEP_PASS' in line)
        timestamps = []
        for stamp in re.findall(r'\[(\d\d:\d\d:\d\d\.\d+)\].*EGLSurface\(\d+\).* -> wl_surface[#@]\d+\.commit\(\)', output):
            hours, minutes, seconds = stamp.split(':')
            timestamps.append(int(hours) * 3600 + int(minutes) * 60 + float(seconds))
        intervals = [(b - a) * 1000 for a, b in zip(timestamps[15:-1], timestamps[16:])]
        assert intervals, 'No real EGL frame commits measured'
        percentile95 = sorted(intervals)[int(len(intervals) * .95)]
        print(f'{report}; mappedLayers={len(layers)} commits={len(commits)}, no popup/reposition; '
              f'warm median={statistics.median(intervals):.2f}ms p95={percentile95:.2f}ms '
              f'max={max(intervals):.2f}ms')
