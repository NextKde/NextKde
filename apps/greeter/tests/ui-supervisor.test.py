#!/usr/bin/env python3
import os
from pathlib import Path
import runpy
import signal
import subprocess
import sys
import tempfile
import time
import unittest
APP=Path(__file__).resolve().parents[1]
entry=runpy.run_path(str(APP/'bin/kos-greeter-ui'))

class UI(unittest.TestCase):
 def test_reconnect_then_success_and_fixed_command(self):
  with tempfile.TemporaryDirectory() as tmp:
   marker=Path(tmp)/'count'
   code='from pathlib import Path;import sys;p=Path(sys.argv[1]);n=int(p.read_text())+1 if p.exists() else 1;p.write_text(str(n));sys.exit(75 if n<3 else 0)'
   self.assertEqual(entry['run_ui']([sys.executable,'-c',code,str(marker)],delay=0),0)
   self.assertEqual(marker.read_text(),'3')
  self.assertEqual(entry['COMMAND'][:3],['/usr/bin/qs','--log-rules','*.debug=false'])
 def test_success_is_never_restarted(self):
  self.assertEqual(entry['run_ui']([sys.executable,'-c','pass'],delay=0),0)
 def test_retry_limit_is_failure(self):
  self.assertEqual(entry['run_ui']([sys.executable,'-c','raise SystemExit(75)'],delay=0),70)
 def test_real_quickshell_exit_codes(self):
  with tempfile.TemporaryDirectory() as tmp:
   env=dict(os.environ,QT_QPA_PLATFORM='offscreen')
   for name in ('WAYLAND_DISPLAY','DISPLAY','GREETD_SOCK'):env.pop(name,None)
   for code in (70,75):
    (Path(tmp)/'shell.qml').write_text('import QtQuick\nimport Quickshell\nShellRoot { Timer { interval: 1; running: true; onTriggered: Qt.exit('+str(code)+') } }\n')
    result=subprocess.run(['/usr/bin/qs','-p',tmp],env=env,capture_output=True,timeout=3)
    self.assertEqual(result.returncode,code,result.stderr)
 def test_signal_deadline_reaps_hung_ui(self):
  with tempfile.TemporaryDirectory() as tmp:
   marker=Path(tmp)/'ready'
   child_code='import signal,time,sys;from pathlib import Path;signal.signal(signal.SIGTERM,signal.SIG_IGN);Path(sys.argv[1]).write_text("ready");time.sleep(60)'
   launcher='import runpy,sys;m=runpy.run_path(sys.argv[1]);sys.exit(m["run_ui"]([sys.executable,"-c",sys.argv[2],sys.argv[3]],delay=0))'
   p=subprocess.Popen([sys.executable,'-c',launcher,str(APP/'bin/kos-greeter-ui'),child_code,str(marker)])
   try:
    deadline=time.monotonic()+3
    while not marker.exists() and time.monotonic()<deadline:time.sleep(.02)
    self.assertTrue(marker.exists());start=time.monotonic();p.send_signal(signal.SIGTERM)
    self.assertEqual(p.wait(timeout=4),70);self.assertLess(time.monotonic()-start,3)
   finally:
    if p.poll() is None:p.kill();p.wait()

if __name__=='__main__':unittest.main()
