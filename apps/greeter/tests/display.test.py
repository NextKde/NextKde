#!/usr/bin/env python3
"""Controller fault/topology integration with atomic fake KScreen; no host modeset."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest

APP = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(APP / 'companion'))
import display

ROOT = APP.parents[1]
EVIDENCE = ROOT / 'apps/greeter/tests/fixtures/outputs'

class Backend:
    def __init__(self):
        self.raw = json.loads((EVIDENCE / 'outputs.json').read_text())
        self.hardware = {'eDP-2': json.loads((EVIDENCE / 'machine-output.example.json').read_text())['outputs'][0]['hardwareId']}
        self.lid = False
        self.commands = []
        self.fail = False
        self.ignore = False
        self.read_failures = 0

    def snapshot(self):
        if self.read_failures:
            self.read_failures -= 1
            raise subprocess.TimeoutExpired('fixture', 4)
        return display.normalize(copy.deepcopy(self.raw), self.hardware, self.lid)

    def apply(self, argv):
        self.commands.append(argv)
        if self.fail:
            raise subprocess.TimeoutExpired('fixture', 4)
        if self.ignore:
            return
        for argument in argv:
            _, identifier, setting, *values = argument.split('.')
            output = next(o for o in self.raw['outputs'] if o['name'] == identifier)
            value = '.'.join(values)
            if setting == 'mode': output['currentModeId'] = value
            elif setting == 'scale': output['scale'] = float(value)
            elif setting == 'position': output['pos'] = dict(zip(('x', 'y'), map(int, value.split(','))))
            elif setting == 'priority': output['priority'] = int(value)
            elif setting == 'rotation': output['rotation'] = next(k for k,v in display.ROTATIONS.items() if display.ROTATION_NAMES[v] == value)
            elif setting == 'enable': output['enabled'] = True
            elif setting == 'hdr': output['hdr'] = False
            elif setting == 'wcg': output['wcg'] = False
            elif setting == 'vrrpolicy': output['vrrPolicy'] = 0
            else: raise AssertionError(argument)

class DisplayTests(unittest.TestCase):
    def setUp(self):
        self.backend = Backend()
        self.policy = json.loads((EVIDENCE / 'machine-output.example.json').read_text())
        self.controller = display.Controller(self.backend, self.policy, True)

    def test_apply_atomic_and_readback(self):
        self.backend.raw['outputs'][0].update(currentModeId='1', scale=1, hdr=True, wcg=True, vrrPolicy=2)
        result = self.controller.tick()
        self.assertEqual(result['status'], 'applied')
        self.assertEqual(len(self.backend.commands), 1)
        self.assertIn('output.eDP-2.mode.2', self.backend.commands[0])
        self.assertIn('output.eDP-2.scale.1.5', self.backend.commands[0])
        self.assertIn('output.eDP-2.vrrpolicy.never', self.backend.commands[0])
        self.assertAlmostEqual(result['outputs'][0]['mode']['refreshHz'], 239.9980010986328)
        for _ in range(10): self.controller.tick()
        self.assertEqual(len(self.backend.commands), 1)

    def test_timeout_fallback_bounded(self):
        self.backend.raw['outputs'][0]['scale'] = 1
        self.backend.fail = True
        result = self.controller.tick()
        self.assertEqual(result['status'], 'fallback-failed')
        self.assertEqual(len(self.backend.commands), 2)
        for _ in range(10): self.controller.tick()
        self.assertEqual(len(self.backend.commands), 2)

    def test_accepted_but_ineffective_is_failure(self):
        self.backend.raw['outputs'][0]['scale'] = 1
        self.backend.ignore = True
        self.assertEqual(self.controller.tick()['status'], 'fallback-ineffective')
        self.assertEqual(len(self.backend.commands), 2)
        self.controller.tick()
        self.assertEqual(len(self.backend.commands), 2)

    def test_failed_readback_does_not_resubmit(self):
        self.backend.raw['outputs'][0]['scale'] = 1
        original = self.backend.apply
        def apply(args):
            original(args)
            self.backend.read_failures = 2
        self.backend.apply = apply
        with self.assertRaises(subprocess.TimeoutExpired): self.controller.tick()
        self.controller.tick()
        self.assertEqual(len(self.backend.commands), 1)

    def test_unknown_connector_no_hardware_match(self):
        self.backend.hardware = {}
        result = self.controller.tick()
        self.assertAlmostEqual(result['outputs'][0]['mode']['refreshHz'], 59.999000549316406)
        self.assertEqual(self.backend.commands, [['output.eDP-2.mode.1']])

    def test_shipped_policy_uses_preferred_without_personal_overrides(self):
        policy = json.loads((APP / 'config/outputs.json').read_text())
        self.assertEqual(policy, dict(schemaVersion=1, outputs=[]))
        self.backend.raw['outputs'][0].update(scale=2, pos={'x': -1280, 'y': 100})
        controller = display.Controller(self.backend, policy, True)
        result = controller.tick()
        self.assertEqual(result['status'], 'applied')
        self.assertEqual(self.backend.commands, [['output.eDP-2.mode.1']])
        self.assertEqual(result['outputs'][0]['scale'], 2)
        self.assertEqual(result['outputs'][0]['position'], [-1280, 100])
        controller.tick()
        self.assertEqual(len(self.backend.commands), 1)

    def test_lid_external_unplug_reopen_and_priority(self):
        self.controller.tick()
        external = copy.deepcopy(self.backend.raw['outputs'][0])
        external.update(id=2, name='DP-1', priority=2, scale=2, pos={'x': -1280, 'y': -100})
        self.backend.raw['outputs'].append(external)
        self.backend.lid = True
        result = self.controller.tick()
        self.assertEqual(result['primary'], 'DP-1')
        self.assertEqual(len(result['outputs']), 1)
        external['connected'] = False
        self.assertEqual(self.controller.tick()['state'], 'unavailable')
        self.backend.lid = False
        self.assertEqual(self.controller.tick()['primary'], 'eDP-2')
        self.assertFalse(any('disable' in command for args in self.backend.commands for command in args))

    def test_same_connector_replaced_hardware_gets_safe_policy(self):
        self.controller.tick()
        self.backend.hardware['eDP-2'] = 'edid-sha256:' + 'a' * 64
        result = self.controller.tick()
        self.assertEqual(result['status'], 'applied')
        self.assertLess(result['outputs'][0]['mode']['refreshHz'], 60)
        count = len(self.backend.commands)
        self.controller.tick()
        self.assertEqual(len(self.backend.commands), count)

    def test_edid_validation(self):
        block = bytearray(128); block[:8] = bytes.fromhex('00ffffffffffff00'); block[-1] = (-sum(block)) % 256
        self.assertTrue(display.edid_identity(bytes(block)).startswith('edid-sha256:'))
        block[15] ^= 1
        self.assertIsNone(display.edid_identity(bytes(block)))
        self.assertIsNone(display.edid_identity(b'bad'))

    def test_command_injection_rejected(self):
        self.backend.raw['outputs'][0]['id'] = '1; rm -rf fixture'
        self.backend.raw['outputs'][0]['scale'] = 1
        with self.assertRaises(ValueError): self.controller.tick()
        self.assertEqual(self.backend.commands, [])

if __name__ == '__main__': unittest.main(verbosity=2)
