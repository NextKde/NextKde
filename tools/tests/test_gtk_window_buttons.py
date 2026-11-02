"""Run only in the validation VM: python3 -m unittest discover -s tools/tests -p test_gtk_window_buttons.py."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('gtk_buttons', Path(__file__).parents[1] / 'gtk-window-buttons.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class GtkButtonsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.config = Path(self.temp.name)
        self.which = patch.object(module.shutil, 'which', return_value=None)
        self.which.start()
        self.addCleanup(self.which.stop)
        self.reload = patch.object(module, 'reload_bridge')
        self.reload.start()
        self.addCleanup(self.reload.stop)

    def test_restore_and_idempotence(self):
        css = self.config / 'gtk-3.0/gtk.css'
        ini = self.config / 'gtk-3.0/settings.ini'
        css.parent.mkdir()
        original_css = '/* Personal style */\nbutton {font-weight: bold;}'
        original_ini = '# Comment\n[Settings]\ngtk-decoration-layout=:close\ngtk-font-name=Sans 12\n'
        css.write_text(original_css)
        ini.write_text(original_ini)
        module.install(self.config)
        module.install(self.config)
        self.assertEqual(css.read_text().count(module.BEGIN), 1)
        self.assertIn('gtk-font-name=Sans 12', ini.read_text())
        module.uninstall(self.config)
        self.assertEqual(css.read_text(), original_css)
        self.assertEqual(ini.read_text(), original_ini)
        self.assertFalse((self.config / 'gtk-4.0/gtk.css').exists())

    def test_right_layout_keeps_chromium_under_the_overlay(self):
        # Chromium consumes this same GTK layout even though it draws its own
        # browser controls. Keep both toolkit sources on the overlay's side.
        module.install(self.config)
        for version in ('3.0', '4.0'):
            line = module.layout_setting((self.config / f'gtk-{version}/settings.ini').read_text())
            leading, trailing = line.strip().split('=', 1)[1].split(':')
            self.assertEqual(leading, '')
            self.assertEqual(trailing.split(','), ['minimize', 'maximize', 'close'])

    def test_upgrade_left_layout_preserves_original_backup(self):
        self.which.stop()
        ini = self.config / 'gtk-3.0/settings.ini'
        ini.parent.mkdir()
        original = '[Settings]\ngtk-decoration-layout=:close\ngtk-font-name=Sans 12\n'
        ini.write_text(original)
        current = ["':close'"]
        def setting(action, schema, key, *value):
            if action == 'get': return current[0]
            current[0] = value[0] if value[0].startswith("'") else repr(value[0])
        with patch.object(module.shutil, 'which', return_value='/usr/bin/gsettings'), \
             patch.object(module, 'gsettings', side_effect=setting):
            with patch.object(module, 'layout_for_install', return_value=module.LEGACY_LAYOUT):
                module.install(self.config)
            state_path = self.config / 'kos/gtk-buttons-state.json'
            state = json.loads(state_path.read_text())
            state.pop('installedLayout') # Original releases did not record it.
            module.json_write(state_path, state)
            module.install(self.config)
            self.assertIn('gtk-decoration-layout=:minimize,maximize,close', ini.read_text())
            self.assertEqual(current[0], repr(':minimize,maximize,close'))
            module.restore_styles(self.config)
            self.assertEqual(ini.read_text(), original)
            self.assertEqual(current[0], "':close'")

    def test_preserve_original_right_layout_and_menu(self):
        ini = self.config / 'gtk-3.0/settings.ini'
        ini.parent.mkdir()
        original = '[Settings]\ngtk-decoration-layout=icon:minimize,maximize,close\n'
        ini.write_text(original)
        module.install(self.config)
        module.install(self.config)
        self.assertEqual(ini.read_text(), original)
        state = json.loads((self.config / 'kos/gtk-buttons-state.json').read_text())
        self.assertEqual(state['installedLayout'], 'icon:minimize,maximize,close')

    def test_restore_old_left_layout_with_later_unrelated_edits(self):
        self.which.stop()
        current = ["':close'"]
        def setting(action, schema, key, *value):
            if action == 'get': return current[0]
            current[0] = value[0] if value[0].startswith("'") else repr(value[0])
        with patch.object(module.shutil, 'which', return_value='/usr/bin/gsettings'), \
             patch.object(module, 'gsettings', side_effect=setting):
            with patch.object(module, 'layout_for_install', return_value=module.LEGACY_LAYOUT):
                module.install(self.config)
            state_path = self.config / 'kos/gtk-buttons-state.json'
            state = json.loads(state_path.read_text())
            state.pop('installedLayout')
            module.json_write(state_path, state)
            ini = self.config / 'gtk-3.0/settings.ini'
            ini.write_text(ini.read_text() + 'gtk-font-name=Sans 15\n')
            module.restore_styles(self.config)
            self.assertIn('gtk-font-name=Sans 15', ini.read_text())
            self.assertNotIn('gtk-decoration-layout=', ini.read_text())
            self.assertEqual(current[0], "':close'")

    def test_preserve_later_edits(self):
        module.install(self.config)
        css = self.config / 'gtk-3.0/gtk.css'
        ini = self.config / 'gtk-3.0/settings.ini'
        css.write_text(css.read_text() + '\n/* Later user style */\n')
        ini.write_text(ini.read_text().replace(module.LAYOUT, ':close') + 'gtk-font-name=Sans 15\n')
        module.uninstall(self.config)
        self.assertIn('Later user style', css.read_text())
        self.assertNotIn(module.BEGIN, css.read_text())
        self.assertIn('gtk-decoration-layout=:close', ini.read_text())
        self.assertIn('Sans 15', ini.read_text())

    def test_unknown_apps_keep_overlay_and_rules_survive(self):
        path = self.config / 'kos/window-buttons.json'
        manual = {'match': {'class': 'other'}, 'showButtons': False}
        module.json_write(path, {'default': {'buttonSize': 15}, 'rules': [manual]})
        with self.assertRaises(ValueError):
            module.rules(self.config, 'org.example.Gtk')
        module.install(self.config)
        module.rules(self.config, 'org.example.Gtk')
        module.rules(self.config, 'org.example.Gtk')
        data = json.loads(path.read_text())
        self.assertEqual(len(data['rules']), 2)
        self.assertEqual(data['rules'][1]['match'], {'class': 'org.example.Gtk', 'type': 'normal'})
        module.rules(self.config, 'org.example.Gtk', remove=True)
        self.assertEqual(json.loads(path.read_text())['rules'], [manual])
        module.rules(self.config, 'org.example.Gtk', 'Standard title')
        module.uninstall(self.config)
        self.assertEqual(json.loads(path.read_text()), {'default': {'buttonSize': 15}, 'rules': [manual]})

    def test_bad_config_does_not_get_overwritten(self):
        path = self.config / 'kos/window-buttons.json'
        module.atomic_write(path, '{broken json')
        with self.assertRaises(ValueError):
            module.rules(self.config, 'org.example.Gtk', remove=True)
        self.assertEqual(path.read_text(), '{broken json')
        with self.assertRaises(ValueError):
            module.strip_css(module.BEGIN + '\nunfinished')

    def test_shared_switch_keeps_qualification_and_follows_glyph_mode(self):
        module.install(self.config, 'hover')
        module.rules(self.config, 'org.example.Gtk')
        path = self.config / 'kos/window-buttons.json'
        before = path.read_text()
        self.assertIn('-gtk-icon-filter: opacity(0)', (self.config / 'gtk-4.0/gtk.css').read_text())
        module.restore_styles(self.config)
        self.assertEqual(path.read_text(), before)
        self.assertFalse((self.config / 'gtk-3.0/gtk.css').exists())
        module.install(self.config, 'always')
        self.assertNotIn('-gtk-icon-filter: opacity(0)', (self.config / 'gtk-4.0/gtk.css').read_text())
        self.assertEqual(path.read_text(), before)

    def test_managed_symlink_is_not_replaced(self):
        target = self.config / 'managed.css'
        target.write_text('/* Declarative theme */')
        css = self.config / 'gtk-4.0/gtk.css'
        css.parent.mkdir()
        css.symlink_to(target)
        with self.assertRaises(ValueError):
            module.install(self.config)
        self.assertTrue(css.is_symlink())
        self.assertFalse((self.config / 'gtk-3.0/gtk.css').exists())
        self.assertEqual(target.read_text(), '/* Declarative theme */')

    def test_gsettings_restore_respects_later_choice(self):
        self.which.stop()
        with patch.object(module.shutil, 'which', return_value='/usr/bin/gsettings'), \
             patch.object(module, 'gsettings', return_value="':close'") as settings:
            module.install(self.config)
            settings.assert_any_call('set', module.SCHEMA, module.KEY, module.LAYOUT)
            settings.reset_mock()
            module.uninstall(self.config)
            self.assertFalse(any(call.args[0] == 'set' for call in settings.call_args_list))


if __name__ == '__main__':
    unittest.main()
