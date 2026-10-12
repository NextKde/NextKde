#!/usr/bin/env python3
"""Machine display controller shared by Greeter and the desktop handoff.

Only explicit --apply changes outputs. No shell, credentials, user selection,
service installation or session-wide environment import.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import time

import outputs

APP = Path(__file__).resolve().parents[1]
DOCTOR = '/usr/bin/kscreen-doctor'
ROTATIONS = {1: 0, 2: 90, 4: 180, 8: 270}
ROTATION_NAMES = {0: 'none', 90: 'left', 180: 'inverted', 270: 'right'}


def edid_identity(data):
    if not data or len(data) > 32768 or len(data) % 128 or data[:8] != bytes.fromhex('00ffffffffffff00'):
        return None
    if len(data) != (data[126] + 1) * 128 or any(sum(data[i:i+128]) % 256 for i in range(0, len(data), 128)):
        return None
    return 'edid-sha256:' + hashlib.sha256(data).hexdigest()


def identities(drm=Path('/sys/class/drm')):
    result = {}
    for directory in drm.glob('card*-*'):
        if not re.fullmatch(r'card[0-9]+-.+', directory.name):
            continue
        try:
            if (directory / 'status').read_text().strip() != 'connected':
                continue
            with (directory / 'edid').open('rb') as stream:
                identity = edid_identity(stream.read(32769))
        except OSError:
            identity = None
        connector = directory.name.split('-', 1)[1]
        result.setdefault(connector, []).append(identity)
    return {name: values[0] if len(values) == 1 else None for name, values in result.items()}


def normalize(raw, hardware, lid_closed=False):
    inventory = []
    for output in raw['outputs']:
        modes = {str(m['id']): dict(width=m['size']['width'], height=m['size']['height'],
                                    refreshHz=m['refreshRate']) for m in output['modes']}
        preferred = next((modes[str(i)] for i in output.get('preferredModes', []) if str(i) in modes), None)
        connector = output['name']
        inventory.append(dict(connector=connector, hardwareId=hardware.get(connector),
                              connected=output['connected'], enabled=output['enabled'],
                              modes=list(modes.values()), currentMode=modes.get(str(output['currentModeId'])),
                              preferredMode=preferred, scale=output['scale'], rotation=ROTATIONS[output['rotation']],
                              position=[output['pos']['x'], output['pos']['y']], priority=output.get('priority', 0),
                              closed=lid_closed and connector.startswith(('eDP-', 'LVDS-'))))
    return inventory


def run(argv, timeout=4):
    # KScreen diagnostics can be verbose; never forward unreviewed stderr.
    process = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             timeout=timeout, check=True)
    if len(process.stdout) > 1024 * 1024:
        raise ValueError('Output inventory too large')
    return process.stdout


class Backend:
    def snapshot(self):
        raw = json.loads(run([DOCTOR, '-j']))
        try:
            lid = run(['/usr/bin/busctl', '--system', 'get-property', 'org.freedesktop.login1',
                       '/org/freedesktop/login1', 'org.freedesktop.login1.Manager', 'LidClosed'], 1).strip() == b'b true'
        except (OSError, subprocess.SubprocessError):
            lid = False
        inventory = normalize(raw, identities(), lid)
        self.raw = raw
        return inventory

    def apply(self, argv):
        if argv:
            run([DOCTOR, *argv])


def arguments(decision, inventory, raw):
    """Address the verified current connector; numeric IDs may change per query."""
    commands = []
    observed = {o['connector']: o for o in inventory}
    native = {o['name']: o for o in raw['outputs']}
    for target in decision['outputs']:
        current = observed[target['connector']]
        source = native[target['connector']]
        identifier = source['id']
        outputs.integer(identifier, 1, 2147483647)
        connector = source['name']
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', connector):
            raise ValueError('Unsafe connector')
        prefix = 'output.' + connector + '.'
        if not current['enabled']:
            commands.append(prefix + 'enable')
        if target['mode'] != current['currentMode']:
            selected = next(m for m in source['modes'] if outputs.exact(target['mode'], [dict(
                width=m['size']['width'], height=m['size']['height'], refreshHz=m['refreshRate'])]))
            mode_id = str(selected['id'])
            if not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', mode_id):
                raise ValueError('Unsafe backend mode ID')
            commands.append(prefix + 'mode.' + mode_id)
        for key, setting, value in (
            ('scale', 'scale', str(target['scale'])),
            ('rotation', 'rotation', ROTATION_NAMES[target['rotation']]),
            ('position', 'position', ','.join(map(str, target['position']))),
            ('priority', 'priority', str(target['priority']))):
            if target[key] != current[key]:
                commands.append(prefix + setting + '.' + value)
        if source.get('hdr', False):
            commands.append(prefix + 'hdr.disable')
        if source.get('wcg', False):
            commands.append(prefix + 'wcg.disable')
        if source.get('vrrPolicy', 0) != 0:
            commands.append(prefix + 'vrrpolicy.never')
    return commands


def effective(decision, inventory, raw):
    observed = {o['connector']: o for o in inventory}
    native = {o['name']: o for o in raw['outputs']}
    for target in decision['outputs']:
        current = observed.get(target['connector'])
        if current is None or not current['connected'] or not current['enabled'] or current.get('closed'):
            return False
        if current['currentMode'] is None or outputs.exact(target['mode'], [current['currentMode']]) is None:
            return False
        if any(current[k] != target[k] for k in ('scale', 'rotation', 'position', 'priority')):
            return False
        source = native[target['connector']]
        if source.get('hdr', False) or source.get('wcg', False) or source.get('vrrPolicy', 0) != 0:
            return False
    return bool(decision['outputs'])


def topology(inventory):
    return tuple(sorted((o['connector'], o['hardwareId'], o['connected'], o['enabled'], o.get('closed', False))
                        for o in inventory))


def safe_plan(inventory):
    # Empty policy deliberately never associates another screen by connector.
    unknown = dict(schemaVersion=1, outputs=[dict(hardwareId='edid-sha256:' + '0' * 64,
        connector='NO-OUTPUT', mode=dict(width=1, height=1, refreshHz=60), scale=1, rotation=0,
        position=[0, 0], priority=1, hdr=False, vrr='never')])
    return outputs.plan(unknown, inventory, 'startup')


class Controller:
    def __init__(self, backend, policy, apply=False):
        self.backend, self.policy, self.apply_enabled = backend, policy, apply
        self.first = True
        self.last_topology = None
        self.known = set()
        self.request_count = 0

    def tick(self):
        inventory = self.backend.snapshot()
        # Validate all observed data before considering a mutation.
        visible = outputs.plan(self.policy, inventory, 'hotplug')
        key = topology(inventory)
        changed = self.first or key != self.last_topology
        connected = {(o['connector'], o['hardwareId']) for o in inventory if o['connected'] and not o.get('closed')}
        fresh = {connector for connector, identity in connected - self.known}
        startup = outputs.plan(self.policy, inventory, 'startup')
        desired = startup if self.first else dict(startup, outputs=[o for o in startup['outputs'] if o['connector'] in fresh])
        # Consume the generation before any mutation/readback can fail.
        self.first = False
        self.last_topology = key
        self.known = {(o['connector'], o['hardwareId']) for o in inventory if o['connected'] and not o.get('closed')}
        status = 'observed'
        if self.apply_enabled and changed and desired['outputs']:
            commands = arguments(desired, inventory, self.backend.raw)
            if commands:
                self.request_count += 1
                try:
                    self.backend.apply(commands)
                    inventory = self.backend.snapshot()
                    if not effective(desired, inventory, self.backend.raw):
                        raise ValueError('Requested display settings did not become effective')
                    status = 'applied'
                except (ValueError, OSError, subprocess.SubprocessError):
                    # Exactly one fresh, supported fallback. Never retry this topology.
                    inventory = self.backend.snapshot()
                    fallback = safe_plan([o for o in inventory if o['connector'] in {t['connector'] for t in desired['outputs']}])
                    commands = arguments(fallback, inventory, self.backend.raw)
                    status = 'fallback'
                    if commands:
                        self.request_count += 1
                        try:
                            self.backend.apply(commands)
                        except (ValueError, OSError, subprocess.SubprocessError):
                            status = 'fallback-failed'
                    inventory = self.backend.snapshot()
                    if status == 'fallback' and not effective(fallback, inventory, self.backend.raw):
                        status = 'fallback-ineffective'
            else:
                status = 'already-effective'
        self.first = False
        self.last_topology = topology(inventory)
        self.known = {(o['connector'], o['hardwareId']) for o in inventory if o['connected'] and not o.get('closed')}
        visible = outputs.plan(self.policy, inventory, 'hotplug')
        native = {o['name']: o for o in self.backend.raw['outputs']}
        for output in visible['outputs']:
            source = native[output['connector']]
            output['actualHdr'] = source.get('hdr', False)
            output['actualVrrPolicy'] = source.get('vrrPolicy', 0)
        return dict(visible, status=status, requestCount=self.request_count, monotonicNs=time.monotonic_ns())


def trusted_policy(path):
    # Explicit source-tree entry is allowed for development; production root
    # snapshot and /etc policy must not be editable by the greeter account.
    path = Path(path)
    if not path.is_absolute():
        raise ValueError('Policy path must be absolute')
    for ancestor in [path, *path.parents]:
        info = ancestor.lstat()
        if stat.S_ISLNK(info.st_mode) or info.st_mode & 0o022 or info.st_uid not in (0, os.getuid()):
            raise ValueError('Untrusted policy path')
    return outputs.validate(outputs.read_json(path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    system_policy = Path('/etc/kos/greeter/outputs.json')
    parser.add_argument('--manifest', default=str(system_policy if system_policy.exists() else APP / 'config/outputs.json'))
    parser.add_argument('--watch', action='store_true')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    try:
        policy = trusted_policy(args.manifest)
    except (ValueError, OSError, KeyError, TypeError):
        # A missing/corrupt policy must not make login unavailable.
        policy = dict(schemaVersion=1, outputs=[dict(hardwareId='edid-sha256:' + '0' * 64,
            connector='NO-OUTPUT', mode=dict(width=1, height=1, refreshHz=60), scale=1, rotation=0,
            position=[0, 0], priority=1, hdr=False, vrr='never')])
    controller = Controller(Backend(), policy, args.apply)
    previous = None
    while True:
        try:
            result = controller.tick()
        except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError):
            result = dict(state='unavailable', outputs=[], primary=None, modeRequests=[], status='inventory-unavailable')
        signature = {k: v for k, v in result.items() if k != 'monotonicNs'}
        if signature != previous:
            print(json.dumps(result, separators=(',', ':')), flush=True)
            previous = signature
        if not args.watch:
            return
        time.sleep(1)


if __name__ == '__main__':
    main()
