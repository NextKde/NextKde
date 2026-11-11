import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// Exercise the shipping state machine and native pre-dispatch input observer.
// Only external services are substituted; no compositor or session is touched.
const directory = mkdtempSync(join(tmpdir(), 'kos-startup-reveal-'));
try {
    const module = join(directory, 'Reveal');
    mkdirSync(module);
    const source = readFileSync(new URL('../../shell/desktop/modules/common/StartupReveal.qml', import.meta.url), 'utf8')
        .replace(/^import qs\.desktop\.modules\..*\n/gm, '')
        .replace('import Quickshell', '').replace('Scope {', 'Item {')
        .replace('target: Quickshell', 'target: Lifecycle');
    writeFileSync(join(module, 'StartupReveal.qml'), source);
    const services = {
        Lifecycle: 'signal reloadCompleted()',
        AppearanceConfigService: 'property bool ready: true; property bool reduceMotion: false; property int startupRevealDuration: 800',
        ConfigService: 'property bool ready: true',
        ScreenLifecycle: 'property bool outputAvailable: true',
        WallpaperService: 'property bool takeoverEnabled: false; function allOutputsReady() { return true }',
        AppLauncherService: 'property bool open: false',
    };
    for (const [name, properties] of Object.entries(services))
        writeFileSync(join(module, `${name}.qml`), `pragma Singleton\nimport QtQuick\nQtObject { ${properties} }\n`);
    writeFileSync(join(module, 'qmldir'), ['module Reveal', ...['StartupReveal', ...Object.keys(services)].map(name => `singleton ${name} 1.0 ${name}.qml`)].join('\n'));
    writeFileSync(join(directory, 'tst_reveal.qml'), `import QtQuick
import QtTest
import Reveal
Item {
    width: 320; height: 200
    property int clicks: 0
    MouseArea { id: dock; x: 40; y: 120; width: 120; height: 60; opacity: StartupReveal.dockProgress
        transform: Translate { y: StartupReveal.dockOffset * 28 }
        onClicked: parent.clicks++
    }
    TestCase {
        name: "StartupReveal"; when: windowShown
        function init() {
            StartupReveal.finish()
            AppearanceConfigService.reduceMotion = false
            AppLauncherService.open = false
            StartupReveal.loaded = false
            StartupReveal.started = false
            StartupReveal.progress = 0
        }
        function test_order_and_duration() {
            const phases = []
            const record = function() { phases.push(StartupReveal.phase) }
            StartupReveal.phaseChanged.connect(record)
            const start = Date.now()
            StartupReveal.loaded = true
            tryCompare(StartupReveal, "phase", "done", 1100)
            StartupReveal.phaseChanged.disconnect(record)
            compare(phases.join(","), "fading,bar,dock,icons,done")
            verify(Date.now() - start >= 750)
            verify(Date.now() - start < 1100)
            compare(StartupReveal.iconProgress(999, 1000), 1)
        }
        function test_click_at_zero_delivered() {
            compare(StartupReveal.progress, 0)
            const before = clicks
            // Inside the final slot, outside its displaced pre-reveal upper edge.
            mouseClick(dock.parent, 60, 125)
            compare(StartupReveal.progress, 1)
            compare(clicks, before + 1)
        }
        function test_keyboard_and_motion() {
            keyPress(Qt.Key_Super_L)
            compare(StartupReveal.progress, 1)
            keyRelease(Qt.Key_Super_L)
            StartupReveal.progress = 0
            mouseMove(dock.parent, 250, 30)
            compare(StartupReveal.progress, 1)
        }
        function test_launcher_cancels_before_open() {
            StartupReveal.loaded = true
            tryVerify(function() { return StartupReveal.progress > 0 })
            AppLauncherService.open = true
            compare(StartupReveal.phase, "done")
            wait(100)
            compare(StartupReveal.progress, 1)
        }
        function test_reduce_motion() {
            AppearanceConfigService.reduceMotion = true
            StartupReveal.loaded = true
            compare(StartupReveal.phase, "done")
            compare(StartupReveal.progress, 1)
        }
        function test_stagger_and_no_replay() {
            StartupReveal.progress = 0.8
            verify(StartupReveal.iconProgress(0, 10) > StartupReveal.iconProgress(9, 10))
            StartupReveal.finish()
            StartupReveal.loaded = true
            StartupReveal.begin()
            compare(StartupReveal.phase, "done")
        }
    }
}
`);
    const result = spawnSync(process.argv[2] || '/usr/lib/qt6/bin/qmltestrunner', ['-input', directory, '-import', directory], {
        encoding: 'utf8', timeout: 15000,
        env: {...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QUICK_BACKEND: 'software', QT_FORCE_STDERR_LOGGING: '1'},
    });
    process.stdout.write(result.stdout || '');
    process.stderr.write(result.stderr || '');
    if (result.error) throw result.error;
    process.exitCode = result.status === 0 ? 0 : 1;
} finally {
    rmSync(directory, { recursive: true, force: true });
}
