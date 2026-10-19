"""Fail closed for in-process entry tests; reviewed launch mocks override this."""
from contextlib import contextmanager, ExitStack
import os
import subprocess
from unittest.mock import patch


@contextmanager
def block_real_launch():
    with ExitStack() as stack:
        for name in ('execv', 'execve', 'execvp', 'execvpe', 'execl', 'execle', 'execlp', 'execlpe',
                     'posix_spawn', 'posix_spawnp', 'system'):
            if hasattr(os, name):
                stack.enter_context(patch.object(os, name, side_effect=AssertionError('Unmocked entry launch: ' + name)))
        stack.enter_context(patch.object(subprocess, 'Popen', side_effect=AssertionError('Unmocked entry child launch')))
        yield
