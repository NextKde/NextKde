#!/usr/bin/env python3
"""Build/install KOS Greeter and persistently select greetd; reversible snapshot."""
import argparse
import ctypes
import uuid
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import stat
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[1]
APP_REL = 'usr/local/lib/kos-greeter/app'
STATE_REL = 'var/lib/kos-greeter-install'
FILES = ('etc/greetd/config.toml', 'etc/systemd/system/greetd.service.d/kos-greeter.conf',
         'etc/systemd/system/kos-greeter-recover.service',
         'etc/systemd/user/kos-shell.service.d/kos-greeter.conf', 'usr/local/sbin/kos-greeter-rollback')
GREETER_POLICY = b'[Unit]\nAfter=getty@tty1.service\nConflicts=getty@tty1.service\nOnFailure=kos-greeter-recover.service\nStartLimitIntervalSec=infinity\nStartLimitBurst=3\n[Service]\nRestart=always\nRestartSec=1\n'
NAME = re.compile(r'[A-Za-z0-9_.@-]+\.service')


def run(*args, check=True, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, check=check, timeout=90, **kwargs)


def public_umask(function):
    def wrapped(*args, **kwargs):
        previous = os.umask(0o022)
        try: return function(*args, **kwargs)
        finally: os.umask(previous)
    return wrapped


def systemctl(*args, check=True): return run('/usr/bin/systemctl', *args, check=check)


def properties(unit):
    result = systemctl('show', unit, '-p', 'Id', '-p', 'LoadState', '-p', 'ActiveState', '-p', 'UnitFileState')
    return dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)


