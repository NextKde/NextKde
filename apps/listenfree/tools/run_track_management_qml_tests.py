"""Run the track rows' source, loading, and favorite regressions in an isolated fixture."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--runner', required=True, help='Qt 6 qmltestrunner executable')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='listenfree-track-qml-') as directory:
    fixture = Path(directory)
    components = fixture / 'Components'
    components.mkdir()
    names = ['AppTheme', 'SongRow', 'CoverArt', 'IconGlyph', 'LoadingIndicator', 'TrackTitle']
    for name in names:
        shutil.copy2(root / 'music_player_desktop/components' / f'{name}.qml', components)
    (components / 'qmldir').write_text('singleton AppTheme 1.0 AppTheme.qml\n' + ''.join(
        f'{name} 1.0 {name}.qml\n' for name in names if name != 'AppTheme'))
    shutil.copytree(root / 'music_player_desktop/assets/icons', fixture / 'assets/icons')
    for name in ['tst_track_management.qml', 'tst_song_row_favorites.qml']:
        shutil.copy2(root / 'tests/qml' / name, fixture)
    environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
    raise SystemExit(subprocess.call([args.runner, '-input', str(fixture)], env=environment))
