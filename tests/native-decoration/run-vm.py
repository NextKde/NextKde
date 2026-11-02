#!/usr/bin/env python3
"""VM-only real Konsole acceptance for KDecoration controls and Bridge exclusion."""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import sys
import time
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tests/cooperative-controls'))
from x11_pointer import click


def wait(fn, timeout=15):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        value=fn()
        if value: return value
        time.sleep(.15)
    raise AssertionError('Timed out waiting for native decoration state')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--bridge',type=Path,required=True)
    p.add_argument('--decoration',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--session',action='store_true')
    p.add_argument('--outer-x11',default=':0')
    a=p.parse_args(); out=a.output.resolve()
    if a.session: session(a,out); return
    out.mkdir(parents=True,exist_ok=False)
    for source,target in [(a.bridge,'plugins/kwin/effects/plugins/kos_bridge.so'),(a.decoration,'plugins/org.kde.kdecoration3/kos_decoration.so')]:
        path=out/target;path.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,path)
    config=out/'config';(config/'kos').mkdir(parents=True)
    (config/'kwinrc').write_text('[org.kde.kdecoration2]\nlibrary=kos_decoration\nButtonsOnLeft=\nButtonsOnRight=IAX\n[Plugins]\nkos_bridgeEnabled=true\n')
    (config/'kos/window-appearance.json').write_text('{"enabled":true}')
    # Strongest legacy override must still never cover native controls.
    (config/'kos/window-buttons.json').write_text(json.dumps({'default':{'drawOnDecoratedWindows':'always','background':'auto'}}))
    wrapper=out/'session.sh';wrapper.write_text('#!/bin/sh\nexec '+shlex.join([sys.executable,str(Path(__file__).resolve()),'--session','--bridge',str(a.bridge.resolve()),'--decoration',str(a.decoration.resolve()),'--output',str(out),'--outer-x11',a.outer_x11])+'\n');wrapper.chmod(0o700)
    env=dict(os.environ,XDG_CONFIG_HOME=str(config),XDG_DATA_HOME=str(out/'data'),QT_PLUGIN_PATH=str(out/'plugins'))
    with (out/'kwin.log').open('w') as log, subprocess.Popen(['dbus-run-session','kwin_wayland','--x11-display',a.outer_x11,'--socket',f'native-controls-{os.getpid()}','--width','1100','--height','760','--no-lockscreen','--no-global-shortcuts','--no-kactivities','--exit-with-session',str(wrapper)],env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True) as proc:
        try:proc.wait(timeout=180)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid,signal.SIGTERM);proc.wait(timeout=10);raise
    assert (out/'passed').exists(), (out/'kwin.log').read_text()[-4500:]
    print('PASS:',out)


