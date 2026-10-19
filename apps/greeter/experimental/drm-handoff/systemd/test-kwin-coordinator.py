#!/usr/bin/python3
"""Real virtual KWin + real authorizer protocol; bus is an explicit fixture."""
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import tempfile
import time
assert os.environ.get('KOS_ISOLATED_HANDOFF_FIXTURE') == '1'
assert not list(Path('/dev/dri').glob('card*')) and not Path('/run/systemd/private').exists()
base = Path(__file__).resolve().parent
loader=importlib.machinery.SourceFileLoader('authorizer',str(base/'kos-handoff-authorize'))
spec=importlib.util.spec_from_loader(loader.name,loader)
helper=importlib.util.module_from_spec(spec);loader.exec_module(helper)
sys.path.insert(0,str(base.parents[2]/'companion'))
from greeter_config import prepare
kwin,session=sys.argv[1:3]
for expired in (False, True):
 runtime=Path(os.environ['XDG_RUNTIME_DIR'])
 fifo=runtime/'coordinator-exit.fifo';os.mkfifo(fifo,0o600)
 fifo_fd=os.open(fifo,os.O_RDWR|os.O_NONBLOCK)
 parent,child=socket.socketpair(socket.AF_UNIX,socket.SOCK_SEQPACKET)
 env=dict(prepare(os.environ),KOS_KWIN_HANDOFF_CONTROL_FD=str(child.fileno()),KWIN_COMPOSE='Q',QT_QPA_PLATFORM='wayland',QT_QPA_PLATFORMTHEME='',GTK_USE_PORTAL='0',QT_NO_XDG_DESKTOP_PORTAL='1',QT_FORCE_STDERR_LOGGING='1',QT_LOGGING_TO_CONSOLE='1',QT_LOGGING_RULES='*.info=true;*.warning=true')
 log=tempfile.TemporaryFile(mode='w+t')
 # The same inherited FD traverses real dbus-run-session, then real KWin.
 process=subprocess.Popen(['/usr/bin/dbus-run-session','--',kwin,'--virtual','--width','800','--height','600','--no-lockscreen','--no-global-shortcuts','--output-count','2','--socket','kos-coordinator-wayland','--exit-with-session',f'{session} {fifo}'],env=env,pass_fds=(child.fileno(),),stdout=log,stderr=subprocess.STDOUT)
 child.close()
 try:
  deadline=time.monotonic()+15
  while not (runtime/'kos-coordinator-wayland').exists():
   if process.poll() is not None or time.monotonic()>deadline: raise RuntimeError('virtual KWin startup failed')
   time.sleep(.05)
  time.sleep(.5)
  nonce=secrets.token_hex(16)
  helper.arm(parent,1000,nonce)
  calls=[]
  def fake_bus(path,method,signature=None,args=()):
   calls.append(method)
   if expired and method=='PrepareGreeterHandoff':time.sleep(2.1)
  helper.call=fake_bus
  try:helper.prepare_and_confirm(parent,'/fake-session',42,nonce)
  except ValueError:assert expired
  else:assert not expired
  assert calls==(['PrepareGreeterHandoff','CancelGreeterHandoff'] if expired else ['PrepareGreeterHandoff'])
  os.write(fifo_fd,b'X');assert process.wait(timeout=5)==0
  log.seek(0); output=log.read()
  assert ('KOS_DRM_HANDOFF NormalSessionExit' in output)==(not expired)
  print('PASS real virtual KWin + authorizer protocol functions:', 'delayed Prepare rollback' if expired else 'current PRESENTED/CONFIRM/READY commit')
 finally:
  parent.close();os.close(fifo_fd)
  if process.poll() is None:process.kill();process.wait()
  if process.returncode:log.seek(0);print(log.read())
  fifo.unlink(missing_ok=True)
print('Real KWin/real helper, explicitly fake bus; physical DRM/PAM not tested')
