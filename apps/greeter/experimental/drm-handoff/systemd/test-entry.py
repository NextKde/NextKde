#!/usr/bin/python3 -I
"""Run inside user/PID sandbox only: real dbus-run-session and fake KWin/UI."""
import importlib.machinery
import importlib.util
import os
import socket
import subprocess
from pathlib import Path
assert os.geteuid() == 0 and not Path('/dev/tty1').exists()
loader = importlib.machinery.SourceFileLoader('entry', '/tests/kos-greeter-session-handoff')
spec = importlib.util.spec_from_loader(loader.name, loader)
entry = importlib.util.module_from_spec(spec); loader.exec_module(entry)
parent, child = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
environment = {'GREETD_SOCK': '/fake-only', 'KOS_KWIN_HANDOFF_CONTROL_FD': str(child.fileno())}
plan = entry.launch_plan(environment)
assert plan[:3] == ['/usr/bin/dbus-run-session', '--', '/opt/kos-handoff/kwin/bin/kwin_wayland']
assert plan[-1] == '/usr/local/lib/kos-greeter/app/bin/kos-greeter-ui'
code = '''import os,socket,subprocess,sys
fd=int(os.environ.pop('KOS_KWIN_HANDOFF_CONTROL_FD'))
channel=socket.socket(fileno=fd)
assert channel.getsockopt(socket.SOL_SOCKET,socket.SO_TYPE)==socket.SOCK_SEQPACKET
os.set_inheritable(fd,False)
channel.send(b'PRIVATE-ARRIVED')
probe="import os,sys; assert 'KOS_KWIN_HANDOFF_CONTROL_FD' not in os.environ; assert not os.path.exists('/proc/self/fd/'+sys.argv[1])"
subprocess.run(['/usr/bin/python3','-I','-c',probe,str(fd)],check=True,close_fds=False)
'''
subprocess.run(plan[:2] + ['/usr/bin/python3', '-I', '-c', code], env=environment,
               pass_fds=(child.fileno(),), check=True, timeout=5)
assert parent.recv(128) == b'PRIVATE-ARRIVED'
for bad in ({}, {**environment, 'DISPLAY': ':fake'}):
    try: entry.launch_plan(bad)
    except (ValueError, OSError): pass
    else: raise AssertionError('unsafe entry accepted')
print('PASS fixed experimental entry; FD crosses real dbus-run-session to fake KWin and cannot enter UI')
print('PASS absent channel and existing desktop rejection; no real display or PAM used')
