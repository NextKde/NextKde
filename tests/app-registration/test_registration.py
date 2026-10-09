from pathlib import Path
import configparser
import json
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
class RegistrationTests(unittest.TestCase):
    def test_promotes_new_apps_without_removing_legacy_or_unrelated_preferences(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); prefix = root / 'prefix'; config = root / 'config'; state = root / 'state'
            for path in (prefix / 'bin', prefix / 'share/applications', config / 'kos'): path.mkdir(parents=True)
            for name in ('listenfree', 'kos-todo', 'kos-calendar', 'kos-weather', 'kos-music'):
                executable = prefix / 'bin' / name; executable.write_text('#!/bin/sh\nexit 0\n'); executable.chmod(0o755)
                (prefix / 'share/applications' / (name + '.desktop')).write_text('[Desktop Entry]\nName=KOS Music\nMimeType=audio/mpeg;audio/flac;\n')
            legacy = (prefix / 'bin/kos-music').read_bytes()
            for app in ('todo', 'calendar', 'weather'):
                (prefix / 'bin' / f'kos-{app}-preview').write_text('old preview')
                (prefix / 'share/applications' / f'kos-{app}-preview.desktop').write_text('old preview')
            preview = prefix / 'opt/nextkde-ui-preview'; preview.mkdir(parents=True); (preview / 'marker').write_text('preserved in backup')
            (config / 'mimeapps.list').write_text('[Default Applications]\naudio/mpeg=kos-music.desktop;\ntext/plain=editor.desktop;\n[Added Associations]\naudio/mpeg=kos-music.desktop;\n[Removed Associations]\naudio/flac=listenfree.desktop;other.desktop;\n')
            (config / 'kde-mimeapps.list').write_text('[Default Applications]\naudio/mpeg=kos-music.desktop;\n')
            (config / 'kos/window-buttons.json').write_text(json.dumps({'apps': {'custom': {'showButtons': True}, 'kos-todo-preview': {'showButtons': False}}, 'rules': [{'match': {'class': 'custom'}, 'showButtons': True}]}))
            command = [sys.executable, str(ROOT / 'tools/register-default-apps.py'), '--prefix', str(prefix), '--config-home', str(config), '--state-home', str(state), '--no-cache']
            before = (config / 'mimeapps.list').read_bytes()
            subprocess.run(command + ['--dry-run'], check=True, stdout=subprocess.PIPE)
            self.assertEqual((config / 'mimeapps.list').read_bytes(), before)
            subprocess.run(command, check=True, stdout=subprocess.PIPE)
            subprocess.run(command, check=True, stdout=subprocess.PIPE) # Upgrades are repeatable.
            prefs = configparser.ConfigParser(); prefs.read(config / 'mimeapps.list')
            self.assertEqual(prefs['Default Applications']['audio/mpeg'], 'listenfree.desktop;')
            self.assertEqual(prefs['Default Applications']['text/plain'], 'editor.desktop;')
            self.assertEqual(prefs['Added Associations']['audio/mpeg'], 'listenfree.desktop;kos-music.desktop;')
            self.assertEqual(prefs['Removed Associations']['audio/flac'], 'other.desktop;')
            prefs.read(config / 'kde-mimeapps.list'); self.assertEqual(prefs['Default Applications']['audio/mpeg'], 'listenfree.desktop;')
            self.assertEqual((prefix / 'bin/kos-music').read_bytes(), legacy)
            self.assertTrue((prefix / 'share/applications/kos-music.desktop').exists())
            self.assertFalse(preview.exists()); self.assertFalse(list((prefix / 'bin').glob('*-preview')))
            self.assertTrue(list(state.glob('kos/application-registration/*/retired-preview/marker')))
            buttons = json.loads((config / 'kos/window-buttons.json').read_text())
            self.assertTrue(buttons['apps']['custom']['showButtons'])
            self.assertEqual(len(buttons['rules']), 1)
            for name in ('listenfree', 'kos-todo', 'kos-calendar', 'kos-weather'): self.assertFalse(buttons['apps'][name]['showButtons'])
    def test_missing_new_app_is_rejected_before_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = subprocess.run([sys.executable, str(ROOT / 'tools/register-default-apps.py'), '--prefix', str(root), '--config-home', str(root / 'config'), '--state-home', str(root / 'state'), '--no-cache'], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / 'config').exists()); self.assertFalse((root / 'state').exists())

if __name__ == '__main__': unittest.main()
