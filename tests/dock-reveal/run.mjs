import assert from 'node:assert/strict';
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

// Exercise the shipping handle, controller, geometry and timing code with
// synthetic Qt events in an offscreen QQuickWindow. Service state and the glass
// renderer are stubbed; no event reaches the user's compositor or pointer.
const repository = fileURLToPath(new URL('../..', import.meta.url));
const directory = mkdtempSync(join(tmpdir(), 'kos-dock-reveal-'));
try {
    const dock = join(directory, 'desktop/modules/dock');
    const common = join(directory, 'desktop/modules/common');
    for (const path of [dock, common, join(directory, 'config'), join(directory, 'state'), join(directory, 'runtime')])
        mkdirSync(path, { recursive: true, mode: 0o700 });
    for (const name of ['DockRevealHandle.qml', 'DockRevealGeometry.mjs',
        'DockAutoHideController.qml', 'DockAutoHideMath.mjs', 'DockAnimation.qml'])
        symlinkSync(join(repository, 'shell/desktop/modules/dock', name), join(dock, name));
    copyFileSync(new URL('fixtures/WindowService.qml', import.meta.url), join(dock, 'WindowService.qml'));
    for (const name of ['LiquidGlassPanel.qml', 'AppearanceTokens.qml'])
        copyFileSync(new URL(`fixtures/${name}`, import.meta.url), join(common, name));
    writeFileSync(join(dock, 'qmldir'), `module qs.desktop.modules.dock
DockRevealHandle 1.0 DockRevealHandle.qml
DockAutoHideController 1.0 DockAutoHideController.qml
singleton DockAnimation 1.0 DockAnimation.qml
singleton WindowService 1.0 WindowService.qml
`);
    writeFileSync(join(common, 'qmldir'), `module qs.desktop.modules.common
LiquidGlassPanel 1.0 LiquidGlassPanel.qml
singleton AppearanceTokens 1.0 AppearanceTokens.qml
`);
    copyFileSync(new URL('shell.qml', import.meta.url), join(directory, 'shell.qml'));
    const result = spawnSync(process.argv[2] || 'quickshell', ['-p', directory], {
        encoding: 'utf8', timeout: 22000,
        env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QUICK_BACKEND: 'software',
            WAYLAND_DISPLAY: '', DISPLAY: '',
            XDG_CONFIG_HOME: join(directory, 'config'), XDG_STATE_HOME: join(directory, 'state'),
            XDG_RUNTIME_DIR: join(directory, 'runtime'),
            KOS_PLATFORM_SOCKET: join(directory, 'absent-platform.sock'),
            KOS_DATA_SOCKET: join(directory, 'absent-data.sock') },
    });
    const output = (result.stdout || '') + (result.stderr || '');
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, output);
    assert.doesNotMatch(output, /FAIL |ReferenceError|TypeError|Binding loop|is not a type|is not a function|Cannot assign|Unable to assign/, output);
    assert.match(output, /DOCK_REVEAL_RUNTIME_PASS/, output);
    console.log('Dock reveal: real HoverHandler input, delayed/cancelled entry, slow gap hand-off, hide reset, dynamic span, legacy default, mode switching and disabled mode passed offscreen');
} finally {
    rmSync(directory, { recursive: true, force: true });
}
