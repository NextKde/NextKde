#!/usr/bin/env python3
"""Temporarily replace the running display manager, with timed rollback."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import subprocess
import sys

MODULE = Path(__file__).with_name('rollback-greeter.py')
spec = importlib.util.spec_from_file_location('greeter_recovery', MODULE)
recovery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recovery)
APP = Path(__file__).resolve().parents[1] / 'apps/greeter'
FILES = ('qml/LoadingSpinner.qml', 'qml/GlassFieldBackground.qml', 'qml/GaussianGlass.qml', 'shell.qml', 'wallpaper.qml', 'qml/Lifecycle.js', 'qml/WallpaperHost.qml',
         'qml/WallpaperSource.qml', 'qml/WallpaperWindows.qml', 'companion/accounts.py',
         'companion/outputs.py', 'companion/display.py', 'companion/resources.py',
         'companion/wallpaper.py', 'companion/kos_wallpaper.py', 'companion/theme.py', 'companion/theme-files.json',
         'config/outputs.json', 'bin/kos-greeter-ui', 'bin/kos-greeter-session',
         'bin/kos-greeter-outputs', 'bin/kos-greeter-wallpaper',
         'companion/handoff.py', 'companion/greeter_config.py', 'companion/session_output.py', 'companion/plasma_session.py', 'bin/kos-user-session', 'cover.qml', 'companion/cover.py')
SHARED = APP.parents[1] / 'shared/qml/wallpapers'
GREETD_EXECUTABLE = next((path for path in ('/usr/bin/greetd', '/usr/sbin/greetd')
                         if os.access(path, os.X_OK)), '/usr/bin/greetd')


def wallpaper_files():
    # The sole intentional source link is resolved to the known shared bundle.
    if (APP / 'wallpapers').resolve(strict=True) != SHARED.resolve(strict=True):
        raise RuntimeError('Unexpected shared wallpaper bundle')
    files = ['qmldir', 'StaticWallpaperImage.qml', 'ThemeWallpaperScene.qml', 'ThemeWallpaperThumbnail.qml']
    expected = json.loads((APP / 'companion/theme-files.json').read_text())
    for theme, entries in expected.items():
        if theme not in ('starfield', 'blackhole', 'weather', 'forest', 'underwater'):
            raise RuntimeError('Unknown built-in theme')
        for relative in entries:
            path = Path(relative)
            if path.is_absolute() or '..' in path.parts:
                raise RuntimeError('Invalid shared resource path')
            files.append('themes/' + theme + '/' + relative)
    import hashlib
    for relative in files:
        source = SHARED / relative
        if any(parent.is_symlink() for parent in (source, *source.parents) if parent != SHARED.parent):
            raise RuntimeError('Symlinked shared source: ' + str(source))
        if not source.is_file():
            raise RuntimeError('Missing shared wallpaper source: ' + str(source))
        parts = Path(relative).parts
        if parts[0] == 'themes' and hashlib.sha256(source.read_bytes()).hexdigest() != expected[parts[1]]['/'.join(parts[2:])]:
            raise RuntimeError('Changed trusted theme resource: ' + relative)
    return files


def preview_wallpaper(path):
    # Read user-selected content with the sudo caller's credentials, not root's.
    uid = os.getuid()
    if os.geteuid() == 0 and os.environ.get('SUDO_UID', '').isdecimal():
        uid = int(os.environ['SUDO_UID'])
    kwargs = {}
    if os.geteuid() == 0 and uid != 0:
        account = pwd.getpwuid(uid)
        kwargs = dict(user=uid, group=account.pw_gid, extra_groups=[])
    code = '''import os,stat,sys
fd=os.open(sys.argv[1],os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
with os.fdopen(fd,'rb') as stream:
 info=os.fstat(stream.fileno())
 if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= 16*1024*1024:
  raise ValueError('wallpaper byte budget/type')
 sys.stdout.buffer.write(stream.read(16*1024*1024+1))
'''
    result = subprocess.run(['/usr/bin/python3', '-c', code, str(Path(path).absolute())],
                            capture_output=True, timeout=15, **kwargs)
    if result.returncode:
        raise RuntimeError('Cannot read selected wallpaper as the requesting account')
    resource_spec = importlib.util.spec_from_file_location('preview_resources', APP / 'companion/resources.py')
    resources = importlib.util.module_from_spec(resource_spec)
    try:
        resource_spec.loader.exec_module(resources)
    except ImportError as error:
        raise RuntimeError('Pillow is required for --wallpaper') from error
    try:
        return resources.image_copy(result.stdout)[0]
    except (OSError, ValueError, resources.Image.DecompressionBombError, resources.Image.DecompressionBombWarning) as error:
        raise RuntimeError('Selected wallpaper must be a valid bounded static PNG/JPEG') from error



def kos_wallpaper():
    uid = os.getuid()
    if os.geteuid() == 0:
        if not os.environ.get('SUDO_UID', '').isdecimal() or int(os.environ['SUDO_UID']) == 0:
            raise RuntimeError('Run using sudo from your own account to select its KOS wallpaper')
        uid = int(os.environ['SUDO_UID'])
    account = pwd.getpwuid(uid)
    state_home = os.environ.get('XDG_STATE_HOME', str(Path(account.pw_dir) / '.local/state'))
    kwargs = dict(user=uid, group=account.pw_gid, extra_groups=[]) if os.geteuid() == 0 else {}
    result = subprocess.run(['/usr/bin/python3', str(APP / 'companion/kos_wallpaper.py'), state_home],
                            capture_output=True, text=True, timeout=20, **kwargs)
    if result.returncode:
        raise RuntimeError('Cannot read your current KOS wallpaper: ' + result.stderr.strip())
    value = json.loads(result.stdout)
    if value == {'schemaVersion': 1, 'enabled': False}:
        return None
    import base64
    if set(value) != {'schemaVersion', 'fit', 'image', 'size'} or value['schemaVersion'] != 1 or value['fit'] not in ('crop', 'fit', 'stretch', 'center'):
        raise RuntimeError('Invalid KOS wallpaper response')
    return uid, base64.b64decode(value['image'], validate=True), value['fit']


def revoke_temporary_wallpaper(uid):
    app = recovery.STATE / 'app'
    recovery.trusted(recovery.STATE, directory=True)
    recovery.trusted(app, directory=True)
    recovery.trusted(app / 'config', directory=True)
    if not (app / 'config/wallpaper.json').exists():
        return False
    recovery.trusted(app / 'config/wallpaper.json')
    metadata = json.loads((app / 'config/wallpaper.json').read_text())
    if set(metadata) != {'schemaVersion', 'defaultUid'} or type(metadata['schemaVersion']) is not int or metadata['schemaVersion'] != 1 or type(metadata['defaultUid']) is not int:
        raise RuntimeError('Invalid temporary wallpaper metadata')
    if metadata['defaultUid'] != uid:
        return False
    spec = importlib.util.spec_from_file_location('revoke_resources', APP / 'companion/resources.py')
    resources = importlib.util.module_from_spec(spec); spec.loader.exec_module(resources)
    resources.Store(app / 'public-display').revoke(uid)
    return True


def revoke_wallpaper():
    if os.geteuid() != 0 or not os.environ.get('SUDO_UID', '').isdecimal() or int(os.environ['SUDO_UID']) == 0:
        raise RuntimeError('Use sudo from the account whose wallpaper you want to revoke')
    uid = int(os.environ['SUDO_UID'])
    account = pwd.getpwuid(uid)
    state_home = os.environ.get('XDG_STATE_HOME', str(Path(account.pw_dir) / '.local/state'))
    fd = recovery.lock()
    try:
        if recovery.STATE.exists(): revoke_temporary_wallpaper(uid)
        result = subprocess.run(['/usr/bin/python3', str(APP / 'companion/kos_wallpaper.py'), '--disable', state_home],
                                user=uid, group=account.pw_gid, extra_groups=[], capture_output=True, text=True, timeout=15)
        if result.returncode:
            raise RuntimeError('Temporary publication revoked, but could not disable the account preference')
    finally:
        if not recovery.STATE.exists(): recovery.LOCK.unlink(missing_ok=True)
        os.close(fd)
    print('KOS login wallpaper sync disabled; active temporary consumers will use the default background.')


def preflight(vt):
    if not Path('/run/systemd/system').is_dir():
        raise RuntimeError('A running systemd system manager is required')
    for program in ('/usr/bin/systemctl', '/usr/bin/systemd-run', '/usr/bin/loginctl', '/usr/bin/python3', '/usr/bin/busctl'):
        if not os.access(program, os.X_OK):
            raise RuntimeError('Missing executable: ' + program)
    for relative in FILES:
        source = APP / relative
        if source.is_symlink() or not source.is_file():
            raise RuntimeError('Missing or symlinked app source: ' + str(source))
    wallpaper_files()
    recovery.run('/usr/bin/python3', str(APP / 'bin/kos-greeter-session'), '--check')
    if not Path('/etc/pam.d/greetd').is_file():
        raise RuntimeError('Distribution greetd PAM configuration is required; this script does not create it')
    user = pwd.getpwnam('greeter')
    if user.pw_uid == 0:
        raise RuntimeError('Greeter account must not be root')
    original = recovery.properties('display-manager.service')
    name = original.get('Id', '')
    if not re.fullmatch(r'[A-Za-z0-9_.@-]+\.service', name) or name in (recovery.TEST, recovery.GUARD, recovery.SWITCH, 'greetd.service', 'display-manager.service'):
        raise RuntimeError('Unsupported original display manager')
    if original.get('ActiveState') != 'active':
        raise RuntimeError('Original display manager must be active before testing')
    if recovery.properties('greetd.service').get('ActiveState') not in ('inactive', 'failed'):
        raise RuntimeError('An existing greetd daemon is running')
    if original.get('UnitFileState') not in ('enabled', 'enabled-runtime', 'disabled', 'static', 'indirect'):
        raise RuntimeError('Unsupported original enablement state')
    # A runtime mask cannot override a persistent local unit of the same name.
    for path in (Path('/etc/systemd/system') / name, recovery.UNIT_DIR / name):
        if path.exists() or path.is_symlink():
            raise RuntimeError('Existing local unit prevents a reversible runtime mask: ' + str(path))
    for unit in (recovery.TEST, recovery.GUARD, recovery.TIMER, recovery.SWITCH):
        if recovery.properties(unit).get('LoadState') != 'not-found':
            raise RuntimeError('Reserved test unit already exists: ' + unit)
        for base in (Path('/etc/systemd/system'), recovery.UNIT_DIR):
            path = base / unit
            if path.exists() or path.is_symlink():
                raise RuntimeError('Reserved test file already exists: ' + str(path))
    if recovery.STATE.exists() or recovery.STATE.is_symlink():
        raise RuntimeError('A previous test snapshot exists; run rollback-greeter.py first')
    getty = recovery.properties('getty@tty' + str(vt) + '.service')
    return {'version': 1, 'original': name, 'original_enabled': original['UnitFileState'],
            'vt': vt, 'getty_active': getty.get('ActiveState') == 'active', 'sessions': recovery.sessions()}


def write(path, content, mode=0o644):
    # Never replace an unexpected file or follow symlinks.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
    os.fchmod(fd, mode)
    info = os.fstat(fd)
    try:
        with os.fdopen(fd, 'wb' if isinstance(content, bytes) else 'w') as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
    except BaseException:
        if path.exists() and path.lstat().st_ino == info.st_ino:
            path.unlink()
        raise


def prepare(data, wallpaper=None, kos=None):
    bundle_files = wallpaper_files()
    state = recovery.STATE
    state.mkdir(mode=0o755)
    state.chmod(0o755)
    try:
        (state / 'private').mkdir(mode=0o700)
        (state / 'private').chmod(0o700)
        # Recovery is saved before any systemd or display manager mutation.
        write(state / 'private/state.json', json.dumps(data), 0o600)
    except BaseException:
        shutil.rmtree(state)
        raise
    for source, destination in ((MODULE, state / 'private/rollback-greeter.py'), (Path(__file__), state / 'private/test-greeter.py')):
        write(destination, source.read_text(), 0o700)
    for relative in ('app', 'app/qml', 'app/companion', 'app/config', 'app/bin'):
        directory = state / relative
        directory.mkdir(mode=0o755)
        directory.chmod(0o755)
    for relative in FILES:
        destination = state / 'app' / relative
        content = (APP / relative).read_text()
        if relative == 'shell.qml' and wallpaper is not None:
            original = 'Greeter.WallpaperSource { id: wallpaperSource; uid: root.selectedUid; frozen: ["ReadyToLaunch", "Exiting", "LaunchRequested"].includes(root.phase) }'
            if content.count(original) != 1:
                raise RuntimeError('Preview adapter no longer matches the authentication frontend')
            content = content.replace(original, 'QtObject { id: wallpaperSource; readonly property bool ready: true; readonly property var state: ({source: Qt.resolvedUrl("config/preview-wallpaper.png"), fit: "crop", version: "temporary-preview"}) }')
        write(destination, content, 0o755 if relative.startswith('bin/') else 0o644)
    for relative in bundle_files:
        destination = state / 'app/wallpapers' / relative
        # Newly-created snapshot only; no directory links to the user checkout.
        destination.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
        for parent in (destination.parent, *destination.parent.parents):
            if parent == state / 'app': break
            parent.chmod(0o755)
        write(destination, (SHARED / relative).read_bytes())
    if wallpaper is not None:
        write(state / 'app/config/preview-wallpaper.png', wallpaper)

    if kos is not None:
        uid, image, fit = kos
        resource_spec = importlib.util.spec_from_file_location('publish_resources', APP / 'companion/resources.py')
        resources = importlib.util.module_from_spec(resource_spec); resource_spec.loader.exec_module(resources)
        store = resources.Store(state / 'app/public-display')
        store.publish(uid, image, consent=True, notice=resources.NOTICE, fit=fit)
        write(state / 'app/config/wallpaper.json', json.dumps(dict(schemaVersion=1, defaultUid=uid)))

    write(state / 'config.toml' , '[terminal]\nvt = ' + str(data['vt']) + '\nswitch = true\n[general]\nsource_profile = false\n[default_session]\ncommand = "/usr/bin/python3 /run/kos-greeter-test/app/bin/kos-greeter-session --temporary-seat"\nuser = "greeter"\n')
    # --timeout 0 (or --no-auto-rollback) disables the deadline entirely:
    # no timer unit and no OnFailure guard, so only a manual rollback or a
    # reboot (which clears /run units and the runtime mask) can restore.
    failure = ''
    if data['seconds'] > 0:
        control = '/usr/bin/python3 /run/kos-greeter-test/private/rollback-greeter.py --auto'
        write(recovery.UNIT_DIR / recovery.GUARD, '[Unit]\nDescription=KOS Greeter test rollback\nStartLimitIntervalSec=0\n[Service]\nType=oneshot\nExecStart=' + control + '\nTimeoutStartSec=1200\n')
        write(recovery.UNIT_DIR / recovery.TIMER, '[Unit]\nDescription=KOS Greeter test deadline\n[Timer]\nOnActiveSec=' + str(data['seconds']) + 's\nAccuracySec=1s\nUnit=' + recovery.GUARD + '\n')
        failure = 'OnFailure=' + recovery.GUARD + '\n'
    write(recovery.UNIT_DIR / recovery.TEST, '[Unit]\nDescription=Temporary KOS Greeter test\nAfter=systemd-user-sessions.service systemd-logind.service getty@tty' + str(data['vt']) + '.service\nConflicts=' + data['original'] + ' getty@tty' + str(data['vt']) + '.service\n' + failure + '[Service]\nType=simple\nExecStart=' + GREETD_EXECUTABLE + ' --config /run/kos-greeter-test/config.toml\nRestart=no\nTimeoutStopSec=30\nKillMode=control-group\nSendSIGHUP=yes\nIgnoreSIGPIPE=no\nKeyringMode=shared\nStandardOutput=null\nStandardError=null\n')


def apply():
    if Path(__file__).resolve() != recovery.STATE / 'private/test-greeter.py':
        raise RuntimeError('Internal switch must run from the root-owned recovery snapshot')
    recovery.trusted(Path(__file__))
    fd = recovery.lock()
    try:
        data = recovery.snapshot()
        if data['seconds'] > 0 and recovery.properties(recovery.TIMER).get('ActiveState') != 'active':
            raise RuntimeError('Automatic rollback timer is not active; refusing switch')
        recovery.systemctl('stop', data['original'])
        recovery.systemctl('mask', '--runtime', data['original'])
        recovery.systemctl('daemon-reload')
        if recovery.properties(data['original']).get('LoadState') != 'masked':
            raise RuntimeError('Runtime mask did not take effect')
        recovery.systemctl('start', recovery.TEST)
        if recovery.properties(recovery.TEST).get('ActiveState') != 'active':
            raise RuntimeError('Greeter test service did not start')
    except BaseException:
        recovery.restore()
        raise
    finally:
        if not recovery.STATE.exists():
            recovery.LOCK.unlink(missing_ok=True)
        os.close(fd)



def recovery_tty(vt):
    # sudo use_pty wraps the original console in /dev/pts/N. SUDO_TTY is
    # populated by sudo with the invoking terminal (see installed sudo(8)).
    if not os.isatty(0):
        raise RuntimeError('Interactive stdin is required; pipes are not a recovery TTY')
    actual = os.ttyname(0)
    tty = actual
    sudo_tty = os.environ.get('SUDO_TTY', '')
    if re.fullmatch(r'/dev/pts/[0-9]+', actual) and os.environ.get('SUDO_UID', '').isdecimal():
        tty = sudo_tty
    match = re.fullmatch(r'/dev/tty([1-9][0-9]*)', tty)
    if not match or int(match.group(1)) == vt or os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY'):
        raise RuntimeError('Use a text TTY different from test VT ' + str(vt)
                           + '; stdin=' + actual + ', sudo origin=' + (sudo_tty or '(none)'))
    return tty


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--start', action='store_true', help='switch from a text TTY; ends the current desktop')
    parser.add_argument('--check', action='store_true', help='read-only preflight (default)')
    parser.add_argument('--timeout', type=int, default=600, help='automatic rollback in seconds, 60–1800, or 0 to disable (default 600)')
    parser.add_argument('--no-auto-rollback', action='store_true', help='same as --timeout 0: no timer, roll back manually or reboot')
    parser.add_argument('--vt', type=int, default=1, help='test VT, 1–12; must differ from your recovery TTY')
    parser.add_argument('--revoke-wallpaper', action='store_true', help='revoke your active temporary public copy and disable your account sync choice')
    parser.add_argument('--no-wallpaper-sync', action='store_true', help='do not publish your KOS wallpaper for this temporary test')
    parser.add_argument('--wallpaper', metavar='IMAGE', help='explicitly show this PNG/JPEG to everyone before authentication, only for this temporary test')
    parser.add_argument('--apply', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.apply:
        if os.geteuid() != 0:
            parser.error('Internal switch requires root')
        apply()
        return
    if args.revoke_wallpaper:
        if args.start or args.check or args.wallpaper:
            parser.error('Use --revoke-wallpaper alone')
        revoke_wallpaper()
        return
    if args.start and args.check:
        parser.error('Choose --start or --check')
    if args.no_auto_rollback:
        args.timeout = 0
    if not (args.timeout == 0 or 60 <= args.timeout <= 1800) or not 1 <= args.vt <= 12:
        parser.error('Invalid timeout or VT')
    if args.start:
        if os.geteuid() != 0:
            parser.error('Run --start with sudo from a text TTY')
        try:
            recovery_tty(args.vt)
        except RuntimeError as error:
            parser.error(str(error))
    wallpaper = preview_wallpaper(args.wallpaper) if args.wallpaper else None
    kos = None if args.wallpaper or args.no_wallpaper_sync else kos_wallpaper()
    if not args.start:
        data = preflight(args.vt)
        deadline = 'disabled (manual rollback only)' if args.timeout == 0 else str(args.timeout) + ' seconds'
        if kos is not None:
            print('Current KOS image and fit validated; your authorized public copy will be used before authentication.')
        if wallpaper is not None:
            print('Selected wallpaper validated; it will be visible to everyone before authentication during the test.')
        print('Read-only preflight passed. Original:', data['original'], '| test VT:', args.vt,
              '| automatic rollback:', deadline + '. No changes made.')
        return
    fd = recovery.lock()
    try:
        data = preflight(args.vt)
        data['seconds'] = args.timeout
        if kos is not None:
            print('Publishing your selected KOS wallpaper for this temporary login test; visible before authentication.', flush=True)
        if args.timeout == 0:
            print('WARNING: automatic rollback is disabled; the test runs until you roll back from this TTY.', flush=True)
        if wallpaper is not None:
            print('Selected image will be public before authentication for all accounts in this temporary test.', flush=True)
        print('Current desktop will end. Recovery command: sudo python3 /run/kos-greeter-test/private/rollback-greeter.py', flush=True)
        try:
            prepare(data, wallpaper, kos)
            recovery.systemctl('daemon-reload')
            if args.timeout > 0:
                recovery.systemctl('start', recovery.TIMER)
                if recovery.properties(recovery.TIMER).get('ActiveState') != 'active':
                    raise RuntimeError('Cannot arm the rollback timer')
            # Dispatch after closing the setup lock so the detached worker can acquire it.
        except BaseException:
            if (recovery.STATE / 'private/state.json').exists():
                recovery.restore()
            raise
    finally:
        if not recovery.STATE.exists():
            recovery.LOCK.unlink(missing_ok=True)
        os.close(fd)
    switch = ['/usr/bin/systemd-run', '--unit=kos-greeter-switch', '--collect', '--service-type=exec',
              '--property=TimeoutStartSec=300', '--property=RuntimeMaxSec=180']
    if args.timeout > 0:
        switch.append('--property=OnFailure=' + recovery.GUARD)
    switch.extend(['/usr/bin/python3', str(recovery.STATE / 'private/test-greeter.py'), '--apply'])
    try:
        recovery.run(*switch)
    except BaseException:
        fd = recovery.lock()
        try:
            recovery.restore()
        finally:
            os.close(fd)
        raise
    print('Detached switch scheduled. Automatic rollback remains active even after login.' if args.timeout > 0
          else 'Detached switch scheduled. Automatic rollback is disabled; roll back from this TTY (no deadline).')


if __name__ == '__main__':
    try:
        main()
    except (OSError, KeyError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print('Greeter test refused/failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
