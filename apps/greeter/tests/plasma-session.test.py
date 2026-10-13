#!/usr/bin/env python3
"""Fixed distro argv only; no actual authentication or desktop launch."""
import sys
from pathlib import Path
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'companion'))
from plasma_session import installed_command, ALLOWED_COMMANDS, greetd_executable


class PlasmaSession(unittest.TestCase):
    def resolve(self, value, executable=True):
        def read(config, _):
            config.read_dict({'Desktop Entry': {'Exec': value}})
        with patch('plasma_session.configparser.ConfigParser.read', read), patch('plasma_session.os.access', return_value=executable):
            return installed_command()

    def test_supported_distro_paths(self):
        for command in ALLOWED_COMMANDS:
            self.assertEqual(self.resolve(' '.join(command)), list(command))

    def test_unknown_command_and_extra_arguments_rejected(self):
        for value in ('', '/tmp/startplasma', 'sh -c startplasma-wayland', ' '.join(ALLOWED_COMMANDS[0]) + ' --unknown'):
            with self.assertRaises(ValueError): self.resolve(value)

    def test_missing_executable_rejected(self):
        with self.assertRaises(ValueError): self.resolve(' '.join(ALLOWED_COMMANDS[0]), executable=False)

    def test_greetd_known_locations(self):
        for expected in ('/usr/bin/greetd', '/usr/sbin/greetd'):
            with patch('plasma_session.os.access', side_effect=lambda path, mode: path == expected):
                self.assertEqual(greetd_executable(), expected)


if __name__ == '__main__': unittest.main(verbosity=2)
