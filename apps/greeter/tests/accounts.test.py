#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
import tempfile
import os
from types import SimpleNamespace
import io
from PIL import Image

spec = importlib.util.spec_from_file_location('accounts', Path(__file__).resolve().parents[1] / 'companion/accounts.py')
accounts = importlib.util.module_from_spec(spec); spec.loader.exec_module(accounts)

class IdentityTests(unittest.TestCase):
    def test_identity_and_fallback(self):
        user = accounts.normalize({'Uid': 1001, 'UserName': 'alice', 'RealName': '  ', 'IconFile': '/home/alice/.face'})
        self.assertEqual(user, {'uid': 1001, 'username': 'alice', 'displayName': 'alice', 'avatar': ''})
        other = accounts.normalize({'Uid': 1002, 'UserName': 'bob', 'RealName': 'Alice'})
        self.assertEqual(other['uid'], 1002)
        self.assertEqual(other['username'], 'bob')
        self.assertEqual(other['displayName'], 'Alice')
        for uid in (-1, True, '1000'):
            self.assertIsNone(accounts.normalize({'Uid': uid, 'UserName': 'alice'}))
        self.assertEqual(accounts.avatar('/var/lib/AccountsService/icons/missing-test-icon'), '')

    def test_avatar_safety_and_decode(self):
        with patch.object(accounts.os, 'open', side_effect=AssertionError('Home was opened')) as opened:
            self.assertEqual(accounts.avatar('/home/private/.face'), '')
            opened.assert_not_called()
        with patch.object(accounts.Path, 'lstat', return_value=SimpleNamespace(st_mode=0o40755, st_uid=0, st_gid=0)), patch.object(accounts.os, 'open', side_effect=PermissionError()):
            self.assertEqual(accounts.avatar('/var/lib/AccountsService/icons/test'), '')
        for mode in (0o120777, 0o40777):
            with patch.object(accounts.Path, 'lstat', return_value=SimpleNamespace(st_mode=mode, st_uid=0, st_gid=0)), patch.object(accounts.os, 'open', side_effect=AssertionError('Unsafe path opened')) as opened:
                self.assertEqual(accounts.avatar('/var/lib/AccountsService/icons/test'), '')
                opened.assert_not_called()
        with patch.object(accounts.Path, 'lstat', return_value=SimpleNamespace(st_mode=0o40775, st_uid=0, st_gid=1000)), patch.object(accounts.os, 'open', side_effect=AssertionError('Untrusted group directory opened')) as opened:
            self.assertEqual(accounts.avatar('/var/lib/AccountsService/icons/test'), '')
            opened.assert_not_called()
        encoded = io.BytesIO(); Image.new('RGB', (20, 20)).save(encoded, 'PNG')
        big = io.BytesIO(); Image.new('RGB', (1025, 1025)).save(big, 'PNG')
        for raw, valid in ((b'broken image', False), (encoded.getvalue(), True), (big.getvalue(), False)):
            with tempfile.TemporaryFile() as stream:
                stream.write(raw); stream.seek(0)
                directory = SimpleNamespace(st_mode=0o40775, st_uid=0, st_gid=0)
                info = SimpleNamespace(st_mode=0o100644, st_uid=0, st_size=len(raw))
                with patch.object(accounts.Path, 'lstat', autospec=True, side_effect=lambda p: directory if str(p).startswith('/var/lib/AccountsService') else SimpleNamespace(st_mode=0o40755, st_uid=0, st_gid=0)), patch.object(accounts.os, 'open', return_value=os.dup(stream.fileno())), patch.object(accounts.os, 'fstat', return_value=info):
                    result = accounts.avatar('/var/lib/AccountsService/icons/test')
                    self.assertEqual(result.startswith('data:image/png;base64,'), valid)
                    if valid:
                        import base64
                        pixels = Image.open(io.BytesIO(base64.b64decode(result.split(',', 1)[1])))
                        self.assertEqual(pixels.mode, 'RGBA')
                        self.assertEqual(pixels.size, (96, 96))
                        self.assertEqual(pixels.getpixel((0, 0))[3], 0)
                        self.assertEqual(pixels.getpixel((48, 48))[3], 255)

    def test_snapshot_and_unavailable(self):
        def reader(*args):
            if args[0] == 'call':
                return [['/org/freedesktop/Accounts/User1001', '/org/freedesktop/Accounts/User1002', '/bad', '/org/freedesktop/Accounts/User1001']]
            uid = int(args[2].rsplit('User', 1)[1])
            return {'Uid': uid, 'UserName': 'alice' if uid == 1001 else 'bob', 'RealName': '', 'IconFile': '/home/private/.face'}[args[-1]]
        self.assertEqual([u['uid'] for u in accounts.snapshot(reader)], [1001, 1002])
        def unavailable(*args):
            raise RuntimeError()
        self.assertEqual(accounts.snapshot(unavailable), [])

unittest.main()
