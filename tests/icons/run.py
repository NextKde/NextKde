#!/usr/bin/env python3
"""VM-only isolated font/shell adapter smoke test. Never starts the desktop shell."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--qs', default='qs')
parser.add_argument('--capture', default='/tmp/nextkde-shell-font-icons.png')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='nextkde-font-icons-') as directory:
    stage = Path(directory)
    common = stage / 'desktop/modules/common'
    common.mkdir(parents=True)
    shutil.copytree(root / 'shared/Icons', stage / 'shared/Icons')
    declarations = []
    for name in ['BundledIcons', 'BundledIcon', 'AppIcon']:
        shutil.copyfile(root / f'shell/desktop/modules/common/{name}.qml', common / f'{name}.qml')
        declarations.append(('singleton ' if name == 'BundledIcons' else '') + f'{name} 1.0 {name}.qml')
    (common / 'IconThemeReloadService.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { readonly property bool pixmapCacheAllowed: true }\n')
    declarations.append('singleton IconThemeReloadService 1.0 IconThemeReloadService.qml')
    (common / 'qmldir').write_text('module qs.desktop.modules.common\n' + '\n'.join(declarations) + '\n')
    shutil.copyfile(Path(__file__).with_name('shell.qml'), stage / 'shell.qml')
    result = subprocess.run([args.qs, '-p', str(stage)], text=True, capture_output=True, timeout=15,
        env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
             'QT_QPA_PLATFORMTHEME': '', 'XDG_CONFIG_HOME': str(stage / 'config'),
             'XDG_DATA_HOME': str(stage / 'data'), 'KOS_ICON_CAPTURE': args.capture})
    output = result.stdout + result.stderr
    if result.returncode or 'FONT_ICONS_PASS' not in output or any(x in output for x in ['TypeError', 'ReferenceError', 'Binding loop', 'Failed to load', 'Cannot assign']):
        raise SystemExit(output)
    print('Shell font, artwork adapters, Wi-Fi/volume/battery states passed; capture:', args.capture)
