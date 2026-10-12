#!/usr/bin/env python3
import os, signal, subprocess, tempfile
from pathlib import Path
APP=Path(__file__).resolve().parents[1]
OUT=Path(os.environ.get('KOS_ENTRY_EVIDENCE', str(APP.parents[1]/'docs/kos-greeter/evidence/T11')))
with tempfile.TemporaryDirectory(prefix='kos-t11-') as temp:
    env=dict(os.environ, XDG_CONFIG_HOME=temp+'/config', KOS_T11_EVIDENCE=str(OUT))
    for key in ('DISPLAY','WAYLAND_DISPLAY','GREETD_SOCK','KOS_HANDOFF_PATH','KOS_HANDOFF_SESSION','KOS_HANDOFF_SHA256'): env.pop(key,None)
    with (OUT/'virtual.log').open('w') as stream:
        p=subprocess.Popen(['dbus-run-session','--','kwin_wayland','--virtual','--output-count','2','--width','1024','--height','768','--socket','wayland-kos-t11-'+str(os.getpid()),'--no-lockscreen','--no-global-shortcuts','--no-kactivities','--exit-with-session',str(APP/'tests/entry-session')],env=env,stdout=stream,stderr=stream,start_new_session=True)
        try: code=p.wait(timeout=75)
        except subprocess.TimeoutExpired: os.killpg(p.pid,signal.SIGKILL);p.wait();code=124
    text=(OUT/'virtual.log').read_text(errors='replace')
    print(text[-5000:]);assert code==0,code
    assert text.count('PASS T11 ')==(9 if os.environ.get('KOS_T12_PRODUCTION_LAYER') == '1' else 7),text
