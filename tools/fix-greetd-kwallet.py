#!/usr/bin/env python3
"""Add optional KWallet PAM hooks to greetd, with a root-only backup."""
import datetime
import os
from pathlib import Path
import stat
import tempfile


def main():
    if os.geteuid() != 0:
        raise SystemExit('Run with pkexec or sudo; no password is accepted by this script.')
    module = Path('/usr/lib/security/pam_kwallet5.so')
    if not module.is_file(): raise SystemExit('Missing pam_kwallet5.so; no changes made.')
    target = Path('/etc/pam.d/greetd')
    metadata = target.lstat()
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0 or metadata.st_mode & 0o022:
        raise SystemExit('Unsafe greetd PAM file; no changes made.')
    original = target.read_bytes()
    lines = original.decode('utf-8').splitlines()
    for kind, arguments in [('auth', ' force_run'), ('session', ' auto_start force_run')]:
        tokens = [line.split('#', 1)[0].split() for line in lines]
        hooks = [parts for parts in tokens if len(parts) >= 3 and parts[0].lstrip('-') == kind and parts[2] == 'pam_kwallet5.so']
        if hooks:
            if len(hooks) != 1 or hooks[0][1] != 'optional' or (kind == 'session' and 'auto_start' not in hooks[0]):
                raise SystemExit('Existing KWallet hook differs; no changes made.')
            # Arguments are parsed at auth time and reused by the session hook.
            # greetd opens PAM before the graphical session exists.
            if 'force_run' not in hooks[0]:
                index = next(i for i, line in enumerate(lines) if line.split('#', 1)[0].split() == hooks[0])
                fields = lines[index].split('#', 1)
                lines[index] = fields[0].rstrip() + ' force_run' + (' #' + fields[1] if len(fields) == 2 else '')
            continue
        positions = [index for index, line in enumerate(lines) if len(line.split()) >= 3 and line.split()[0] == kind and line.split()[1:3] == ['include', 'system-local-login']]
        if len(positions) != 1: raise SystemExit('Unexpected greetd PAM layout; no changes made.')
        lines.insert(positions[0]+1, f'-{kind:<10} optional     pam_kwallet5.so{arguments}')
    updated = ('\n'.join(lines)+'\n').encode()
    if updated == original:
        print('KWallet PAM hooks already configured; no changes needed.')
        return
    backup_dir = Path('/var/backups/kos-greeter')
    backup_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = backup_dir.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o077:
        raise SystemExit('Unsafe backup directory; no changes made.')
    backup = backup_dir / ('greetd-pam-' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    with backup.open('xb') as output:
        os.fchmod(output.fileno(), 0o600)
        output.write(original); output.flush(); os.fsync(output.fileno())
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, prefix='.greetd-kwallet-', delete=False) as output:
            temporary = Path(output.name)
            os.fchown(output.fileno(), metadata.st_uid, metadata.st_gid)
            os.fchmod(output.fileno(), stat.S_IMODE(metadata.st_mode))
            output.write(updated); output.flush(); os.fsync(output.fileno())
        current = target.lstat()
        fields = ('st_dev', 'st_ino', 'st_mtime_ns', 'st_mode', 'st_uid', 'st_gid', 'st_size')
        if target.read_bytes() != original or any(getattr(current, field) != getattr(metadata, field) for field in fields):
            raise SystemExit('PAM file changed concurrently; no changes made.')
        os.replace(temporary, target)
        directory = os.open(target.parent, os.O_RDONLY | os.O_DIRECTORY)
        try: os.fsync(directory)
        finally: os.close(directory)
    finally:
        if temporary is not None: temporary.unlink(missing_ok=True)
    print('Configured optional KWallet auth/session hooks for greetd.')
    print('Backup: ' + str(backup))
    print('Applies on the next password login; current session is unchanged.')


if __name__ == '__main__':
    main()
