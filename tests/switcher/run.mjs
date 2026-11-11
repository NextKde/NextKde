import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, readFileSync, writeFileSync, copyFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const directory = mkdtempSync(join(tmpdir(), 'kos-switcher-'));
const source = new URL('../../shell/desktop/modules/', import.meta.url);
try {
    for (const name of ['SwitcherContent', 'SwitcherService']) {
        writeFileSync(join(directory, name + '.qml'),
            readFileSync(new URL('switcher/' + name + '.qml', source), 'utf8')
                .replace(/^import (qs\..*|Quickshell)$/gm, '')
                .replaceAll('Quickshell.stateDir', '"/state/kos"'));
    }
    copyFileSync(new URL('tst_switcher.qml', import.meta.url), join(directory, 'tst_switcher.qml'));
    const fixtures = {
        SwitcherCard: 'Item { property var windowRecord; property bool selected; property bool previewActive }',
        LiquidGlassPanel: 'Item { property Item blurAnchor; property int radius; property real cornerExponent; property bool scrimEnabled; property string scrimLevel; property real effectOpacity; property var blurRegion: null }',
        AppearanceTokens: 'QtObject { property var shape: ({cornerExponent: 2}); property var surface: ({usesBackdrop: true}) }',
        DockAnimation: 'QtObject { property int windowPreviewEntranceDuration: 90; property int windowPreviewExitDuration: 110; property int elementEnterEasing: Easing.OutCubic; property int elementExitEasing: Easing.InCubic }',
        WindowService: 'QtObject { property var records: [] }',
        PlatformClient: 'QtObject { signal eventReceived(string name, var payload); signal transportChanged(bool connected) }',
        StageConfigService: 'QtObject { function enqueueBashChain(args, done) { done(true) } }',
        JsonConfigStore: 'QtObject { function readPath(path, done) { done("{}") } function writePath(path, data) {} }',
    };
    let qmldir = 'singleton SwitcherService 1.0 SwitcherService.qml\n';
    for (const [name, body] of Object.entries(fixtures)) {
        const singleton = !['SwitcherCard', 'LiquidGlassPanel'].includes(name);
        writeFileSync(join(directory, name + '.qml'), (singleton ? 'pragma Singleton\n' : '') + 'import QtQuick\n' + body);
        qmldir += `${singleton ? 'singleton ' : ''}${name} 1.0 ${name}.qml\n`;
    }
    writeFileSync(join(directory, 'qmldir'), qmldir);
    const result = spawnSync(process.env.QMLTESTRUNNER || '/usr/lib/qt6/bin/qmltestrunner', ['-input', directory], {
        encoding: 'utf8', timeout: 20000,
        env: {...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QUICK_BACKEND: 'software', QT_FORCE_STDERR_LOGGING: '1'},
    });
    const output = (result.stdout || '') + (result.stderr || '');
    console.log(output.trim());
    assert.equal(result.status, 0, output);
    assert.doesNotMatch(output, /QWARN|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign/);
} finally {
    rmSync(directory, {recursive: true, force: true});
}
