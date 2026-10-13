"""Resolve the installed Plasma entry against a fixed distro path allowlist."""
import configparser
import os
import shlex

ALLOWED_COMMANDS = (
    ('/usr/lib/plasma-dbus-run-session-if-needed', '/usr/bin/startplasma-wayland'),
    ('/usr/lib/x86_64-linux-gnu/libexec/plasma-dbus-run-session-if-needed', '/usr/bin/startplasma-wayland'),
)


def greetd_executable():
    # Known package locations only; preflight checks executability separately.
    return next((path for path in ('/usr/bin/greetd', '/usr/sbin/greetd')
                 if os.access(path, os.X_OK)), '/usr/bin/greetd')


def installed_command():
    config = configparser.ConfigParser(interpolation=None, strict=False)
    config.read('/usr/share/wayland-sessions/plasma.desktop')
    command = tuple(shlex.split(config.get('Desktop Entry', 'Exec', fallback='')))
    if command not in ALLOWED_COMMANDS:
        raise ValueError('installed-session-allowlist')
    if any(not os.access(path, os.X_OK) for path in command):
        raise ValueError('missing-session-executable')
    return list(command)
