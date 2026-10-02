import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
const binary = resolve(process.argv[2]);
const directory = mkdtempSync(join(tmpdir(), 'kos-wallpaper-colors-'));
try {
    mkdirSync(join(directory, 'shell'), {recursive: true});
    mkdirSync(join(directory, 'apps/settings'), {recursive: true});
    writeFileSync(join(directory, 'shell/shell.qml'), 'import QtQuick\nItem {}');
    writeFileSync(join(directory, 'apps/settings/main.qml'), `import QtQuick
Item {
    Component.onCompleted: {
        const invalid = settingsBridge.wallpaperColorImage("not-a-color", "#112233", 90)
        const solid = settingsBridge.wallpaperColorImage("#A8C8F0", "#A8C8F0", 0)
        const gradient = settingsBridge.wallpaperColorImage("#A8C8F0", "#EFC5DE", 45)
        const cached = settingsBridge.wallpaperColorImage("#A8C8F0", "#EFC5DE", 405)
        console.log("COLORS " + JSON.stringify({invalid, solid, gradient, cached}))
    }
}`);
    const result = spawnSync(binary, ['--smoke-test'], {encoding:'utf8', timeout:15000,
        env: {...process.env, QT_FORCE_STDERR_LOGGING:'1', QT_QPA_PLATFORM:'offscreen',
            QT_QUICK_BACKEND:'software', KOS_SHELL_DIR:join(directory, 'shell'),
            XDG_CACHE_HOME:join(directory, 'cache')}});
    assert.equal(result.status, 0, result.stderr);
    const match = result.stderr.match(/COLORS (\{.*\})/);
    assert.ok(match, result.stderr);
    const data = JSON.parse(match[1]);
    assert.equal(data.invalid, '');
    assert.equal(data.gradient, data.cached, 'normalize angles before cache lookup');
    for (const [path, width, height] of [[data.solid,16,16],[data.gradient,1920,1080]]) {
        assert.ok(existsSync(path));
        const bytes = readFileSync(path);
        assert.equal(bytes.toString('hex',0,8), '89504e470d0a1a0a');
        assert.equal(bytes.readUInt32BE(16), width);
        assert.equal(bytes.readUInt32BE(20), height);
    }
    console.log('wallpaper color bridge: validation, PNG generation and cache passed');
} finally { rmSync(directory, {recursive:true, force:true}); }
