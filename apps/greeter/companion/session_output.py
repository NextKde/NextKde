"""Keep reviewed session diagnostics off the login VT, retaining journal streams."""
import ctypes
import fcntl
import os
import re
import stat
import sys
import syslog
import time


def journal_stream(identifier, priority):
    library = ctypes.CDLL('libsystemd.so.0')
    function = library.sd_journal_stream_fd
    function.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
    function.restype = ctypes.c_int
    descriptor = function(identifier.encode('ascii'), priority, 0)
    if descriptor < 0: raise OSError(-descriptor, 'journal stream unavailable')
    return descriptor


def close_quietly(descriptor):
    try: os.close(descriptor)
    except OSError: pass


class SilentOutput:
    """Python-level last resort when even /dev/null cannot be opened."""
    encoding = 'utf-8'
    def write(self, value): return len(value)
    def flush(self): pass
    def isatty(self): return False


def suppress_output():
    for target in (1, 2):
        descriptor = None
        try:
            descriptor = os.open('/dev/null', os.O_WRONLY)
            os.dup2(descriptor, target, inheritable=True)
        except OSError:
            # Never leave an original terminal fd after a setup failure.
            close_quietly(target)
            if target == 1: sys.stdout = SilentOutput()
            else: sys.stderr = SilentOutput()
        finally:
            if descriptor is not None and descriptor != target: close_quietly(descriptor)


def redirect_output(identifier):
    """Replace only stdout/stderr; stdin, controlling terminal and PID survive."""
    streams = []
    try:
        streams = [journal_stream(identifier, 6)]
        streams.append(journal_stream(identifier, 3))
        for descriptor, target in zip(streams, (1, 2)):
            os.dup2(descriptor, target, inheritable=True)
    except (OSError, AttributeError):
        # Journal/setup failure must neither block login nor expose logs on VT.
        suppress_output()
        try: syslog.syslog(syslog.LOG_ERR, 'KOS_SESSION journal-unavailable-output-suppressed')
        except OSError: pass
    finally:
        for descriptor in streams:
            if descriptor not in (1, 2): close_quietly(descriptor)


def diagnostic(line, error=False):
    try: print(line, file=sys.stderr if error else sys.stdout, flush=True)
    except OSError:
        # A stream can die after successful setup (e.g. journal restart).
        # Later session phase events must not prevent fixed startup.
        suppress_output()



def clear_inherited_vt():
    """Clear only the inherited Linux VT, without switching/opening another seat."""
    descriptor = None
    try:
        terminal = os.ttyname(0)
        match = re.fullmatch(r'/dev/tty([1-9][0-9]?)', terminal)
        if not match or int(match[1]) > 63: return False
        original = os.fstat(0)
        if not stat.S_ISCHR(original.st_mode) or os.major(original.st_rdev) != 4 or os.minor(original.st_rdev) != int(match[1]):
            return False
        # Confirm this fd is a VT, rather than trusting its pathname alone.
        fcntl.ioctl(0, 0x4B3B, bytearray(4))  # KDGETMODE; do not change mode.
        descriptor = os.open(terminal, os.O_WRONLY | os.O_NOCTTY | os.O_NOFOLLOW)
        current = os.fstat(descriptor)
        if (current.st_dev, current.st_ino, current.st_rdev) != (original.st_dev, original.st_ino, original.st_rdev):
            return False
        os.write(descriptor, b'\x1b[2J\x1b[3J\x1b[H')
        return True
    except OSError:
        return False
    finally:
        if descriptor is not None: close_quietly(descriptor)


def phase(name):
    # Callers pass fixed event names, never protocol data or environment.
    diagnostic('KOS_SESSION_PHASE ' + name + ' ' + str(time.monotonic_ns()))


def prepare_session_output(identifier):
    redirect_output(identifier)
    cleared = clear_inherited_vt()
    diagnostic('KOS_SESSION_OUTPUT ready vt-cleared=' + str(int(cleared)) + ' ' + str(time.monotonic_ns()))
