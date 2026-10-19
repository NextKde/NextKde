#!/usr/bin/env python3
"""Actual staged authentication QML: delayed image and bounded fallback startup."""
import base64
import io
import json
import os
from pathlib import Path
import shutil
import signal
import sys
import subprocess
import tempfile
import unittest

from PIL import Image

APP = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('qs'), 'Quickshell required')
class Startup(unittest.TestCase):
    def run_frontend(self, corrupt=False, blocked=False, single=False, delay=1.2):
        with tempfile.TemporaryDirectory(prefix='kos-startup-') as directory:
            app = Path(directory)
            shutil.copytree(APP/'qml', app/'qml')
            shutil.copytree(APP/'wallpapers', app/'wallpapers')
            windows = app/'qml/WallpaperWindows.qml'
            text = windows.read_text().replace(
                'onDecoded: console.info("KOS_WALLPAPER_DECODE_READY " + window.screen.name)',
                'onDecoded: {\n                    if (width !== window.screen.width || height !== window.screen.height)\n                        throw new Error("BACKGROUND_NOT_SCREEN_SIZED");\n                    if (composition.decodeBudget[0] !== Math.ceil(width * window.devicePixelRatio * 1.06) ||\n                        composition.decodeBudget[1] !== Math.ceil(height * window.devicePixelRatio * 1.06))\n                        throw new Error("BACKGROUND_DESKTOP_DPR_MISMATCH");\n                    console.info("PASS real background uses full screen and desktop decode budget");\n                }')
            windows.write_text(text)
            (app/'companion').mkdir()
            (app/'companion/accounts.py').write_text('import time\ntime.sleep(.8)\nprint("[{\\"uid\\":1000,\\"username\\":\\"fixture\\",\\"displayName\\":\\"Fixture\\",\\"avatar\\":\\"\\"}]")\n' if single else 'print("[]")\n')
            buffer = io.BytesIO()
            Image.new('RGB', (2160, 1212), '#689abc').save(buffer, format='PNG')
            data = 'bad-png' if corrupt else base64.b64encode(buffer.getvalue()).decode()
            state = dict(uid=1000 if single else -1, source='data:image/png;base64,'+data,
                         fit='crop', version='fixture')
            (app/'companion/wallpaper.py').write_text(
                'import time\ntime.sleep('+str(delay)+')\nprint('+repr(json.dumps(state))+')\n')
            source = (APP/'shell.qml').read_text()
            source = source.rsplit('}', 1)[0] + '''
    Timer { interval: 500; running: true; onTriggered: {
        if (window.visible || root.startupComplete) throw new Error("AUTH_BEFORE_IMAGE");
        console.info("PASS auth hidden while image pending");
    } }
    Connections { target: window
        function onVisibleChanged() {
            if (!window.visible) return;
            if (!wallpaperSource.ready || !primaryWallpaper.resourceSettled || !root.accountsReady)
                throw new Error("AUTH_BEFORE_DECODE");
            if (wallpaperSource.state.version !== "fixture")
                throw new Error("AUTH_BEFORE_CURRENT_ACCOUNT_WALLPAPER");
            if (root.accounts.length === 1 && root.selectedUid !== 1000)
                throw new Error("AUTH_BEFORE_ACCOUNT_SELECTION");
            if (window.implicitWidth !== window.screen.width || window.implicitHeight !== window.screen.height)
                throw new Error("FIXED_AUTH_GEOMETRY");
            if (Quickshell.env("QT_QPA_PLATFORM") === "wayland" && primaryWallpaper.visible)
                throw new Error("AUTH_DUPLICATES_BACKGROUND");
            console.info("PASS first auth visibility after settled wallpaper at screen geometry");
        }
    }
    Timer { interval: 3000; running: true; onTriggered: {
        if (!window.visible || !root.startupComplete) throw new Error("AUTH_STUCK");
        // Later account reloads must not hide a usable authentication window.
        root.selectedUid = 12345;
        if (!window.visible) throw new Error("AUTH_HIDDEN_ON_UID_CHANGE");
        console.info("PASS account change retains auth visibility");
        Qt.quit();
    } }
}
'''
            if blocked:
                # Exercise the real layer gate with no background instance.
                source = source.replace('Quickshell.env("QT_QPA_PLATFORM") === "offscreen" ||', 'false ||')
                source = source.replace('interval: 3000; running: true;', 'interval: 8500; running: true;')
                if blocked == 'loader-error':
                    source = source.replace('source: "qml/WallpaperWindows.qml"', 'source: "qml/MissingBackground.qml"')
                    source = source.replace('active: Quickshell.env("QT_QPA_PLATFORM") !== "offscreen"', 'active: true')
            elif delay > 1.2:
                source = source.replace('interval: 3000; running: true;', 'interval: 5500; running: true;')
            (app/'shell.qml').write_text(source)
            env = os.environ.copy()
            virtual = os.environ.get('KOS_STARTUP_VIRTUAL_SESSION') == '1'
            for key in (('GREETD_SOCK',) if virtual else ('DISPLAY', 'WAYLAND_DISPLAY', 'WAYLAND_SOCKET', 'GREETD_SOCK')):
                env.pop(key, None)
            env['QT_QPA_PLATFORM'] = 'wayland' if virtual else 'offscreen'
            result = subprocess.run(['qs', '--log-rules', '*.debug=false', '-p', str(app)],
                                    env=env, capture_output=True, text=True, timeout=12)
            logs = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, logs)
            self.assertNotIn('ERROR:', '\n'.join(line for line in logs.splitlines() if 'MissingBackground.qml' not in line))
            for marker in ('PASS auth hidden', 'PASS first auth visibility', 'PASS account change'):
                self.assertIn(marker, logs)
            if virtual:
                self.assertIn('PASS real background uses full screen and desktop decode budget', logs)
                print('PASS real background uses full screen and desktop decode budget')
            if blocked:
                self.assertIn('KOS_WALLPAPER_STARTUP_FALLBACK', logs)
            print('PASS '+('missing-background bounded fallback' if blocked else 'corrupt-image fallback' if corrupt else 'delayed-image decode')+' startup ordering')

    def test_virtual_screen_composition(self):
        with tempfile.TemporaryDirectory(prefix='kos-startup-virtual-') as directory:
            env = os.environ.copy()
            for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'GREETD_SOCK', 'KOS_GREETER_OUTPUT_APPLY', 'QT_QPA_PLATFORM'):
                env.pop(key, None)
            env['XDG_CONFIG_HOME'] = directory+'/config'
            env['KOS_STARTUP_VIRTUAL_SESSION'] = '1'
            with open(directory+'/log', 'w') as stream:
                process = subprocess.Popen(['dbus-run-session', '--', 'kwin_wayland', '--virtual',
                    '--width', '1536', '--height', '960', '--socket', 'kos-startup-'+str(os.getpid()),
                    '--no-lockscreen', '--no-global-shortcuts', '--no-kactivities', '--exit-with-session',
                    str(Path(__file__).resolve())], env=env, stdout=stream, stderr=stream, start_new_session=True)
                try:
                    code = process.wait(timeout=18)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL); process.wait(); code = 124
            logs = Path(directory+'/log').read_text()
            self.assertEqual(code, 0, logs)
            self.assertIn('PASS delayed-image decode startup ordering', logs)
            self.assertIn('PASS real background uses full screen and desktop decode budget', logs)
            print('PASS actual virtual KWin 16:10, scale 1.5, background/auth startup gate')

    def test_single_account_delayed_wallpaper(self):
        self.run_frontend(single=True)

    def test_delayed_image(self):
        self.run_frontend()

    def test_large_image_read_exceeding_old_three_second_deadline(self):
        self.run_frontend(single=True, delay=3.4)

    def test_loader_error_has_deadline(self):
        self.run_frontend(blocked='loader-error')

    def test_missing_background_has_deadline(self):
        self.run_frontend(blocked=True)

    def test_corrupt_image_falls_back(self):
        self.run_frontend(corrupt=True)


if __name__ == '__main__':
    if os.environ.get('KOS_STARTUP_VIRTUAL_SESSION') == '1':
        assert os.environ['WAYLAND_DISPLAY'].startswith('kos-startup-')
        inventory = json.loads(subprocess.check_output(['kscreen-doctor', '-j']))
        connector = inventory['outputs'][0]['name']
        subprocess.run(['kscreen-doctor', 'output.'+connector+'.scale.1.5'], check=True)
        result = unittest.TextTestRunner().run(unittest.TestSuite([Startup('test_delayed_image')]))
        sys.exit(0 if result.wasSuccessful() else 1)
    unittest.main()
