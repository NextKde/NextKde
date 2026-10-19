#!/usr/bin/env python3
import os, signal, subprocess, tempfile
from pathlib import Path
APP=Path(__file__).resolve().parents[1]
OUT=Path(os.environ.get('KOS_STARTUP_BACKGROUND_EVIDENCE', str(APP.parents[1]/'.build/greeter-tests/T11/startup-background')))
OUT.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='kos-first-frame-') as temp:
 env=dict(os.environ,XDG_CONFIG_HOME=temp+'/config',KOS_STARTUP_BACKGROUND_EVIDENCE=str(OUT))
 for k in ('DISPLAY','WAYLAND_DISPLAY','GREETD_SOCK','KOS_HANDOFF_SESSION','KOS_HANDOFF_SHA256'):env.pop(k,None)
 with (OUT/'virtual.log').open('w') as stream:
  p=subprocess.Popen(['dbus-run-session','--','kwin_wayland','--virtual','--output-count','2','--width','1024','--height','768','--socket','wayland-kos-background-'+str(os.getpid()),'--no-lockscreen','--no-global-shortcuts','--no-kactivities','--exit-with-session',str(APP/'tests/startup-background-session')],env=env,stdout=stream,stderr=stream,start_new_session=True)
  try:code=p.wait(timeout=35)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait();code=124
 text=(OUT/'virtual.log').read_text(errors='replace');print(text[-3500:]);assert code==0,code
 assert text.count('PASS first-frame ')==3,text