def session(a,out):
    from PIL import Image
    def dbus(path,method,*args):
        return subprocess.check_output(['qdbus6','org.kde.KWin',path,method,*args],text=True)
    def diagnostics():return json.loads(dbus('/Effects','org.kde.kwin.Effects.debug','kos_bridge','window-controls'))
    def state():return next((w for w in diagnostics()['windows'] if 'konsole' in w['windowClass'].lower()),None)
    def native():
        w=state()
        return w if w and w.get('decorationControls') and len(w.get('decorationButtons',[]))==3 else None
    def point(action):
        button=next(b for b in native()['decorationButtons'] if b['action']==action)
        x,y,w,h=button['rect'];return x+w/2,y+h/2
    def capture(label):
        click(a.outer_x11,capture_path=str(out/(label+'.png')))
    def colored_pixels(path, rect):
        image=Image.open(path)
        x,y,w,h=rect
        return sum(1 for r,g,b in image.crop((int(x),int(y),int(x+w),int(y+h))).getdata() if max(r,g,b)-min(r,g,b)>80 and max(r,g,b)>150)
    with (out/'konsole.log').open('w') as log, subprocess.Popen(['konsole','--separate','--hide-menubar','--hold','-e','/bin/true'],stdout=log,stderr=subprocess.STDOUT) as app:
        try:
            w=wait(native)
            time.sleep(1)
            w=native()
            assert w['decorated'] and not w['painted'] and not w['sampling'],w
            assert [b['action'] for b in sorted(w['decorationButtons'],key=lambda b:b['rect'][0])]==['minimize','maximize','close'],w
            (out/'initial.json').write_text(json.dumps(w,indent=2))
            def visible_controls(label, buttons):
                capture(label)
                return all(colored_pixels(out/(label+'.png'),b['rect'])>30 for b in buttons)
            wait(lambda:visible_controls('native-normal',native()['decorationButtons']))
            def glyph_signature(label):
                capture(label)
                x,y=point('maximize')
                return Image.open(out/(label+'.png')).crop((round(x)-4,round(y)-4,round(x)+4,round(y)+4)).tobytes()
            always=glyph_signature('glyph-always')
            rules=out/'config/kos/window-buttons.json'
            values=json.loads(rules.read_text());values['default']['glyphMode']='hover'
            rules.write_text(json.dumps(values))
            hidden=wait(lambda:(sig if (sig:=glyph_signature('glyph-hidden'))!=always else None))
            click(a.outer_x11,point('maximize'),move_only=True)
            wait(lambda:glyph_signature('glyph-hover')==always)
            click(a.outer_x11,(400,400),move_only=True)
            wait(lambda:glyph_signature('glyph-leave')==hidden)
            values['default']['glyphMode']='always';rules.write_text(json.dumps(values))
            wait(lambda:glyph_signature('glyph-restored')==always)
            click(a.outer_x11,point('maximize'))
            wait(lambda:state()['maximized'])
            click(a.outer_x11,point('maximize'))
            wait(lambda:not state()['maximized'])
            click(a.outer_x11,point('minimize'))
            wait(lambda:state()['minimized'])
            script=out/'restore.js';script.write_text('workspace.windowList().forEach(w=>{if(w.resourceClass.indexOf("konsole")>=0){w.minimized=false;workspace.activeWindow=w;}});')
            dbus('/Scripting','org.kde.kwin.Scripting.loadScript',str(script),'native-restore');dbus('/Scripting','org.kde.kwin.Scripting.start')
            wait(lambda:not state()['minimized'])
            # Right click may open KDE's native menu, but never a Bridge drag.
            initial=native()['decorationButtons']
            click(a.outer_x11,point('close'),button=3)
            click(a.outer_x11,(400,400))
            assert native()['decorationButtons']==initial
            assert not (out/'data/kos/window-buttons-rules.json').exists()
            # Reconfigure standard KDE button layout, not overlay offsets.
            rc=out/'config/kwinrc';rc.write_text(rc.read_text().replace('ButtonsOnLeft=\nButtonsOnRight=IAX','ButtonsOnLeft=XAI\nButtonsOnRight='))
            dbus('/KWin','org.kde.KWin.reconfigure')
            w=wait(lambda:(v if v and [b['action'] for b in sorted(v['decorationButtons'],key=lambda b:b['rect'][0])]==['close','maximize','minimize'] else None) if (v:=native()) else None)
            assert min(b['rect'][0] for b in w['decorationButtons']) < min(b['rect'][0] for b in initial)
            assert not w['painted'] and not w['sampling']
            (out/'left-layout.json').write_text(json.dumps(w,indent=2))
            # Native buttons remain even when the Bridge effect is unloaded.
            click(a.outer_x11,(400,400),move_only=True)
            dbus('/Effects','org.kde.kwin.Effects.unloadEffect','kos_bridge')
            time.sleep(1)
            wait(lambda:visible_controls('bridge-disabled',w['decorationButtons']))
            dbus('/Effects','org.kde.kwin.Effects.loadEffect','kos_bridge')
            wait(native)
            click(a.outer_x11,point('close'))
            app.wait(timeout=10)
            wait(lambda:not state())
            (out/'passed').write_text('Native Konsole layout/actions, no overlay/sampling/adjustment, and Bridge-independent rendering passed.\n')
        finally:
            if app.poll() is None:app.terminate();app.wait(timeout=5)

if __name__=='__main__':main()
