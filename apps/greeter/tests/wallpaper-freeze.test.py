#!/usr/bin/env python3
"""Real QML source: stop an in-flight reload, hold snapshot, thaw and reload."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
APP = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    shutil.copytree(APP/'qml',root/'qml')
    (root/'companion').mkdir()
    (root/'companion/wallpaper.py').write_text('''import json,sys,time
from pathlib import Path
p=Path(__file__).with_name('counter')
n=int(p.read_text())+1 if p.exists() else 1
p.write_text(str(n))
time.sleep(.5)
print(json.dumps(dict(uid=int(sys.argv[1]),source='',fit='crop',version=str(n))))
''')
    (root/'shell.qml').write_text('''import QtQuick
import Quickshell
import "qml" as Greeter
ShellRoot {
 property string held: ""
 Greeter.WallpaperSource { id: source; uid: 1001 }
 Timer { interval: 1200; running: true; onTriggered: {
   if (source.state.version !== "1") throw new Error("Initial resource not loaded");
   held = source.state.version; source.frozen = true;
 } }
 Timer { interval: 2400; running: true; onTriggered: {
   if (source.state.version !== held) throw new Error("Frozen resource changed");
   console.info("PASS frozen in-flight reload leaves resource version unchanged");
   source.frozen = false;
 } }
 Timer { interval: 3300; running: true; onTriggered: {
   if (source.state.version === held) throw new Error("Thaw did not reload resource");
   console.info("PASS thaw reloads latest resource"); Qt.quit();
 } }
}''')
    env=os.environ.copy()
    for key in ('DISPLAY','WAYLAND_DISPLAY','GREETD_SOCK'): env.pop(key,None)
    env['QT_QPA_PLATFORM']='offscreen'
    result=subprocess.run(['qs','--log-rules','*.debug=false','-p',str(root)],env=env,capture_output=True,text=True,timeout=6)
    logs=result.stdout+result.stderr
    assert result.returncode==0 and 'Error:' not in logs,logs
    assert logs.count('PASS ')==2,logs
    print('\n'.join(line for line in logs.splitlines() if 'PASS ' in line))
