#!/usr/bin/env python3
"""Real Quickshell IPC against a test double; never PAM or a login proof."""
import json
import os
from pathlib import Path
import socket
import shutil
import struct
import subprocess
import tempfile
import threading

APP = Path(__file__).resolve().parents[1]

def receive(connection):
    def exact(size):
        result = b''
        while len(result) < size:
            chunk = connection.recv(size - len(result))
            if not chunk:
                raise EOFError
            result += chunk
        return result
    length = struct.unpack('<I', exact(4))[0]
    assert length < 65536
    return json.loads(exact(length))

def run(case):
    requests, errors = [], []
    with tempfile.TemporaryDirectory(prefix='kos-greeter-test-') as temporary:
        directory = Path(temporary)
        shutil.copytree(APP / 'qml', directory / 'qml')
        shutil.copytree(APP / 'wallpapers', directory / 'wallpapers')
        (directory / 'companion').mkdir()
        (directory / 'companion/wallpaper.py').write_text('import json,sys\nprint(json.dumps(dict(uid=int(sys.argv[1]),source="",fit="crop",version="default")))\n')
        (directory / 'companion/accounts.py').write_text('import json\nprint(json.dumps([{"uid":1001,"username":"fixture-alice","displayName":"Same name","avatar":""},{"uid":1002,"username":"fixture-bob","displayName":"Same name","avatar":""}]))\n')
        if case == 'single':
            (directory / 'companion/accounts.py').write_text('import json\nprint(json.dumps([dict(uid=1001,username="fixture-alice",displayName="Only user",avatar="")]))\n')
        (directory / 'qml/Lifecycle.js').write_text((APP / 'qml/Lifecycle.js').read_text())
        server = socket.socket(socket.AF_UNIX)
        server.bind(str(directory / 'greetd.sock'))
        server.listen(1)
        server.settimeout(10)

        def serve():
            try:
                connection, _ = server.accept()
                with connection:
                    connection.settimeout(10)
                    attempts = 0
                    rounds = 0
                    while True:
                        request = receive(connection)
                        # Persist only message types, never username or response.
                        kind = request['type']
                        requests.append(kind)
                        if kind == 'create_session':
                            attempts += 1
                            if case in ('alice', 'bob', 'cancel-alice'):
                                assert request['username'] == 'fixture-' + case.removeprefix('cancel-')
                            if case in ('setup-failure','backend-error','backend-reconnect'):
                                data = json.dumps({'type':'error','error_type':'auth_error' if case == 'setup-failure' else 'error','description':'Fixture unavailable backend'}).encode()
                                connection.sendall(struct.pack('<I',len(data))+data)
                                continue
                            rounds = 0
                            reply = {'type': 'auth_message', 'auth_message_type': 'secret', 'auth_message': 'Test prompt'}
                        elif kind == 'post_auth_message_response':
                            rounds += 1
                            if case == 'multi' and rounds <= 3:
                                message_type = ('info', 'error', 'visible')[rounds - 1]
                                reply = {'type': 'auth_message', 'auth_message_type': message_type, 'auth_message': 'Test ' + message_type}
                                data = json.dumps(reply).encode()
                                connection.sendall(struct.pack('<I', len(data)) + data)
                                continue
                            if case == 'disconnect':
                                return
                            if case in ('failure', 'cleanup-error') and attempts == 1:
                                reply = {'type': 'error', 'error_type': 'auth_error', 'description': 'Test failure'}
                            else:
                                reply = {'type': 'success'}
                        elif kind == 'cancel_session':
                            if case == 'cleanup-error' and attempts == 1:
                                reply = {'type':'error','error_type':'error','description':'unable to send message: Connection refused (os error 111)'}
                            else: reply = {'type': 'success'}
                        elif kind == 'start_session':
                            assert request['cmd'] == ['/usr/bin/python3', str(directory / 'bin/kos-user-session')]
                            assert request.get('env', []) == []
                            reply = ({'type': 'error', 'error_type': 'auth_error', 'description': 'Test launch rejection'}
                                     if case == 'launch-rejected' else {'type': 'success'})
                        else:
                            raise AssertionError('Unexpected protocol type')
                        data = json.dumps(reply).encode()
                        connection.sendall(struct.pack('<I', len(data)) + data)
            except EOFError:
                pass
            except Exception as exception:
                errors.append(type(exception).__name__)

        thread = threading.Thread(target=serve)
        thread.start()
        driver = '''
    property int testStage: 0
    Timer {
        interval: 30; repeat: true; running: true
        onTriggered: {
            if (["ReadyToLaunch", "Exiting", "LaunchRequested"].includes(root.phase) && !wallpaperSource.frozen)
                throw new Error("Wallpaper snapshot not frozen during exit");
            if (root.phase === "Idle" && wallpaperSource.frozen) throw new Error("Wallpaper recovery stayed frozen");
            if (root.testStage === 0) {
                if (TEST_SINGLE) {
                    if (root.phase !== "AwaitingPrompt") return;
                    root.testStage = 1;
                } else if (root.phase === "Idle" && root.accounts.length === 2) {
                    root.testStage = 1;
                    if (TEST_ACCOUNT >= 0) root.selectUser(root.accounts[TEST_ACCOUNT]);
                    else { root.selectUser(null); username.text = "fixture-user"; username.accepted(); }
                }
            } else if (TEST_BOOT && root.testStage === 1 && root.phase === "Idle" && root.feedback !== "") {
                console.info("TEST_SETUP_FAILED"); Qt.quit();
            } else if (root.testStage === 1 && root.phase === "AwaitingPrompt") {
                if (!response.enabled || !response.activeFocus) throw new Error("Password not ready and focused");
                root.testStage = 2;
                response.text = "fixture-response";
                if (TEST_CANCEL) { if (TEST_KEEP) root.cancel(); else root.backToList(); }
                else { response.accepted(); if (response.text !== "") throw new Error("Immediate wipe failed"); }
            } else if (root.testStage === 2 && TEST_CANCEL && !TEST_KEEP && root.phase === "Idle") {
                if (!root.choosingUser || username.text !== "" || response.text !== "" || !otherUserButton.activeFocus)
                    throw new Error("List recovery failed");
                console.info("TEST_CANCELLED"); Qt.quit();
            } else if (root.testStage === 2 && root.phase === "AwaitingPrompt") {
                if (response.text !== "" || !response.activeFocus) throw new Error("Retry did not clear and focus input");
                if (TEST_KEEP) { console.info("TEST_CANCELLED"); Qt.quit(); }
                else if (TEST_REJECT) {
                    if (root.feedback === "") throw new Error("Launch rejection diagnostic missing");
                    console.info("TEST_RECOVERED"); Qt.quit();
                } else {
                    if (TEST_MULTI && !root.echoResponse) throw new Error("Visible prompt did not enable echo");
                    if (TEST_FAILURE && root.feedback === "") throw new Error("Failure feedback missing");
                    root.testStage = 4; response.text = "fixture-response"; response.accepted();
                }
            }
        }
    }
'''.replace('TEST_BOOT', 'true' if case == 'setup-failure' else 'false').replace('TEST_SINGLE', 'true' if case == 'single' else 'false').replace('TEST_FAILURE', 'true' if case in ('failure','cleanup-error') else 'false').replace('TEST_REJECT', 'true' if case == 'launch-rejected' else 'false').replace('TEST_ACCOUNT', str({'alice': 0, 'bob': 1, 'cancel-alice': 0}.get(case, -1))).replace('TEST_MULTI', 'true' if case == 'multi' else 'false').replace('TEST_KEEP', 'true' if case == 'cancel-alice' else 'false').replace('TEST_CANCEL', 'true' if case in ('cancel', 'cancel-alice') else 'false')
        driver += """
 Timer { interval: 2200; running: true; repeat: true; onTriggered: { if (["disconnect", "frame-timeout", "backend-error", "backend-reconnect"].includes("CASE") && root.phase === "BackendUnavailable") { console.info("TEST_VISIBLE_RECOVERY"); if ("CASE" === "backend-reconnect") root.reconnectBackend(); else Qt.quit(); } } }
""".replace('CASE', case)
        source = (APP / 'shell.qml').read_text()
        if case == 'disconnect':
            source = source.replace('60000', '500')
        if case == 'frame-timeout':
            source = source.replace('watchdog.interval = 5000', 'watchdog.interval = 500').replace('function onFrameSwapped() { root.frameSubmitted(); }', 'function onFrameSwapped() {}')
        (directory / 'shell.qml').write_text(source.rsplit('}', 1)[0] + driver + '}\n')
        environment = os.environ.copy()
        if os.environ.get('KOS_T08_VIRTUAL') != '1':
            environment.pop('WAYLAND_DISPLAY', None)
            environment.pop('DISPLAY', None)
            environment['QT_QPA_PLATFORM'] = 'offscreen'
            # Offscreen has no mapped output. Only this test double supplies a frame event.
            driver += '''
    Timer { interval: 20; repeat: true; running: true; onTriggered: { if ("CASE" !== "frame-timeout") {
            let draining = root.exitFrameArmed && root.exitFramesRemaining === 2;
            root.frameSubmitted();
            if (draining && root.phase !== "Exiting") throw new Error("Stale swap launched session");
        } } }
'''.replace('CASE', case)
            (directory / 'shell.qml').write_text(source.rsplit('}', 1)[0] + driver + '}\n')
        environment['GREETD_SOCK'] = str(directory / 'greetd.sock')
        process = subprocess.run(['/usr/bin/qs', '--log-rules', '*.debug=false', '-p', str(directory)],
                                 env=environment, capture_output=True, timeout=12)
        thread.join(timeout=11)
        server.close()
        output = (process.stdout + process.stderr).decode(errors='replace')
        assert process.returncode == (75 if case == 'backend-reconnect' else 0), (case, output)
        assert not errors, errors
        assert not thread.is_alive(), 'Mock thread did not terminate'
        assert 'fixture-response' not in output, 'Response appeared in logs'
        assert 'TypeError' not in output and 'ReferenceError' not in output, output
        if case in ('success', 'single', 'failure', 'multi', 'alice', 'bob','cleanup-error'):
            assert requests[-1] == 'start_session', requests
            assert 'KOS_GREETER_STATE Terminated' in output
            states = ['ReadyToLaunch', 'Exiting', 'LaunchRequested', 'Terminated']
            positions = [output.index('KOS_GREETER_STATE ' + state) for state in states]
            assert positions == sorted(positions)
            markers = ['ExitStarted', 'ExitComplete', 'FrameSubmitted', 'LaunchRequested']
            positions = [output.index('KOS_GREETER_VISUAL ' + marker) for marker in markers]
            assert positions == sorted(positions), output
            times = [int(output.split('KOS_GREETER_VISUAL ' + marker + ' ', 1)[1].split()[0]) for marker in markers]
            assert times[1] - times[0] >= (0 if environment.get('KOS_GREETER_REDUCED_MOTION') == '1' else 180), times
        elif case == 'launch-rejected':
            assert 'start_session' in requests, requests
            assert requests.count('start_session') == 1, requests
            assert 'TEST_RECOVERED' in output and requests[-2:] == ['cancel_session', 'create_session'], output
        else:
            assert 'start_session' not in requests, requests
        if case in ('disconnect','frame-timeout','backend-error','backend-reconnect'):
            assert 'TEST_VISIBLE_RECOVERY' in output and 'start_session' not in requests, output
        if case == 'setup-failure':
            assert requests.count('create_session') == 1 and 'post_auth_message_response' not in requests and 'TEST_SETUP_FAILED' in output, requests
        if case == 'multi':
            assert requests.count('post_auth_message_response') == 4, requests
        if case in ('failure','cleanup-error'):
            assert requests.count('create_session') == 2
        if case == 'cancel':
            assert requests[-1] == 'cancel_session', requests
        if case == 'cancel-alice':
            assert requests[-2:] == ['cancel_session', 'create_session'], requests
        if os.environ.get('KOS_T08_VIRTUAL') == '1':
            evidence = Path(os.environ.get('KOS_GREETER_EVIDENCE', str(APP.parents[1] / 'docs/kos-greeter/evidence/T08')))
            evidence.mkdir(parents=True, exist_ok=True)
            (evidence / ('ipc-' + case + '.log')).write_text('\n'.join(line for line in output.splitlines() if 'KOS_GREETER_' in line or 'TEST_RECOVERED' in line) + '\n')
        print('PASS: actual Quickshell + mock IPC:', case, ','.join(requests))

for scenario in ('success', 'single', 'failure', 'cancel', 'disconnect', 'launch-rejected', 'multi', 'alice', 'bob', 'cancel-alice', 'frame-timeout', 'setup-failure','cleanup-error','backend-error','backend-reconnect'):
    run(scenario)
