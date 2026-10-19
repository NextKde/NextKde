"""Private KWin settings for the pre-authentication compositor only.

No desktop configuration is read or copied. Failure is closed: launching with
inherited/default desktop effects would reintroduce the shutdown crash path.
"""
import os
from pathlib import Path
import secrets
import stat

# Installed KWin 6.7 scripted effects are desktop transitions, not Greeter UI.
# Quickshell owns the Greeter transitions and its glass rendering.
DISABLED_EFFECTS = (
    'kos_bridge', 'dialogparent', 'dimscreen', 'eyeonscreen', 'fade',
    'fadedesktop', 'fadingpopups', 'frozenapp', 'fullscreen', 'login', 'logout',
    'maximize', 'scale', 'sessionquit', 'squash', 'translucency', 'windowaperture',
)
KWINRC = ('[Plugins]\n' + ''.join(name + 'Enabled=false\n' for name in DISABLED_EFFECTS)).encode()


def runtime_directory(environment):
    path = Path(environment.get('XDG_RUNTIME_DIR') or '/run/user/' + str(os.geteuid()))
    if not path.is_absolute() or '..' in path.parts:
        raise ValueError('Invalid Greeter runtime directory')
    # Walk by directory descriptors; no path component may follow a symlink.
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for component in path.parts[1:]:
            next_fd = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                              dir_fd=fd)
            os.close(fd)
            fd = next_fd
            metadata = os.fstat(fd)
            if metadata.st_uid not in (0, os.geteuid()) or stat.S_IMODE(metadata.st_mode) & 0o022:
                raise ValueError('Untrusted Greeter runtime path')
        metadata = os.fstat(fd)
        if metadata.st_uid != os.geteuid() or stat.S_IMODE(metadata.st_mode) != 0o700:
            raise ValueError('Greeter runtime must be private and owned by its UID')
    except BaseException:
        os.close(fd)
        raise
    return path, fd


def prepare(environment):
    """Return a new environment; leave the caller/user session unchanged.

    Directories live in logind's UID runtime directory, never persistent /tmp.
    They remain until runtime teardown so compositor children cannot race cleanup.
    """
    path, runtime_fd = runtime_directory(environment)
    name = 'kos-greeter-' + secrets.token_hex(16)
    private_fd = None
    try:
        os.mkdir(name, mode=0o700, dir_fd=runtime_fd)
        private_fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                             dir_fd=runtime_fd)
        for directory in ('config', 'config-dirs', 'cache', 'data'):
            os.mkdir(directory, mode=0o700, dir_fd=private_fd)
        config_fd = os.open('config', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                            dir_fd=private_fd)
        try:
            fd = os.open('kwinrc', os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                         0o600, dir_fd=config_fd)
            with os.fdopen(fd, 'wb') as stream:
                stream.write(KWINRC)
        finally:
            os.close(config_fd)
    finally:
        if private_fd is not None: os.close(private_fd)
        os.close(runtime_fd)
    base = path / name
    result = dict(environment)
    result.update(XDG_RUNTIME_DIR=str(path), XDG_CONFIG_HOME=str(base/'config'), XDG_CONFIG_DIRS=str(base/'config-dirs'),
                  XDG_CACHE_HOME=str(base/'cache'), XDG_DATA_HOME=str(base/'data'))
    # KDE legacy config roots must not bypass the standard private lookup.
    result.pop('KDEHOME', None)
    result.pop('KDEROOTHOME', None)
    return result
