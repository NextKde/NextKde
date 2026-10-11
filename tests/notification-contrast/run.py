#!/usr/bin/env python3
"""Render actual history labels through repeated theme switches in isolation."""
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import threading
REPO=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('platform_fixture',REPO/'tests/widget-experience/run.py')
fixture=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixture)
with tempfile.TemporaryDirectory(prefix='kos-notification-contrast-') as directory:
    root=Path(directory)
    for name in ['desktop','Kos']:
        (root/name).symlink_to(REPO/'shell'/name,target_is_directory=True)
    shutil.copy(Path(__file__).with_name('shell.qml'),root/'shell.qml')
    with fixture.Server(str(root/'platform.sock'),fixture.Platform) as platform:
        threading.Thread(target=platform.serve_forever,daemon=True).start()
        env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',
                 XDG_CONFIG_HOME=str(root/'config'),XDG_STATE_HOME=str(root/'state'),
                 KOS_PLATFORM_SOCKET=str(root/'platform.sock'),KOS_DATA_SOCKET=str(root/'absent-data.sock'))
        result=subprocess.run(['qs','-p',str(root),'--no-color'],env=env,capture_output=True,text=True,timeout=16)
        output=result.stdout+result.stderr
        assert result.returncode==0 and output.count('NOTIFICATION_CONTRAST_PASS')==9,output
        assert not re.search(r'NOTIFICATION_CONTRAST_FAIL|ReferenceError|TypeError|Binding loop|Unable to assign|Property value set multiple times',output),output
        print('\n'.join(line for line in output.splitlines() if 'NOTIFICATION_CONTRAST_PASS' in line))
        platform.shutdown()
