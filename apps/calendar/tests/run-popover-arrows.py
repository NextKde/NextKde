#!/usr/bin/env python3
"""Run in a VM/CI: isolated shared-popover geometry checks, not visual acceptance."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import os

repo = Path(__file__).resolve().parents[3]
with tempfile.TemporaryDirectory(prefix='popover-arrows-') as tmp:
    work = Path(tmp)
    shutil.copytree(repo / 'shared/demo-ui', work / 'ui')
    # This vendor library normally uses CMake-generated QML registration.
    (work / 'ui/controls/qmldir').write_text('singleton LiquidStyle 1.0 LiquidStyle.qml\n')
    shutil.copy2(Path(__file__).with_name('tst_popover_arrows.qml'), work / 'tst_arrows.qml')
    runner = shutil.which('qmltestrunner') or '/usr/lib/qt6/bin/qmltestrunner'
    result = subprocess.run([runner, '-input', str(work / 'tst_arrows.qml')],
        env=dict(os.environ, QT_QPA_PLATFORM='offscreen'), timeout=30)
    raise SystemExit(result.returncode)
