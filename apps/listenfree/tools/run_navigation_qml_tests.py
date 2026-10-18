"""Run navigation loading, restoration, and memory-budget regressions without native plugins."""
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
with tempfile.TemporaryDirectory(prefix='listenfree-navigation-qml-') as directory:
    fixture = Path(directory)
    tests = fixture / 'tests/qml'
    components = fixture / 'music_player_desktop/components'
    assets = fixture / 'music_player_desktop/assets'
    for path in [tests / 'components', tests / 'assets', components, assets]:
        path.mkdir(parents=True, exist_ok=True)
    for path in [components, tests / 'components']:
        shutil.copy2(root / 'music_player_desktop/components/NavigationCache.qml', path)
    for source in (root / 'music_player_desktop/assets').glob('album_Cover_*.png'):
        shutil.copy2(source, assets)
        shutil.copy2(source, tests / 'assets')
    for name in ['tst_navigation_cache.qml', 'tst_navigation_budget.qml', 'tst_navigation_loading.qml']:
        shutil.copy2(root / 'tests/qml' / name, tests)
    environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
    raise SystemExit(subprocess.call([args.runner, '-input', str(tests)], env=environment))
