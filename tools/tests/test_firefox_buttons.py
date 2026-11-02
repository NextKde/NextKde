"""Firefox profile management regression tests. Run only in a VM."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('firefox_buttons', Path(__file__).parents[1]/'firefox_buttons.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class FirefoxButtons(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.config = self.home/'.config'
        self.profile = self.home/'firefox-profile'
        self.profile.mkdir()

    def test_install_switch_restore_preserves_user_files(self):
        css = self.profile/'chrome/userChrome.css'
        js = self.profile/'user.js'
        original_css = '/* personal theme */\n#urlbar { font-weight: bold; }\n'
        original_js = 'user_pref("browser.startup.page", 1);\n'
        m.write(css, original_css); m.write(js, original_js)
        m.install(self.config, [self.profile]); m.install(self.config, [self.profile])
        self.assertEqual(css.read_text().count(m.BEGIN), 1)
        self.assertIn('.titlebar-close', css.read_text())
        self.assertIn(original_js, js.read_text())
        rules = (self.config/'kos/window-buttons.json').read_text()
        m.sync(self.config, False, 'always')
        self.assertEqual(css.read_text(), original_css)
        self.assertEqual((self.config/'kos/window-buttons.json').read_text(), rules)
        m.sync(self.config, True, 'hover')
        self.assertIn('--kos-visible-glyph: none', css.read_text())
        css.write_text(css.read_text()+'/* later edit */\n')
        m.uninstall(self.config)
        self.assertEqual(css.read_text(), original_css+'/* later edit */\n')
        self.assertEqual(js.read_text(), original_js)

    def test_missing_profiles_and_symlinks_do_not_get_written(self):
        (self.profile/'chrome').symlink_to(self.home)
        with self.assertRaises(ValueError): m.install(self.config, [self.profile])
        self.assertFalse((self.profile/'user.js').exists())
        with self.assertRaises(ValueError): m.install(self.config, [])

    def test_theme_owned_enabled_user_js_is_preserved(self):
        target=self.home/'theme.js'
        original=f'user_pref("{m.PREF}", true);\n'
        target.write_text(original)
        (self.profile/'user.js').symlink_to(target)
        m.install(self.config,[self.profile])
        m.sync(self.config,False,'hover'); m.sync(self.config,True,'hover')
        m.uninstall(self.config)
        self.assertTrue((self.profile/'user.js').is_symlink())
        self.assertEqual(target.read_text(),original)
        target.write_text(f'user_pref("{m.PREF}", false);\n')
        with self.assertRaises(ValueError): m.install(self.config,[self.profile])

    def test_native_discovery_and_rule_scope(self):
        root=self.config/'mozilla/firefox'; root.mkdir(parents=True)
        (root/'normal').mkdir()
        (root/'profiles.ini').write_text('[Profile0]\nIsRelative=1\nPath=normal\n')
        profiles=m.discover(self.home, self.config)
        self.assertEqual(profiles, [root/'normal'])
        m.install(self.config, profiles)
        rules=json.loads((self.config/'kos/window-buttons.json').read_text())['rules']
        self.assertEqual(rules[0]['match'], {'class':'firefox', 'type':'normal'})
        self.assertTrue(rules[0]['nativeGtkControls'])
        self.assertNotIn('showButtons', rules[0])

    def test_no_registration_means_no_profile_mutation(self):
        m.sync(self.config, True, 'always')
        self.assertEqual(list(self.profile.iterdir()), [])
        self.assertFalse(m.state_path(self.config).exists())

    def test_invalid_rules_do_not_partially_install(self):
        m.write(self.config/'kos/window-buttons.json','{broken')
        with self.assertRaises(ValueError): m.install(self.config,[self.profile])
        self.assertFalse((self.profile/'user.js').exists())
        self.assertFalse((self.profile/'chrome/userChrome.css').exists())

    def test_malformed_file_keeps_both_profiles_untouched(self):
        m.write(self.profile/'chrome/userChrome.css',m.BEGIN+'\nbroken')
        with self.assertRaises(ValueError): m.install(self.config,[self.profile])
        self.assertFalse((self.profile/'user.js').exists())

if __name__ == '__main__': unittest.main()