def atomic(path, data, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.kos-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as out:
            os.fchmod(out.fileno(), mode); out.write(data); out.flush(); os.fsync(out.fileno())
        os.replace(name, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try: os.fsync(directory)
        finally: os.close(directory)
    finally:
        Path(name).unlink(missing_ok=True)


def regular(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode): raise RuntimeError('Not a regular file: ' + str(path))
    return info


def read_regular(path, limit=128*1024*1024):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
            raise RuntimeError('Invalid/oversized file: ' + str(path))
        with os.fdopen(fd, 'rb', closefd=False) as stream:
            data = stream.read(limit + 1)
        if len(data) > limit: raise RuntimeError('File exceeded budget')
        return data
    finally: os.close(fd)


def shell_compatibility(directory):
    """Read-only capability check; independent app never upgrades the Shell."""
    required = {
        'desktop/modules/common/SessionEntryService.qml': ('function check()', 'WindowService.providerReady'),
        'desktop/modules/common/qmldir': ('singleton SessionEntryService',),
        'desktop/modules/dock/DockWindow.qml': ('SessionEntryService', 'entryFrameSubmitted'),
        'desktop/modules/bar/BarWindow.qml': ('SessionEntryService', 'entryFrameSubmitted'),
        'desktop/modules/wallpaper/SpatialWallpaperWindow.qml': ('SessionEntryService', 'onFrameSwapped'),
        'desktop/modules/wallpaper/WallpaperImageLayer.qml': ('SessionEntryService',),
        'Kos/Ui/wallpapers/StaticWallpaperImage.qml': ('Image',),
        'Kos/Ui/wallpapers/qmldir': ('StaticWallpaperImage',),
    }
    missing = []
    for relative, markers in required.items():
        try: content = (directory / relative).read_text()
        except OSError: content = ''
        if not all(marker in content for marker in markers): missing.append(relative)
    return missing


def require_caller_shell():
    caller = int(os.environ.get('SUDO_UID', '-1'))
    if caller <= 0: raise RuntimeError('Install using sudo from your desktop account')
    directory = Path(pwd.getpwuid(caller).pw_dir) / '.config/quickshell/kos'
    missing = shell_compatibility(directory)
    if missing:
        raise RuntimeError('Installed Shell lacks compatible login handoff: ' + ', '.join(missing)
            + '. As your normal user run: python3 ' + str(REPO / 'tools/sync-greeter-shell.py')
            + ' --check; then repeat without --check, and rerun install. No restart is performed.')


def build(destination, sync=True):
    if os.geteuid() == 0: raise RuntimeError('Build as your normal user, not sudo')
    spec = importlib.util.spec_from_file_location('greeter_packaging', REPO / 'tools/test-greeter.py')
    pack = importlib.util.module_from_spec(spec); spec.loader.exec_module(pack)
    shared = pack.wallpaper_files()
    target = destination.absolute()
    if target.exists() or target.is_symlink(): raise RuntimeError('Build destination already exists; choose a new directory')
    target.mkdir(parents=True, mode=0o700)
    try:
        for relative in (*pack.FILES, 'companion/entry.py'):
            source = pack.APP / relative; regular(source)
            dest = target / 'app' / relative; dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(source.read_bytes()); dest.chmod(0o755 if relative.startswith('bin/') else 0o644)
        for relative in shared:
            dest = target / 'app/wallpapers' / relative; dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes((pack.SHARED / relative).read_bytes()); dest.chmod(0o644)
        # Compile without running the helpers or introducing bytecode in source.
        for file in (target/'app').rglob('*.py'):
            compile(file.read_bytes(), str(file), 'exec')
        for file in (target/'app/bin').iterdir():
            if file.read_bytes().startswith(b'#!/usr/bin/env python3'):
                compile(file.read_bytes(), str(file), 'exec')
        kos = pack.kos_wallpaper() if sync else None
        if kos:
            uid, image, fit = kos
            (target/'wallpaper.png').write_bytes(image)
            (target/'wallpaper.json').write_text(json.dumps(dict(uid=uid, fit=fit)))
        manifest = {}
        for file in sorted(target.rglob('*')):
            if file.is_file():
                manifest[str(file.relative_to(target))] = dict(hash=hashlib.sha256(file.read_bytes()).hexdigest(), mode=stat.S_IMODE(file.stat().st_mode))
        (target/'manifest.json').write_text(json.dumps(manifest, sort_keys=True))
    except BaseException:
        shutil.rmtree(target); raise
    print('Built standalone QML/Python app bundle:', target)


class Installer:
    # Alternate filesystem root is for unit tests only; CLI always uses /.
    def __init__(self, root=Path('/')):
        self.root = root; self.state = root/STATE_REL; self.app = root/APP_REL
        self.units = root/'etc/systemd/system'

    def safe(self, path):
        for parent in (path, *path.parents):
            if parent == self.root.parent and self.root != Path('/'): break
            if parent.exists() or parent.is_symlink():
                info = parent.lstat()
                if stat.S_ISLNK(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o022:
                    raise RuntimeError('Unsafe managed path: ' + str(parent))
            if parent == self.root: break

    def lock(self):
        path = self.root/'run/kos-greeter-install.lock'; self.safe(path.parent)
        path.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(path, os.O_CREAT|os.O_RDWR|os.O_NOFOLLOW, 0o600)
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077:
            os.close(fd); raise RuntimeError('Unsafe install lock')
        try: fcntl.flock(fd, fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BaseException: os.close(fd); raise RuntimeError('Another installation/rollback is running')
        return fd  # Keep the pathname stable, including after rollback.

    def links(self, original):
        result = {}
        if not self.units.exists(): return result
        for directory, dirs, files in os.walk(self.units, followlinks=False):
            for name in (*dirs, *files):
                path = Path(directory)/name
                if path.is_symlink():
                    target = os.readlink(path)
                    if name == 'display-manager.service' or Path(target).name in (original, 'greetd.service'):
                        result[str(path.relative_to(self.root))] = target
        return result

    def validate_bundle(self, bundle):
        regular(bundle/'manifest.json')
        manifest = json.loads(read_regular(bundle/'manifest.json', 256*1024))
        if not isinstance(manifest, dict) or not 1 <= len(manifest) <= 1000: raise RuntimeError('Invalid bundle manifest')
        total = 0
        for relative, record in manifest.items():
            path = Path(relative)
            if path.is_absolute() or '..' in path.parts or not (path.parts[0] == 'app' or relative in ('wallpaper.png','wallpaper.json')):
                raise RuntimeError('Invalid bundle path')
            if not isinstance(record, dict) or set(record) != {'hash','mode'} or record['mode'] not in (0o600,0o644,0o755):
                raise RuntimeError('Invalid bundle record')
            if relative.startswith('app/') and record['mode'] != (0o755 if relative.startswith('app/bin/') else 0o644):
                raise RuntimeError('Invalid runtime file permissions')
            source = bundle/path
            if any(p.is_symlink() for p in (source,*source.parents)): raise RuntimeError('Symlinked bundle')
            info = regular(source); total += info.st_size
            if total > 128*1024*1024 or hashlib.sha256(read_regular(source)).hexdigest() != record['hash']:
                raise RuntimeError('Bundle changed or exceeded size budget')
        for required in ('app/shell.qml','app/cover.qml','app/bin/kos-greeter-session','app/bin/kos-greeter-ui','app/bin/kos-user-session','app/companion/entry.py','app/companion/greeter_config.py','app/companion/session_output.py','app/companion/plasma_session.py'):
            if required not in manifest: raise RuntimeError('Incomplete bundle')
        return manifest

    def preflight(self):
        if (self.root/'run/kos-greeter-test').exists():
            raise RuntimeError('Temporary test is active; first run tools/rollback-greeter.py')
        for relative in (*FILES, APP_REL, STATE_REL): self.safe((self.root/relative).parent)
        for relative in FILES:
            path = self.root/relative
            if path.exists() or path.is_symlink(): self.safe(path); regular(path)
        if self.app.exists() or self.app.is_symlink(): raise RuntimeError('Installation already exists; roll it back before replacing it')
        if self.app.parent.exists(): raise RuntimeError('Reserved install directory already exists; refusing to overwrite it')
        if not (self.root/'etc/pam.d/greetd').is_file(): raise RuntimeError('Install distribution greetd/PAM first; PAM is not generated')
        account = pwd.getpwnam('greeter')
        if account.pw_uid == 0: raise RuntimeError('greeter must not be root')
        original = properties('display-manager.service'); name = original.get('Id','')
        if not NAME.fullmatch(name) or name in ('greetd.service','display-manager.service','kos-greeter-recover.service'):
            raise RuntimeError('Cannot identify the previous display manager')
        if original.get('UnitFileState') not in ('enabled','disabled','static','indirect'):
            raise RuntimeError('Previous manager has unsupported enablement/mask state')
        greetd = properties('greetd.service')
        if greetd.get('LoadState') != 'loaded' or greetd.get('ActiveState') not in ('inactive','failed') or greetd.get('UnitFileState') not in ('enabled','disabled','indirect'):
            raise RuntimeError('greetd must be installed, unmasked and not running')
        if properties('kos-greeter-recover.service').get('LoadState') != 'not-found':
            raise RuntimeError('Recovery service name is already in use')
        for program in ('systemctl','loginctl','greetd','qs','kwin_wayland','kscreen-doctor','dbus-run-session','python3'):
            if not shutil.which(program): raise RuntimeError('Missing dependency: ' + program)
        # Fixed Plasma allowlist and renderer dependencies, without starting UI.
        run('/usr/bin/python3', str(REPO/'apps/greeter/bin/kos-greeter-session'), '--check')
        run('/usr/bin/python3', '-c', 'import PIL')
        if not (self.root/'dev/tty3').is_char_device() or properties('getty@tty3.service').get('LoadState') != 'loaded':
            raise RuntimeError('Recovery tty3/getty is unavailable')
        return name, original

    def load(self):
        self.safe(self.state); regular(self.state/'state.json')
        data = json.loads((self.state/'state.json').read_text())
        if data.get('version') != 1 or not NAME.fullmatch(data.get('original','')):
            raise RuntimeError('Invalid installation snapshot')
        if data['original'] in ('greetd.service','display-manager.service','kos-greeter-recover.service'):
            raise RuntimeError('Invalid original manager in snapshot')
        if set(data['files']) != set(FILES): raise RuntimeError('Invalid backup paths')
        for relative in data['links']:
            if not relative.startswith('etc/systemd/system/') or '..' in Path(relative).parts:
                raise RuntimeError('Invalid backup link')
        return data

    def save(self, data): atomic(self.state/'state.json', json.dumps(data).encode(), 0o600)

    def current_files(self):
        return {relative: hashlib.sha256(read_regular(self.root/relative)).hexdigest()
                if (self.root/relative).exists() else None for relative in FILES}

    def verify_receipt(self, data):
        if data.get('phase') == 'installed':
            if self.current_files() != data.get('installed_files') or self.links(data['original']) != data.get('installed_links'):
                raise RuntimeError('Managed config/service links changed after installation; snapshot retained')

    def installed_check(self, app=None):
        app = self.app if app is None else app
        account = pwd.getpwnam('greeter')
        run('/usr/bin/python3', str(app/'bin/kos-greeter-session'), '--check',
            user=account.pw_uid, group=account.pw_gid, extra_groups=[])
        files = self.runtime_files(app)
        try:
            run('/usr/bin/python3', '-c',
                'import os,sys;bad=[p for p in sys.argv[1:] if not os.access(p,os.R_OK)];'
                'sys.stderr.write("Unreadable Greeter runtime files: " + ", ".join(bad[:12]) if bad else "");'
                'sys.exit(bool(bad))',
                *files, user=account.pw_uid, group=account.pw_gid, extra_groups=[])
        except subprocess.CalledProcessError as error:
            raise RuntimeError(error.stderr.strip() or 'Greeter runtime readability check failed') from error

    def runtime_files(self, app=None):
        app = self.app if app is None else app
        files = []
        for path in app.rglob('*'):
            if not path.is_file(): continue
            parts = path.relative_to(app).parts
            # Store's publisher-only lock stays private (0600). Read-only
            # consumers never acquire it; manifest/images remain mandatory.
            if len(parts) == 3 and parts[0] == 'public-display' and parts[1].isdecimal() and parts[2] == '.lock':
                continue
            files.append(str(path))
        return files

    def publish(self, bundle, manifest):
        caller = int(os.environ.get('SUDO_UID','-1'))
        if caller <= 0: raise RuntimeError('Publish/revoke using sudo from the requesting account')
        spec = importlib.util.spec_from_file_location('installed_resources',self.app/'companion/resources.py')
        resources=importlib.util.module_from_spec(spec);spec.loader.exec_module(resources)
        store = resources.Store(self.app/'public-display')
        if 'wallpaper.json' not in manifest:
            store.revoke(caller)
            print('No current consent/image: previous public copy revoked for your account.')
            return
        values = {}
        for relative in ('wallpaper.json','wallpaper.png'):
            raw = read_regular(bundle/relative)
            if hashlib.sha256(raw).hexdigest()!=manifest[relative]['hash']:
                raise RuntimeError('Wallpaper bundle changed')
            values[relative] = raw
        meta = json.loads(values['wallpaper.json'])
        if set(meta) != {'uid','fit'} or meta['uid'] != caller or meta['fit'] not in ('crop','fit','stretch','center'):
            raise RuntimeError('Wallpaper consent must belong to the sudo caller')
        store.publish(caller,values['wallpaper.png'],consent=True,notice=resources.NOTICE,fit=meta['fit'])
        atomic(self.app/'config/wallpaper.json',json.dumps(dict(schemaVersion=1,defaultUid=caller)).encode())
        print('Public wallpaper refreshed (24-hour expiry; --refresh-wallpaper renews or revokes from current consent).')

    @public_umask
    def refresh(self, bundle, sync=True):
        self.recover_upgrade()
        data = self.load(); self.verify_receipt(data)
        if data.get('phase') != 'installed': raise RuntimeError('Complete installation/rollback before refreshing')
        manifest = self.validate_bundle(bundle)
        if not sync: manifest = {k:v for k,v in manifest.items() if k not in ('wallpaper.json','wallpaper.png')}
        self.publish(bundle, manifest)

    def owned_sessions(self, data):
        same_boot = data.get('boot_id') == (self.root/'proc/sys/kernel/random/boot_id').read_text().strip()
        old = {row.split()[0] for row in data['sessions'] if row.split()} if same_boot else set()
        result = []
        for row in run('/usr/bin/loginctl','list-sessions','--no-legend','--no-pager').stdout.splitlines():
            fields = row.split()
            if not fields or fields[0] in old: continue
            sid = fields[0]
            if not re.fullmatch(r'[A-Za-z0-9_.-]+',sid): raise RuntimeError('Invalid logind session')
            service = run('/usr/bin/loginctl','show-session',sid,'-p','Service','--value',check=False).stdout.strip()
            if service in ('greetd','greetd-greeter'): result.append(sid)
        return result

    def reload_user(self, data):
        uid = data.get('caller_uid', -1)
        if uid <= 0 or properties('user@'+str(uid)+'.service').get('ActiveState') != 'active': return
        account = pwd.getpwuid(uid)
        # Reload only the caller's manager; do not import tokens/environment,
        # restart its current Shell, or change another account's manager.
        run('/usr/bin/systemctl','--user','daemon-reload',
            user=uid, group=account.pw_gid, extra_groups=[],
            env={'XDG_RUNTIME_DIR':'/run/user/'+str(uid),
                 'DBUS_SESSION_BUS_ADDRESS':'unix:path=/run/user/'+str(uid)+'/bus'})

    def recover_policy(self):
        journal = self.state/'policy-update.json'
        if not journal.exists(): return
        self.safe(journal)
        record = json.loads(read_regular(journal, 128*1024))
        previous = record['state']; data = self.load()
        path = self.root/FILES[1]
        old = bytes.fromhex(record['before'])
        if hashlib.sha256(old).hexdigest() != previous['installed_files'][FILES[1]]:
            raise RuntimeError('Invalid policy migration backup')
        current = self.current_files()
        allowed = dict(previous['installed_files']); allowed[FILES[1]] = record['after']
        if current not in (previous['installed_files'], allowed):
            raise RuntimeError('Managed files changed during policy migration; backup retained')
        committed = data.get('phase') == 'installed' and data.get('installed_files') == allowed
        if not committed:
            atomic(path, old)
            systemctl('daemon-reload')
            self.save(previous)
        journal.unlink()

    def ensure_policy(self):
        # Separate transaction after app upgrade; old rollback implementations
        # skip receipt checks for an in-progress phase and retain original files.
        self.recover_policy()
        data = self.load(); self.verify_receipt(data)
        path = self.root/FILES[1]
        old = read_regular(path, 4096)
        if old == GREETER_POLICY: return
        journal = self.state/'policy-update.json'
        record = dict(state=data, before=old.hex(), after=hashlib.sha256(GREETER_POLICY).hexdigest())
        atomic(journal, json.dumps(record).encode(), 0o600)
        try:
            self.save(dict(data, phase='policy-updating'))
            atomic(path, GREETER_POLICY)
            systemctl('daemon-reload')
            self.save(dict(data, installed_files=self.current_files()))
        except BaseException:
            self.recover_policy()
            raise
        journal.unlink()
        print('Migrated bounded daemon recovery policy; no service restarted.')

    def exchange_apps(self, stage):
        # Linux atomic directory exchange: readers never see a missing app path.
        libc = ctypes.CDLL(None, use_errno=True)
        rename = libc.renameat2
        rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        rename.restype = ctypes.c_int
        if rename(-100, os.fsencode(self.app), -100, os.fsencode(stage), 2):
            number = ctypes.get_errno()
            raise OSError(number, os.strerror(number))
        for parent in (self.app.parent, stage.parent):
            fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY)
            try: os.fsync(fd)
            finally: os.close(fd)

    def recover_upgrade(self):
        journal = self.state/'upgrade.json'
        stage = self.state/'upgrade-app'
        if not journal.exists():
            if stage.exists(): self.safe(stage); shutil.rmtree(stage)
            return
        self.safe(journal); regular(journal)
        record = json.loads(read_regular(journal))
        data = self.load(); self.verify_receipt(data)
        self.safe(self.app); self.safe(stage)
        committed = data.get('upgradeId') == record['id']
        if not committed:
            inode = self.app.stat().st_ino
            if inode == record['new_inode']:
                if stage.stat().st_ino != record['old_inode']: raise RuntimeError('Upgrade backup identity changed')
                self.exchange_apps(stage)
            elif inode != record['old_inode']:
                raise RuntimeError('Installed app identity changed; upgrade snapshot retained')
        if stage.exists(): shutil.rmtree(stage)
        journal.unlink()
        print('Completed pending upgrade cleanup.' if committed else 'Restored previous app after interrupted upgrade.')

    @public_umask
    def upgrade(self, bundle, manifest, digest, data, sync=True):
        self.verify_receipt(data)
        if (self.root/'run/kos-greeter-test').exists(): raise RuntimeError('Temporary test is active')
        self.safe(self.app)
        # Keep staging private; rename exchange requires a shared filesystem.
        if self.app.stat().st_dev != self.state.stat().st_dev:
            raise RuntimeError('App and recovery snapshot must be on the same filesystem for atomic upgrade')
        stage = self.state/'upgrade-app'; journal = self.state/'upgrade.json'
        if stage.exists() or journal.exists(): raise RuntimeError('Pending upgrade must be recovered first')
        try:
            stage.mkdir(mode=0o755)
            for relative, record in manifest.items():
                if not relative.startswith('app/'): continue
                if relative.startswith('app/public-display/') or relative == 'app/config/wallpaper.json':
                    raise RuntimeError('Bundle cannot override published display state')
                raw = read_regular(bundle/relative)
                if hashlib.sha256(raw).hexdigest() != record['hash']: raise RuntimeError('Bundle changed during upgrade')
                atomic(stage/relative[4:], raw, record['mode'])
            for directory, _, _ in os.walk(stage): Path(directory).chmod(0o755)
            # Published data belongs to all accounts; carry it across, never
            # republish from the invoking account without fresh consent.
            public = self.app/'public-display'
            if public.exists():
                for path in (public, *public.rglob('*')): self.safe(path)
                shutil.copytree(public, stage/'public-display')
            selection = self.app/'config/wallpaper.json'
            if selection.exists():
                self.safe(selection); atomic(stage/'config/wallpaper.json', read_regular(selection))
            # Validate the public installed path; failure exchanges the old app back.
            record = dict(id=uuid.uuid4().hex, old_inode=self.app.stat().st_ino, new_inode=stage.stat().st_ino)
            atomic(journal, json.dumps(record).encode(), 0o600)
            self.exchange_apps(stage)
            effective = manifest if sync else {k:v for k,v in manifest.items() if k not in ('wallpaper.json','wallpaper.png')}
            self.publish(bundle, effective)
            self.installed_check()
            updated = dict(data, digest=digest, sync=sync, upgradeId=record['id'])
            self.save(updated)
        except BaseException:
            if journal.exists(): self.recover_upgrade()
            elif stage.exists(): shutil.rmtree(stage)
            raise
        self.recover_upgrade()
        print('Updated from local source. Service state unchanged; new app is used on the next login.')

    @public_umask
    def install(self, bundle, enable=True, now=False, sync=True):
        require_caller_shell()
        manifest = self.validate_bundle(bundle)
        digest = hashlib.sha256(json.dumps(manifest,sort_keys=True).encode()).hexdigest()
        if self.state.exists():
            self.recover_policy()
            data = self.load()
            if data.get('phase') != 'installed': raise RuntimeError('Complete pending rollback before updating')
            self.recover_upgrade(); data = self.load()
            if now: raise RuntimeError('Existing installation updates without restarting; omit --activate-now')
            if not enable and data.get('enabled'):
                raise RuntimeError('--files-only cannot change an existing boot selection')
            if data.get('phase') == 'installed' and data.get('digest') == digest and data.get('sync') == sync:
                self.verify_receipt(data)
                self.ensure_policy()
                print('Identical installation already present; original recovery snapshot preserved.'); return
            self.upgrade(bundle, manifest, digest, data, sync)
            self.ensure_policy()
            return
        original, props = self.preflight()
        if now: recovery_tty(1)
        data = dict(version=1, original=original, original_active=props.get('ActiveState')=='active',
                    links=self.links(original), files={}, digest=digest, enabled=enable, sync=sync, phase='preparing',
                    getty_active=properties('getty@tty1.service').get('ActiveState') == 'active',
                    caller_uid=int(os.environ.get('SUDO_UID','-1')),
                    boot_id=(self.root/'proc/sys/kernel/random/boot_id').read_text().strip(),
                    sessions=run('/usr/bin/loginctl','list-sessions','--no-legend','--no-pager').stdout.splitlines())
        directories = set()
        for path in [self.root/f for f in FILES] + [self.app / f[4:] for f in manifest if f.startswith('app/')]:
            for parent in path.parents:
                if parent == self.root: break
                if not parent.exists(): directories.add(str(parent.relative_to(self.root)))
        data['created_dirs'] = sorted(directories, key=lambda p: len(Path(p).parts), reverse=True)
        self.state.parent.mkdir(parents=True, exist_ok=True)
        stage = Path(tempfile.mkdtemp(prefix='.kos-greeter-snapshot-', dir=self.state.parent))
        try:
            for relative in FILES:
                path = self.root/relative
                if path.exists() or path.is_symlink():
                    info = regular(path); self.safe(path)
                    atomic(stage/'backup'/relative, read_regular(path), 0o600)
                    data['files'][relative] = stat.S_IMODE(info.st_mode)
                else: data['files'][relative] = None
            atomic(stage/'state.json',json.dumps(data).encode(),0o600)
            atomic(stage/'rollback.py',Path(__file__).read_bytes(),0o700)
            os.replace(stage,self.state)
            directory = os.open(self.state.parent, os.O_RDONLY | os.O_DIRECTORY)
            try: os.fsync(directory)
            finally: os.close(directory)
        finally:
            if stage.exists(): shutil.rmtree(stage)
        try:
            self.app.mkdir(parents=True,mode=0o755)
            # Do not inherit a restrictive sudo caller umask on runtime paths.
            for parent in (self.app,*self.app.parents):
                if parent == self.root/'usr/local/lib' or parent == self.root: break
                parent.chmod(0o755)
            for relative, record in manifest.items():
                if not relative.startswith('app/'): continue
                raw = read_regular(bundle/relative)
                if hashlib.sha256(raw).hexdigest()!=record['hash']: raise RuntimeError('Bundle changed during installation')
                atomic(self.app/relative[4:], raw, record['mode'])
            for directory, dirs, _ in os.walk(self.app):
                Path(directory).chmod(0o755)
            # Root-owned public copy, only for the account with explicit consent.
            if sync and 'wallpaper.json' in manifest:
                self.publish(bundle, manifest)
            self.installed_check()
            root_app='/'+APP_REL
            atomic(self.root/FILES[0], ('[terminal]\nvt = 1\nswitch = true\n[general]\nsource_profile = false\n[default_session]\ncommand = "'+root_app+'/bin/kos-greeter-session --installed-seat"\nuser = "greeter"\n').encode())
            atomic(self.root/FILES[1], GREETER_POLICY)
            atomic(self.root/FILES[2], ('[Unit]\nDescription=Restore the previous KOS display manager on Greeter failure\n[Service]\nType=oneshot\nExecStart=/usr/bin/python3 /'+STATE_REL+'/rollback.py --recover\nTimeoutStartSec=300\n').encode())
            atomic(self.root/FILES[3], ('[Service]\nEnvironment=KOS_GREETER_APP_DIR='+root_app+'\n').encode())
            atomic(self.root/FILES[4], Path(__file__).read_bytes(),0o755)
            systemctl('daemon-reload')
            self.reload_user(data)
            if enable:
                systemctl('disable',original)
                systemctl('enable','--force','greetd.service')
                if properties('display-manager.service').get('Id') != 'greetd.service': raise RuntimeError('Default display manager alias did not change')
            data['installed_files']=self.current_files();data['installed_links']=self.links(original)
            data['phase']='installed';self.save(data)
            if now:
                systemctl('stop',original);systemctl('start','greetd.service')
                if properties('greetd.service').get('ActiveState')!='active': raise RuntimeError('greetd failed to start')
        except BaseException:
            try: self.rollback(recover=now)
            except BaseException as error: print('Automatic restoration failed; snapshot retained: '+str(error),file=sys.stderr)
            raise
        print('Installed. '+('greetd is active.' if now else 'greetd is the boot default; reboot when ready.' if enable else 'Service enablement unchanged.'))
        print('Rollback: sudo python3 /'+STATE_REL+'/rollback.py --rollback')

    @public_umask
    def rollback(self, recover=False):
        self.recover_policy()
        if not self.state.exists(): print('No persistent Greeter installation to roll back.'); return
        self.recover_upgrade()
        data=self.load()
        self.verify_receipt(data)
        data['phase']='rolling-back';self.save(data)
        active=properties('greetd.service').get('ActiveState')=='active'
        if active: systemctl('stop','greetd.service')
        for sid in self.owned_sessions(data): run('/usr/bin/loginctl','terminate-session',sid)
        systemctl('disable','greetd.service')
        # Recreate exact old alias/wants links, not merely guessed enablement.
        for relative,target in self.links(data['original']).items():
            path=self.root/relative
            if os.readlink(path)!=target: raise RuntimeError('Concurrent service link change')
            path.unlink()
        for relative,target in data['links'].items():
            path=self.root/relative;self.safe(path.parent);path.parent.mkdir(parents=True,exist_ok=True)
            if path.exists() or path.is_symlink(): raise RuntimeError('Backup link now occupied: '+relative)
            path.symlink_to(target)
        for relative,mode in data['files'].items():
            path=self.root/relative;self.safe(path.parent)
            if path.is_symlink(): raise RuntimeError('Managed file changed to symlink')
            if mode is None: path.unlink(missing_ok=True)
            else: atomic(path,(self.state/'backup'/relative).read_bytes(),mode)
        systemctl('daemon-reload')
        self.reload_user(data)
        if data['original_active'] or active or recover:
            systemctl('start',data['original'])
            if properties(data['original']).get('ActiveState')!='active': raise RuntimeError('Original manager not active; snapshot retained')
        if data.get('getty_active'): systemctl('start','getty@tty1.service')
        if self.app.exists(): self.safe(self.app);shutil.rmtree(self.app)
        for relative in data.get('created_dirs',[]):
            path = self.root/relative
            try: path.rmdir()
            except FileNotFoundError: pass
            except OSError as error:
                if error.errno not in (39, 17): raise  # Preserve nonempty directories.
        shutil.rmtree(self.state)
        print('Restored previous manager, boot aliases and config; installed Greeter removed.')


def recovery_tty(vt):
    if not os.isatty(0): raise RuntimeError('Immediate switching requires an interactive text TTY')
    actual=os.ttyname(0); tty=os.environ.get('SUDO_TTY','') if actual.startswith('/dev/pts/') and os.environ.get('SUDO_UID','').isdigit() else actual
    if not re.fullmatch(r'/dev/tty(?:[1-9]|1[0-2])',tty) or tty=='/dev/tty'+str(vt) or os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY'):
        raise RuntimeError('Switch from a recovery text TTY other than tty'+str(vt))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    action=parser.add_mutually_exclusive_group(required=True)
    action.add_argument('--build',type=Path,metavar='DIRECTORY')
    action.add_argument('--install',type=Path,metavar='BUNDLE')
    action.add_argument('--rollback',action='store_true')
    action.add_argument('--recover',action='store_true',help=argparse.SUPPRESS)
    action.add_argument('--check',action='store_true')
    action.add_argument('--status',action='store_true')
    action.add_argument('--refresh-wallpaper',type=Path,metavar='BUNDLE')
    parser.add_argument('--no-wallpaper-sync',action='store_true')
    parser.add_argument('--files-only',action='store_true',help='install payload/config without changing boot service enablement')
    parser.add_argument('--activate-now',action='store_true',help='from text TTY: end current desktop and switch immediately')
    args=parser.parse_args()
    if args.build: build(args.build,not args.no_wallpaper_sync);return
    if os.geteuid()!=0: parser.error('Use sudo for install/check/status/rollback')
    installer=Installer()
    if args.check:
        require_caller_shell()
        if installer.state.exists():
            data=installer.load(); installer.verify_receipt(data)
            if data.get('phase') != 'installed': raise RuntimeError('Complete pending rollback first')
            print('Existing installation detected; local-source update available (boot selection preserved).')
        else: installer.preflight();print('Read-only preflight passed.')
        return
    if args.status:
        if installer.state.exists():
            data=installer.load();print('Phase:',data['phase'],'Original:',data['original'],'Boot switch:',data['enabled'])
        else: print('No persistent Greeter installation.')
        return
    if args.activate_now and (not args.install or args.files_only): parser.error('--activate-now requires installation with boot activation')
    fd=installer.lock()
    try:
        if args.rollback and installer.state.exists():
            if properties('greetd.service').get('ActiveState')=='active' or installer.owned_sessions(installer.load()):
                recovery_tty(1)
        if args.install: installer.install(args.install,not args.files_only,args.activate_now,not args.no_wallpaper_sync)
        elif args.refresh_wallpaper: installer.refresh(args.refresh_wallpaper,not args.no_wallpaper_sync)
        else: installer.rollback(args.recover)
    finally: os.close(fd)

if __name__=='__main__':
    try: main()
    except (OSError,ValueError,KeyError,RuntimeError,subprocess.SubprocessError) as error:
        print('Greeter install/rollback refused or failed: '+str(error),file=sys.stderr);sys.exit(1)
