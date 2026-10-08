#!/usr/bin/env python3
"""Exercise real daemon responses with isolated audio tools and a harmless desktop entry."""
import json
import os
from pathlib import Path
import sys
import tempfile
import time
from test_file_copy import start_daemon, stop_daemon, request


def main():
    binary = os.path.abspath(sys.argv[1])
    with tempfile.TemporaryDirectory(prefix="media-", dir="/tmp") as directory:
        root = Path(directory)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        state = root / "default"
        state.write_text("speakers")
        pactl = bin_dir / "pactl"
        pactl.write_text(f'''#!/usr/bin/env python3
import json,sys,time
from pathlib import Path
root=Path({directory!r})
args=sys.argv[1:]
if args == ['subscribe']:
    time.sleep(30)
elif args == ['--format=json','info']:
    print(json.dumps({{"default_sink_name":(root/'default').read_text()}}))
elif args == ['--format=json','list','sinks']:
    if (root/'malformed').exists(): print('invalid json')
    else: print(json.dumps([{{"name":n,"description":n.title()}} for n in ['speakers','headphones']]))
elif args[:1] == ['set-default-sink']:
    if args[1] not in ['speakers','headphones']: sys.exit(1)
    (root/'default').write_text(args[1])
else: sys.exit(1)
''')
        pactl.chmod(0o755)
        gio = bin_dir / "gio"
        gio.write_text('#!/bin/sh\nexit 87\n')
        gio.chmod(0o755)
        launcher = bin_dir / "record-launch"
        launcher.write_text(f'#!/usr/bin/env python3\nimport sys,json\nfrom pathlib import Path\nPath({str(root / "launched")!r}).write_text(json.dumps(sys.argv[1:]))\n')
        launcher.chmod(0o755)
        desktop = root / "fixture.desktop"
        desktop.write_text(f'[Desktop Entry]\nType=Application\nName=Media test\nExec={launcher} %f\nTerminal=false\n')
        desktop.chmod(0o755)
        target = root / 'file with spaces.txt'
        target.write_text('fixture')
        os.environ['PATH'] = str(bin_dir) + os.pathsep + os.environ['PATH']
        os.environ['KOS_PLATFORM_SOCKET'] = str(root / 'kos-platform.sock')
        proc, output, ready = start_daemon(binary, directory)
        try:
            assert ready, output
            sock = str(root / 'kos-platform.sock')
            def call(op, payload=None):
                return request(sock, op, op, payload or {})
            reply = call('audio.outputs')
            assert reply['ok'], reply
            assert [x['name'] for x in reply['result']['outputs'] if x['isDefault']] == ['speakers']
            assert call('audio.output.set-default', {'name':'headphones'})['ok']
            reply = call('audio.outputs')
            assert [x['name'] for x in reply['result']['outputs'] if x['isDefault']] == ['headphones']
            assert not call('audio.output.set-default', {'name':'missing'})['ok']
            assert not call('audio.output.set-default', {'name':'--help'})['ok']
            (root / 'malformed').touch()
            assert not call('audio.outputs')['ok']
            reply = call('file.launch', {'desktopFile':str(desktop), 'path':str(target)})
            assert reply['ok'], reply
            for _ in range(100):
                if (root / 'launched').exists(): break
                time.sleep(.05)
            assert json.loads((root / 'launched').read_text()) == [str(target)]
            desktop.write_text('[Desktop Entry]\nType=Link\nName=Invalid\nURL=https://example.com\n')
            assert not call('file.launch', {'desktopFile':str(desktop)})['ok']
            print('Audio enumeration, switching, failures and KDE desktop launch passed')
        finally:
            stop_daemon(proc, output)


if __name__ == '__main__':
    main()
