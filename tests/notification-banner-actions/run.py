#!/usr/bin/env python3
"""Click real Wayland banner controls and assert sender D-Bus callbacks."""
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib
REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('platform_fixture', REPO/'tests/widget-experience/run.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
requests = []
class Platform(fixture.Platform):
    def handle(self):
        for line in self.rfile:
            request = json.loads(line)
            requests.append(request)
            result = {'exists': False} if request['operation'] == 'state.read' else {}
            self.wfile.write((json.dumps({'version':1,'requestId':request['requestId'],'ok':True,'result':result})+'\n').encode())
            if request['operation'] == 'kwin.subscribe':
                windows = [{'id':entry+'-existing','appId':entry,'pid':990001+i,'minimized':True,'activated':False,
                            'desktops':[], 'geometry':{'x':0,'y':0,'width':500,'height':600}}
                           for i,entry in enumerate(['qq','wechat','org.telegram.desktop'])]
                self.wfile.write((json.dumps({'version':1,'event':'window.snapshot','payload':{'type':'snapshot','windows':windows}})+'\n').encode())
            self.wfile.flush()
DBusGMainLoop(set_as_default=True)
context = GLib.MainContext.default()
def wait(seconds=.3):
    end = time.monotonic()+seconds
    while time.monotonic()<end:
        while context.pending(): context.iteration(False)
        time.sleep(.01)
with tempfile.TemporaryDirectory(prefix='kos-notification-actions-') as directory, \
        tempfile.TemporaryDirectory(prefix='kos-na-', dir=os.environ['XDG_RUNTIME_DIR']) as runtime_directory:
    root=Path(directory)
    for name in ['desktop','Kos']:
        (root/name).symlink_to(REPO/'shell'/name, target_is_directory=True)
    shutil.copy(Path(__file__).with_name('shell.qml'),root/'shell.qml')
    # run-tests.sh puts TMPDIR inside the build tree. A runtime directory below
    # that long path can exceed Linux's 108-byte Unix socket pathname limit.
    runtime = Path(runtime_directory)
    wayland=os.environ.get('WAYLAND_DISPLAY','wayland-0')
    (runtime/wayland).symlink_to(Path(os.environ['XDG_RUNTIME_DIR'])/wayland)
    daemon=subprocess.Popen(['dbus-daemon','--session','--nofork','--print-address=1'],
                            stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,start_new_session=True)
    address=daemon.stdout.readline().strip()
    env=dict(os.environ, DBUS_SESSION_BUS_ADDRESS=address, QT_QPA_PLATFORM='wayland',
             XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(root/'config'), XDG_STATE_HOME=str(root/'state'),
             KOS_PLATFORM_SOCKET=str(root/'platform.sock'), KOS_DATA_SOCKET=str(root/'absent-data.sock'), QS_DISABLE_FILE_WATCHER='1')
    with fixture.Server(str(root/'platform.sock'),Platform) as platform:
        threading.Thread(target=platform.serve_forever,daemon=True).start()
        with (root/'log').open('w') as log:
            shell=subprocess.Popen(['quickshell','-p',str(root),'--no-color'],env=env,stdout=log,stderr=log)
            try:
                bus=dbus.bus.BusConnection(address)
                for _ in range(100):
                    if bus.name_has_owner('org.freedesktop.Notifications'): break
                    if shell.poll() is not None: raise AssertionError((root/'log').read_text())
                    wait(.05)
                api=dbus.Interface(bus.get_object('org.freedesktop.Notifications','/org/freedesktop/Notifications'),'org.freedesktop.Notifications')
                actions=[]; closed=[]
                bus.add_signal_receiver(lambda *args: actions.append(tuple(map(str,args))),signal_name='ActionInvoked',dbus_interface='org.freedesktop.Notifications')
                bus.add_signal_receiver(lambda *args: closed.append(tuple(map(str,args))),signal_name='NotificationClosed',dbus_interface='org.freedesktop.Notifications')
                def ipc(method,*args):
                    return subprocess.check_output(['qs','ipc','-p',str(root),'call','test',method,*map(str,args)],env=env,text=True,timeout=5).strip()
                def send(app,entry,resident=False):
                    return int(api.Notify(app,0,'',app+' banner test','Synthetic notification',dbus.Array(['default','default'],signature='s'),
                        dbus.Dictionary({'desktop-entry':dbus.String(entry),'urgency':dbus.Byte(2),'resident':dbus.Boolean(resident)},signature='sv'),-1))
                for app,entry in [('WeChat','wechat'),('Telegram Desktop','org.telegram.desktop'),('QQ','qq')]:
                    ident=send(app,entry); wait(.5)
                    assert ipc('click',entry,'查看')=='true',(entry,ipc('state'),(root/'log').read_text())
                    wait(.25)
                    assert (str(ident),'default') in actions,(actions,closed,ipc('state'),(root/'log').read_text())
                older=send('QQ','qq'); newest=send('QQ','qq'); wait(.5)
                assert ipc('click','qq','查看')=='true'
                wait(.3)
                assert (str(newest),'default') in actions,(actions,closed)
                assert str(older) not in [row[0] for row in closed],('other chat was closed',closed)
                assert ipc('invoke',older)=='true'
                wait(.2)
                assert (str(older),'default') in actions,actions
                ident=send('WeChat','wechat'); wait(.5)
                assert ipc('click','wechat','body')=='true'
                wait(.3)
                assert (str(ident),'default') in actions,('body did not open', actions)
                ipc('clear'); wait(.2)
                for app,entry,title in [('系统通知','system','检测到USB设备'),('DeskCenter','deskcenter','剪贴板中没有可粘贴的文件')]:
                    ident=int(api.Notify(app,0,'',title,'Pure informational notification',
                        dbus.Array([],signature='s'),dbus.Dictionary({'desktop-entry':dbus.String(entry),'urgency':dbus.Byte(2)},signature='sv'),-1))
                    wait(.4)
                    assert ipc('click',entry,'查看')=='false' and ipc('click',entry,'打开')=='false'
                    assert ipc('historyHover',ident)=='true'
                    wait(.1)
                    state=json.loads(ipc('historyState',ident))
                    assert state=={'hovered':True,'hasAction':False,'openVisible':False,'deleteVisible':True},state
                    assert ipc('historyClick',ident)=='true'
                    ipc('click',entry,'body'); wait(.1)
                    assert str(ident) not in [row[0] for row in actions],actions
                ident=send('QQ','qq'); wait(.4)
                assert ipc('historyHover',ident)=='true'; wait(.1)
                state=json.loads(ipc('historyState',ident))
                assert state['hasAction'] and state['openVisible'],state
                assert ipc('historyClick',ident)=='true'; wait(.2)
                assert (str(ident),'default') in actions,actions
                activations = [r['payload'].get('id') for r in requests
                    if r['operation']=='kwin.command' and r['payload'].get('action')=='activate']
                assert {'qq-existing','wechat-existing','org.telegram.desktop-existing'} <= set(activations),activations
                assert not any(r['operation']=='application.launch' for r in requests),requests
                output=(root/'log').read_text()
                assert not re.search(r'ReferenceError|TypeError|Binding loop|Unable to assign',output),output
                print('PASS: pure USB/clipboard notices have no open buttons or launch side effects and remain deletable; QQ/WeChat/Telegram history/banner actions still invoke exact IDs; zero new launches')
            except Exception:
                print((root/'log').read_text())
                raise
            finally:
                shell.terminate(); shell.wait(timeout=5)
                # Activated portal services can inherit the runner's pipes and
                # keep CTest waiting after Python exits. Retire this private
                # bus's whole process group, including its activated children.
                try: os.killpg(daemon.pid,signal.SIGTERM)
                except ProcessLookupError: pass
                daemon.wait(timeout=5)
                platform.shutdown()
