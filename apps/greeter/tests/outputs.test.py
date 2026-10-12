#!/usr/bin/env python3
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('outputs', ROOT / 'apps/greeter/companion/outputs.py')
outputs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(outputs)
BASE = ROOT / 'docs/kos-greeter/evidence/T06'

class Displays(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads((BASE / 'machine-output.example.json').read_text())
        self.inventory = json.loads((BASE / 'inventory.json').read_text())

    def test_baseline(self):
        result = outputs.plan(self.manifest, self.inventory)
        self.assertEqual(result['modeRequests'], [])
        self.assertEqual(result['outputs'][0]['scale'], 1.5)
        self.assertAlmostEqual(result['outputs'][0]['mode']['refreshHz'], 239.9980010986328)

    def test_exact_refresh_and_safe_preferred(self):
        self.manifest['outputs'][0]['mode']['refreshHz'] = 240
        result = outputs.plan(self.manifest, self.inventory)
        self.assertEqual(result['outputs'][0]['reason'], 'unsupported-mode')
        self.assertLess(result['outputs'][0]['mode']['refreshHz'], 60)

    def test_identity_connector_change_and_unknown(self):
        self.inventory[0]['connector'] = 'eDP-9'
        self.assertEqual(outputs.plan(self.manifest, self.inventory)['outputs'][0]['reason'], 'matched')
        self.inventory[0]['hardwareId'] = None
        self.assertEqual(outputs.plan(self.manifest, self.inventory)['outputs'][0]['reason'], 'unknown-or-ambiguous-hardware')

    def test_duplicate_edid_is_ambiguous_without_connector(self):
        second = copy.deepcopy(self.inventory[0]); second['connector'] = 'DP-1'
        self.inventory[0]['connector'] = 'eDP-9'
        self.inventory.append(second)
        self.assertTrue(all(o['reason'] == 'unknown-or-ambiguous-hardware'
                            for o in outputs.plan(self.manifest, self.inventory)['outputs']))

    def test_hotplug_lid_unplug_priority(self):
        external = copy.deepcopy(self.inventory[0])
        external.update(connector='DP-1', hardwareId=None, position=[-1920, -300], scale=2, priority=1)
        self.inventory.append(external)
        self.inventory[0]['closed'] = True
        result = outputs.plan(self.manifest, self.inventory, 'hotplug')
        self.assertEqual(result['primary'], 'DP-1')
        self.assertEqual(result['modeRequests'], [])
        rect = outputs.form_rect(result['outputs'][0])
        self.assertGreaterEqual(rect[0], -1920)
        self.assertGreaterEqual(rect[1], -300)
        self.assertLessEqual(rect[0] + rect[2], -1920 + 1280)
        external['connected'] = False
        self.assertEqual(outputs.plan(self.manifest, self.inventory, 'hotplug')['state'], 'unavailable')
        self.inventory[0]['closed'] = False
        self.assertEqual(outputs.plan(self.manifest, self.inventory, 'hotplug')['primary'], 'eDP-2')

    def test_rotation_small_viewport(self):
        screen = dict(logicalSize=[240, 180], position=[-240, 30])
        self.assertEqual(outputs.form_rect(screen), [-224, 46, 208, 148])
        self.assertIsNone(outputs.form_rect(dict(logicalSize=[20, 20], position=[0, 0])))
        self.manifest['outputs'][0]['rotation'] = 90
        self.assertAlmostEqual(outputs.plan(self.manifest, self.inventory)['outputs'][0]['logicalSize'][0], 1600/1.5)

    def test_no_avatar_modeset_and_idempotent(self):
        self.assertEqual(outputs.plan(self.manifest, self.inventory, 'user-selection')['modeRequests'], [])
        first = outputs.plan(self.manifest, self.inventory)
        self.assertEqual(first, outputs.plan(self.manifest, self.inventory))

    def test_invalid_contract(self):
        for field, value in [('schemaVersion', True), ('schemaVersion', 2), ('password', 'fake')]:
            manifest = copy.deepcopy(self.manifest); manifest[field] = value
            with self.assertRaises(ValueError): outputs.validate(manifest)
        for field, value in [('scale', float('nan')), ('hdr', True), ('vrr', 'automatic'), ('position', [0, 1e20])]:
            manifest = copy.deepcopy(self.manifest); manifest['outputs'][0][field] = value
            with self.assertRaises(ValueError): outputs.validate(manifest)
        self.inventory[0]['position'] = [float('nan'), 0]
        with self.assertRaises(ValueError): outputs.plan(self.manifest, self.inventory)

if __name__ == '__main__':
    unittest.main(verbosity=2)
