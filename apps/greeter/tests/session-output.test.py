#!/usr/bin/env python3
"""No real VT touched: mocked Linux VT validation + isolated child fd inheritance."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch
import stat
from entry_launch_guard import block_real_launch

APP = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(APP/'companion'))
import session_output as output

class Output(unittest.TestCase):
 def test_non_vt_is_never_opened(self):
  for name in ('/dev/pts/1','/dev/tty','/dev/tty0','/dev/tty64','/tmp/tty1'):
   with patch.object(output.os,'ttyname',return_value=name), patch.object(output.os,'open') as opened:
    self.assertFalse(output.clear_inherited_vt()); opened.assert_not_called()
 def test_linux_vt_clear_only_same_device(self):
  info=SimpleNamespace(st_mode=stat.S_IFCHR,st_rdev=os.makedev(4,1),st_dev=5,st_ino=6)
  with patch.object(output.os,'ttyname',return_value='/dev/tty1'), patch.object(output.os,'fstat',return_value=info), \
    patch.object(output.fcntl,'ioctl') as ioctl,patch.object(output.os,'open',return_value=9) as opened, \
    patch.object(output.os,'write') as written,patch.object(output.os,'close') as closed:
   self.assertTrue(output.clear_inherited_vt())
   self.assertEqual(ioctl.call_args.args[:2],(0,0x4B3B))
   self.assertEqual(opened.call_args.args[0],'/dev/tty1')
   written.assert_called_once_with(9,b'\x1b[2J\x1b[3J\x1b[H');closed.assert_called_once_with(9)
 def test_vt_close_failure_does_not_abort(self):
  info=SimpleNamespace(st_mode=stat.S_IFCHR,st_rdev=os.makedev(4,1),st_dev=5,st_ino=6)
  with patch.object(output.os,'ttyname',return_value='/dev/tty1'),patch.object(output.os,'fstat',return_value=info), \
    patch.object(output.fcntl,'ioctl'),patch.object(output.os,'open',return_value=9),patch.object(output.os,'write'), \
    patch.object(output.os,'close',side_effect=OSError('fixture close failure')):
   self.assertTrue(output.clear_inherited_vt())
 def test_wrong_device_and_ioctl_failure(self):
  info=SimpleNamespace(st_mode=stat.S_IFCHR,st_rdev=os.makedev(4,1),st_dev=5,st_ino=6)
  different=SimpleNamespace(st_dev=5,st_ino=7,st_rdev=os.makedev(4,1))
  with patch.object(output.os,'ttyname',return_value='/dev/tty1'),patch.object(output.os,'fstat',side_effect=[info,different]), \
    patch.object(output.fcntl,'ioctl'),patch.object(output.os,'open',return_value=9),patch.object(output.os,'write') as written,patch.object(output.os,'close'):
   self.assertFalse(output.clear_inherited_vt());written.assert_not_called()
  with patch.object(output.os,'ttyname',return_value='/dev/tty1'),patch.object(output.os,'fstat',return_value=info), \
    patch.object(output.fcntl,'ioctl',side_effect=OSError()),patch.object(output.os,'open') as opened:
   self.assertFalse(output.clear_inherited_vt());opened.assert_not_called()
 def test_streams_inherited_without_stdin_change(self):
  with tempfile.TemporaryDirectory() as tmp:
   code='''import os,sys,subprocess
sys.path.insert(0,sys.argv[1]);import session_output as s
before=os.fstat(0)
s.journal_stream=lambda identifier,priority: os.open(sys.argv[2]+str(priority),os.O_CREAT|os.O_WRONLY,0o600)
s.prepare_session_output('fixture')
assert os.fstat(0)==before
print('parent stdout',flush=True); print('parent stderr',file=sys.stderr,flush=True)
subprocess.run([sys.executable,'-c','import sys;print("child stdout");print("child stderr",file=sys.stderr)'],check=True)
'''
   result=subprocess.run([sys.executable,'-c',code,str(APP/'companion'),tmp+'/stream-'],capture_output=True)
   self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(result.stdout,b'');self.assertEqual(result.stderr,b'')
   self.assertIn('parent stdout',(Path(tmp)/'stream-6').read_text());self.assertIn('child stdout',(Path(tmp)/'stream-6').read_text())
   self.assertIn('parent stderr',(Path(tmp)/'stream-3').read_text());self.assertIn('child stderr',(Path(tmp)/'stream-3').read_text())
 def test_failed_journal_is_silent_and_does_not_break_child(self):
  code='''import sys,subprocess
sys.path.insert(0,sys.argv[1]);import session_output as s
s.journal_stream=lambda *args: (_ for _ in ()).throw(OSError('fixture failure'))
s.prepare_session_output('fixture');print('should not reach tty');print('stderr hidden',file=sys.stderr)
subprocess.run([sys.executable,'-c','print("child hidden")'],check=True)
'''
  result=subprocess.run([sys.executable,'-c',code,str(APP/'companion')],capture_output=True)
  self.assertEqual(result.returncode,0);self.assertEqual(result.stdout,b'');self.assertEqual(result.stderr,b'')
 def test_disconnected_journal_diagnostics_do_not_abort_startup(self):
  with tempfile.TemporaryDirectory() as tmp:
   code="""import os,sys,subprocess
