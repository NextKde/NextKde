#!/usr/bin/env python3
"""Read-only acceptance probe for a real VM login; never logs the user out."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time


def output(*command):
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT, timeout=15).strip()


def session():
    sessions = output('loginctl', 'list-sessions', '--no-legend').splitlines()
    for line in sessions:
        identifier = line.split()[0]
        fields = dict(row.split('=', 1) for row in output(
            'loginctl', 'show-session', identifier,
            '-p', 'User', '-p', 'Type', '-p', 'Active').splitlines())
        if (fields.get('User') == str(os.getuid()) and fields.get('Active') == 'yes'
                and fields.get('Type') == 'wayland'):
            return identifier
    raise RuntimeError('No active Wayland login for this user')


def health():
    units = {}
    for name in ('kos-shell', 'kos-platform', 'kos-data'):
        fields = dict(line.split('=', 1) for line in output(
            'systemctl', '--user', 'show', name + '.service',
            '-p', 'ActiveState', '-p', 'SubState', '-p', 'MainPID',
            '-p', 'NRestarts').splitlines())
        if fields['ActiveState'] != 'active' or fields['SubState'] != 'running':
            raise RuntimeError(f'{name} is not running: {fields}')
        if int(fields['MainPID']) <= 0:
            raise RuntimeError(f'{name} has no process')
        units[name] = fields
    value = json.loads(output('qs', 'ipc', '--any-display', '--pid',
                             units['kos-shell']['MainPID'],
                             'call', 'integration-status', 'snapshot'))
    for key in ('shellReady', 'platformConnected', 'dataConnected', 'outputAvailable',
                'desktopWidgetsVisible', 'desktopFilesReady', 'dockVisible'):
        if value.get(key) is not True:
            raise RuntimeError(f'{key} is not ready: {value}')
    if value.get('barExpected') is not False and value.get('barVisible') is not True:
        raise RuntimeError(f'Expected Bar is not visible: {value}')
    return {'session': session(), 'units': units, 'snapshot': value}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--after', type=Path, help='Baseline from before logout/login')
    args = parser.parse_args()
    output('systemd-detect-virt', '--vm')  # fail closed on the physical host
    baseline = json.loads(args.after.read_text()) if args.after else None
    deadline = time.monotonic() + 90
    while True:
        try:
            first = health()
            if baseline and first['session'] == baseline['session']:
                raise RuntimeError('Still in the baseline session; re-login was not exercised')
            break
        except (RuntimeError, ValueError, subprocess.SubprocessError) as error:
            if time.monotonic() >= deadline:
                raise
            print(f'Waiting: {error}', flush=True)
            time.sleep(2)
    # Check repeatedly: an active unit or a single successful IPC reply can
    # otherwise conceal a crash/restart loop.
    for _ in range(15):
        time.sleep(2)
        current = health()
        if current['session'] != first['session'] or current['units'] != first['units']:
            raise RuntimeError(f'Session or service restarted: {first} -> {current}')
    first['checkedAt'] = time.strftime('%Y-%m-%dT%H:%M:%S%z')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(first, indent=2) + '\n')
    print(json.dumps(first, indent=2))


if __name__ == '__main__':
    main()
