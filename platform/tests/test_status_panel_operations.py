#!/usr/bin/env python3
"""Exercise panel operations with private helpers; never changes host power mode."""
import json, os, pathlib, socket, subprocess, sys, tempfile, time, shutil
binary = str(pathlib.Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix='kos-status-', dir='/tmp' if len(tempfile.gettempdir()) > 32 else None) as directory:
    root = pathlib.Path(directory)
    state = root / 'mode'
    state.write_text('balanced')
    helper = root / 'powerprofilesctl'
    helper.write_text('''#!/usr/bin/python3
import pathlib,sys,os
p=pathlib.Path(os.environ['TEST_POWER_STATE'])
if sys.argv[1]=='list':
 for mode in ['power-saver','balanced','performance']:
  print(('* ' if p.read_text()==mode else '  ')+mode+':')
elif sys.argv[1]=='set':
 if sys.argv[2]=='performance': sys.exit(1)
 p.write_text(sys.argv[2])
''')
    helper.chmod(0o755)
    ss = root / 'ss'
    ss.write_text('''#!/bin/sh
printf '%s\\n' 'ESTAB 0 0 a b users:(("browser",pid=111,fd=2)) ino:222 bytes_sent:3000 bytes_received:5000'
''')
    ss.chmod(0o755)
    runtime = root / 'runtime'
    runtime.mkdir(mode=0o700)
    env = dict(os.environ, PATH=directory+':'+os.environ['PATH'],
               TEST_POWER_STATE=str(state), XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM='offscreen')
    private_bus = subprocess.Popen([shutil.which('dbus-daemon'), '--session', '--nofork',
                                    '--nopidfile', '--print-address=1'], stdout=subprocess.PIPE,
                                   text=True)
    env['DBUS_SYSTEM_BUS_ADDRESS'] = private_bus.stdout.readline().strip()
    assert env['DBUS_SYSTEM_BUS_ADDRESS'].startswith('unix:')
    service = None
    log = open(root / 'daemon.log', 'w+')
    process = subprocess.Popen(['dbus-run-session','--',binary,'daemon'], env=env, stdout=log, stderr=log)
    try:
        path = runtime / 'kos-platform.sock'
        deadline = time.monotonic()+15
        while not path.exists() and time.monotonic()<deadline:
            if process.poll() is not None: raise RuntimeError((root/'daemon.log').read_text())
            time.sleep(.05)
        client=socket.socket(socket.AF_UNIX)
        client.settimeout(15)
        client.connect(str(path))
        stream=client.makefile('r')
        serial=0
        def call(op,payload=None):
            global serial
            serial+=1
            request={'version':1,'requestId':str(serial),'operation':op,'payload':payload or {}}
            client.sendall((json.dumps(request)+'\n').encode())
            while True:
                reply=json.loads(stream.readline())
                if reply.get('requestId')==str(serial): return reply
        apps=call('network.applications')
        assert apps['ok'], apps
        assert apps['result']['sockets'][0]['rxBytes']==5000, apps
        battery=call('power.battery')
        assert battery['ok'] and isinstance(battery['result']['batteries'],list), battery
        assert isinstance(battery['result']['adapters'],list), battery
        modes=call('power.profiles')
        assert modes['ok'] and modes['result']['activeProfile']=='balanced', modes
        assert call('power.profile.set',{'profile':'power-saver'})['ok']
        assert call('power.profiles')['result']['activeProfile']=='power-saver'
        assert not call('power.profile.set',{'profile':'performance'})['ok']
        assert call('power.profiles')['result']['activeProfile']=='power-saver'
        assert not call('power.profile.set',{'profile':'invalid'})['ok']
        # Start a delayed D-Bus service and make the present CLI unstartable.
        # This exercises the real daemon's FailedToStart fallback, not just a helper.
        service = subprocess.Popen([str(pathlib.Path(sys.argv[2]).resolve()), '--serve', 'freedesktop'],
                                   env=dict(env, KOS_FAKE_DELAY='250', KOS_FAKE_REJECT='performance'))
        helper.write_text('#!/nonexistent/kos-test-interpreter\n')
        time.sleep(.2)
        modes = call('power.profiles')
        assert modes['ok'] and modes['result']['activeProfile'] == 'balanced', modes
        assert call('power.profile.set', {'profile': 'power-saver'})['ok']
        assert call('power.profiles')['result']['activeProfile'] == 'power-saver'
        assert not call('power.profile.set', {'profile': 'performance'})['ok']
        assert call('power.profiles')['result']['activeProfile'] == 'power-saver'
        # A second socket must remain responsive while the first waits for Get.
        slow = socket.socket(socket.AF_UNIX)
        slow.settimeout(5)
        slow.connect(str(path))
        slow.sendall((json.dumps({'version': 1, 'requestId': 'slow',
                                 'operation': 'power.profiles', 'payload': {}})+'\n').encode())
        time.sleep(.05)
        started = time.monotonic()
        assert call('power.battery')['ok']
        assert time.monotonic() - started < .6, 'D-Bus lookup blocked the daemon'
        assert json.loads(slow.makefile('r').readline())['ok']
        slow.close()
        # An ordinary nonzero helper exit must NOT fall back to the available bus.
        helper.write_text('#!/bin/sh\nexit 1\n')
        assert not call('power.profiles')['ok']
        client.close()
        print('status panel operations: application counters, power read/set, rejection and failure recovery passed')
    finally:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill(); process.wait()
        log.close()
        if service is not None:
            service.terminate()
            service.wait(timeout=3)
        private_bus.terminate()
        private_bus.wait(timeout=3)
