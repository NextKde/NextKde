import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {copyFileSync, mkdirSync, mkdtempSync, readdirSync, rmSync, symlinkSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const repository = fileURLToPath(new URL('../..', import.meta.url));
const directory = mkdtempSync(join(tmpdir(), 'kos-switcher-content-'));
try {
    copyFileSync(new URL('content.qml', import.meta.url), join(directory, 'shell.qml'));
    symlinkSync(join(repository, 'shell/desktop'), join(directory, 'desktop'));
    mkdirSync(join(directory, 'shared'));
    symlinkSync(join(repository, 'shared/qml'), join(directory, 'shared/qml'));
    symlinkSync(join(repository, 'shared/Icons'), join(directory, 'shared/Icons'));
    mkdirSync(join(directory, 'Kos/Ui'), {recursive: true});
    for (const name of readdirSync(join(repository, 'shared/qml'))) {
        if (name !== 'qmldir')
            symlinkSync(join(repository, 'shared/qml', name), join(directory, 'Kos/Ui', name));
    }
    copyFileSync(join(repository, 'shell/Kos/Ui/qmldir'), join(directory, 'Kos/Ui/qmldir'));
    symlinkSync(join(repository, 'shared/Icons'), join(directory, 'Kos/Icons'));
    const result = spawnSync(process.argv[2] || 'qs', ['-p', directory, '--no-color'], {
        encoding: 'utf8', timeout: 10000,
        env: {...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QUICK_BACKEND: 'software',
            QT_FORCE_STDERR_LOGGING: '1', QS_DISABLE_CRASH_HANDLER: '1',
            XDG_STATE_HOME: join(directory, 'state'), XDG_CONFIG_HOME: join(directory, 'config'),
            KOS_PLATFORM_SOCKET: join(directory, 'absent.sock'),
            KOS_DATA_SOCKET: join(directory, 'absent-data.sock'), WAYLAND_DISPLAY: '', DISPLAY: ''},
    });
    const output = (result.stdout || '') + (result.stderr || '');
    assert.equal(result.error, undefined, output);
    assert.equal(result.status, 0, output);
    assert.doesNotMatch(output, /is not a type|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign/);
    assert.match(output, /SWITCHER_CONTENT_PASS/);
    console.log(output.trim());
} finally {
    rmSync(directory, {recursive: true, force: true});
}
