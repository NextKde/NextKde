#!/usr/bin/env python3
"""Restore only the changes made by test-greeter.py; safe to repeat."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import time

STATE = Path('/run/kos-greeter-test')
UNIT_DIR = Path('/run/systemd/system')
LOCK = Path('/run/lock/kos-greeter-test.lock')
TEST = 'kos-greeter-test.service'
GUARD = 'kos-greeter-rollback.service'
TIMER = 'kos-greeter-rollback.timer'
SWITCH = 'kos-greeter-switch.service'


def run(*args, check=True):
    return subprocess.run(args, check=check, text=True, capture_output=True, timeout=90)


def systemctl(*args, check=True):
    return run('/usr/bin/systemctl', *args, check=check)


def properties(unit):
    result = systemctl('show', unit, '-p', 'Id', '-p', 'LoadState', '-p', 'ActiveState', '-p', 'UnitFileState')
    return dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)


def trusted(path, directory=False):
    info = path.lstat()
    good_type = stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)
    if not good_type or info.st_uid != 0 or info.st_mode & 0o022:
        raise RuntimeError('Unsafe recovery path: ' + str(path))
    return info


def lock(wait=False):
    fd = os.open(LOCK, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    info = os.fstat(fd)
    if info.st_uid != 0 or info.st_mode & 0o077 or not stat.S_ISREG(info.st_mode):
        os.close(fd)
        raise RuntimeError('Unsafe coordination lock')
    deadline = time.monotonic() + (240 if wait else 0)
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            # A completed rollback may have removed the old lock while we waited.
            if LOCK.stat().st_ino != info.st_ino:
                os.close(fd)
                return lock(wait=wait)
            return fd
        except BlockingIOError:
            if not wait or time.monotonic() >= deadline:
                os.close(fd)
                raise RuntimeError('Another test/rollback is running; retry shortly')
            time.sleep(0.2)
        except OSError:
            os.close(fd)
            raise


def sessions():
    result = run('/usr/bin/loginctl', 'list-sessions', '--no-legend', '--no-pager')
    return [line.split()[0] for line in result.stdout.splitlines() if line.split()]


def session_service(session):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', session):
        raise RuntimeError('Invalid logind session identifier')
    result = run('/usr/bin/loginctl', 'show-session', session, '-p', 'Service', '--value', check=False)
    return result.stdout.strip() if result.returncode == 0 else ''


def snapshot():
    trusted(STATE, directory=True)
    trusted(STATE / 'private', directory=True)
    trusted(STATE / 'private/state.json')
    data = json.loads((STATE / 'private/state.json').read_text())
    if data.get('version') != 1 or not re.fullmatch(r'[A-Za-z0-9_.@-]+\.service', data.get('original', '')):
        raise RuntimeError('Invalid recovery snapshot')
    if data['original'] in (TEST, GUARD, SWITCH, 'greetd.service', 'display-manager.service'):
        raise RuntimeError('Invalid original manager')
    if type(data.get('vt')) is not int or not 1 <= data['vt'] <= 12:
        raise RuntimeError('Invalid recovery VT')
    return data


def restore():
    if not STATE.exists():
        print('No temporary Greeter test to roll back.')
        return
    data = snapshot()
    # Stop the daemon first; then terminate only sessions created by this test.
    if properties(TEST).get('LoadState') != 'not-found':
        systemctl('stop', TEST)
    for session in sessions():
        if session not in data['sessions'] and session_service(session) in ('greetd', 'greetd-greeter'):
            result = run('/usr/bin/loginctl', 'terminate-session', session, check=False)
            if result.returncode and session_service(session):
                raise RuntimeError('Cannot terminate the test login session')
    mask = UNIT_DIR / data['original']
    if mask.is_symlink() and os.readlink(mask) == '/dev/null':
        mask.unlink()
    elif mask.exists() or mask.is_symlink():
        raise RuntimeError('Original manager runtime unit changed; refusing to overwrite it')
    systemctl('daemon-reload')
    systemctl('start', data['original'])
    if properties(data['original']).get('ActiveState') != 'active':
        raise RuntimeError('Original display manager did not become active; recovery files retained')
    getty = 'getty@tty' + str(data['vt']) + '.service'
    if data['getty_active']:
        systemctl('start', getty)
    # Never change persistent enablement, aliases, PAM or greetd configuration.
    if properties(data['original']).get('UnitFileState') != data['original_enabled']:
        raise RuntimeError('Original enablement differs from snapshot; recovery files retained')
    if properties(TIMER).get('LoadState') != 'not-found':
        systemctl('stop', TIMER)
        if properties(TIMER).get('ActiveState') not in ('inactive', 'failed'):
            raise RuntimeError('Cannot stop rollback timer; recovery files retained')
    for name in (TEST, GUARD, TIMER):
        path = UNIT_DIR / name
        if path.exists():
            trusted(path)
            path.unlink()
    systemctl('daemon-reload')
    systemctl('reset-failed', TEST, GUARD, TIMER, check=False)
    shutil.rmtree(STATE)
    print('Rollback complete: original manager active; temporary app/config/units removed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--status', action='store_true', help='read-only test snapshot and service status')
    parser.add_argument('--auto', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('Run with sudo (or as root).')
    if args.status:
        if STATE.exists():
            data = snapshot()
            deadline = 'disabled' if data.get('seconds') == 0 else str(data['seconds']) + ' seconds'
            print('Original:', data['original'], '| timeout:', deadline)
            for name in (TEST, TIMER, data['original']):
                print(name, properties(name).get('ActiveState'))
        else:
            print('No temporary Greeter test.')
        return
    attempts = 3 if args.auto else 1
    for attempt in range(attempts):
        fd = None
        try:
            fd = lock(wait=args.auto)
            restore()
            LOCK.unlink(missing_ok=True)
            return
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
            if attempt + 1 == attempts:
                raise
        finally:
            if fd is not None:
                os.close(fd)
        time.sleep(5)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print('Rollback failed; keep recovery files and retry from TTY: ' + str(error), file=sys.stderr)
        sys.exit(1)