sys.path.insert(0,sys.argv[1]);import session_output as s
from pathlib import Path
def broken(*args):
 r,w=os.pipe();os.close(r);return w
s.journal_stream=broken
s.prepare_session_output('fixture');s.phase('PlasmaStarting');s.diagnostic('failure',error=True)
subprocess.run([sys.executable,'-c','print("hidden child")'],check=True)
Path(sys.argv[2]).write_text('continued')
"""
   result=subprocess.run([sys.executable,'-c',code,str(APP/'companion'),tmp+'/continued'],capture_output=True)
   self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(result.stdout,b'');self.assertEqual(result.stderr,b'')
   self.assertEqual((Path(tmp)/'continued').read_text(),'continued')
 def test_disconnect_after_ready_phase_is_safely_suppressed(self):
  code="""import os,sys
sys.path.insert(0,sys.argv[1]);import session_output as s
readers=[]
def stream(*args):
 r,w=os.pipe();readers.append(r);return w
s.journal_stream=stream;s.prepare_session_output('fixture')
for reader in readers:os.close(reader)
s.phase('PlasmaStarting');s.diagnostic('safe stderr',error=True)
"""
  result=subprocess.run([sys.executable,'-c',code,str(APP/'companion')],capture_output=True)
  self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(result.stdout,b'');self.assertEqual(result.stderr,b'')
 def test_open_and_dup_failures_are_silent(self):
  for failure in ('open','dup2'):
   code="""import sys,os
sys.path.insert(0,sys.argv[1]);import session_output as s
from pathlib import Path
s.journal_stream=lambda *a: (_ for _ in ()).throw(OSError('journal'))
def fail(*a,**k):raise OSError('injected redirect failure')
setattr(s.os,sys.argv[2],fail)
s.prepare_session_output('fixture');s.phase('PlasmaStarting');print('Python diagnostic suppressed')
# Marker fd opened before fault injection is unnecessary: use real write_text.
if sys.argv[2]=='open': s.os.open=original_open
Path(sys.argv[3]).write_text('continued')
""".replace('s.journal_stream=lambda','original_open=os.open\ns.journal_stream=lambda')
   with tempfile.TemporaryDirectory() as tmp:
    result=subprocess.run([sys.executable,'-c',code,str(APP/'companion'),failure,tmp+'/continued'],capture_output=True)
    self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(result.stdout,b'');self.assertEqual(result.stderr,b'')
    self.assertEqual((Path(tmp)/'continued').read_text(),'continued')
 def test_native_child_retains_ignored_sigpipe(self):
  with tempfile.TemporaryDirectory() as tmp:
   subprocess.run(['/bin/sh','-c','kill -PIPE $$; printf survived > "$1"','fixture',tmp+'/continued'],check=True,restore_signals=False)
   self.assertEqual((Path(tmp)/'continued').read_text(),'survived')
   user=(APP/'bin/kos-user-session').read_text();cover=(APP/'companion/cover.py').read_text()
   self.assertIn('restore_signals=False',user);self.assertIn('restore_signals=False',cover)
 def test_operational_check_before_exec_is_redirected(self):
  import runpy
  greeter=runpy.run_path(str(APP/'bin/kos-greeter-session'))['main']
  events=[];global_vars=greeter.__globals__
  with block_real_launch(), patch.dict(global_vars,prepare_session_output=lambda name:events.append('redirect'),check=lambda:events.append('check'),phase=lambda name:None,prepare_greeter_config=lambda env:dict(env, XDG_CONFIG_HOME='/fixture/private-config')), \
    patch.object(sys,'argv',['entry','--temporary-seat']),patch.dict(os.environ,{'GREETD_SOCK':'fixture'},clear=True), \
    patch.object(os,'execve',side_effect=lambda *args:events.append(('exec',args))):
   greeter()
  self.assertEqual(events[:2],['redirect','check'])
  command=events[2][1];self.assertEqual(command[0],'/usr/bin/dbus-run-session')
  self.assertIn('--drm',command[1]);self.assertIn('--exit-with-session',command[1])
  self.assertEqual(command[2]['XDG_CONFIG_HOME'],'/fixture/private-config')
  self.assertEqual(command[2]['KOS_GREETER_OUTPUT_APPLY'],'1')
 def test_check_command_remains_visible(self):
  result=subprocess.run([sys.executable,str(APP/'bin/kos-greeter-session'),'--check'],capture_output=True,text=True)
  self.assertEqual(result.returncode,0,result.stderr);self.assertIn('check passed',result.stdout)
  result=subprocess.run([sys.executable,str(APP/'bin/kos-user-session'),'--check'],capture_output=True,text=True)
  self.assertEqual(result.returncode,0,result.stderr);self.assertIn('PASS fixed Plasma',result.stdout)

if __name__=='__main__':unittest.main()
