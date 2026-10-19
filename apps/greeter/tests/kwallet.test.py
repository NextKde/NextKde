#!/usr/bin/env python3
"""Exercise PAM migration in a temporary filesystem, without host changes."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[3] / 'tools/fix-greetd-kwallet.py'
spec = importlib.util.spec_from_file_location('kwallet_fix', SCRIPT)
fix = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fix)


class Migration(unittest.TestCase):
    def test_new_existing_and_idempotent(self):
        for existing in (False, True):
            with self.subTest(existing=existing), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                target = root / 'etc/pam.d/greetd'
                target.parent.mkdir(parents=True)
                original = 'auth include system-local-login\nsession include system-local-login\n'
                if existing:
                    original += '-auth optional pam_kwallet5.so\n-session optional pam_kwallet5.so auto_start # keep comment force_run\n'
                target.write_text(original)
                module = root / 'usr/lib/security/pam_kwallet5.so'
                module.parent.mkdir(parents=True)
                module.touch()
                def mapped(value):
                    return Path(value) if str(value).startswith(str(root)) else root / str(value).lstrip('/')
                # The harness owner substitutes root, including backup checks.
                class Metadata:
                    def __init__(self, value):
                        self.value = value
                    def __getattr__(self, key):
                        return 0 if key == 'st_uid' else getattr(self.value, key)
                real_lstat = Path.lstat
                with patch.object(fix, 'Path', mapped), patch.object(fix.os, 'geteuid', return_value=0), patch.object(fix.os, 'fchown'), patch.object(Path, 'lstat', lambda path: Metadata(real_lstat(path))):
                    fix.main()
                    updated = target.read_text()
                    self.assertEqual(sum('force_run' in line.split('#', 1)[0].split() for line in updated.splitlines()), 2)
                    self.assertIn('auto_start', updated)
                    if existing:
                        self.assertIn('# keep comment force_run', updated)
                    backups = list((root / 'var/backups/kos-greeter').iterdir())
                    self.assertEqual(len(backups), 1)
                    self.assertEqual(backups[0].read_text(), original)
                    self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)
                    fix.main()
                    self.assertEqual(target.read_text(), updated)
                    self.assertEqual(len(list(backups[0].parent.iterdir())), 1)


if __name__ == '__main__':
    unittest.main()
