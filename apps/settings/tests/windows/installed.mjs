import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,copyFileSync,cpSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const binary=resolve(process.argv[2]);
const root=mkdtempSync(join(tmpdir(),'kos-window-install-'));
const repo=fileURLToPath(new URL('../../../..',import.meta.url));
try {
    const prefix=join(root,'prefix');
    mkdirSync(join(prefix,'bin'),{recursive:true});
    cpSync(join(repo,'apps/settings'),join(prefix,'share/kos/settings'),{recursive:true});
    cpSync(join(repo,'shared/qml'),join(prefix,'share/shared/qml'),{recursive:true});
    const installed=join(prefix,'bin/kos-settings'); copyFileSync(binary,installed);
    const config=join(root,'config'); mkdirSync(config);
    writeFileSync(join(config,'kwinrc'),'[org.kde.kdecoration2]\nlibrary=third_party\ntheme=original\n');
    const env={...process.env,XDG_CONFIG_HOME:config,XDG_CACHE_HOME:join(root,'cache'),
        XDG_STATE_HOME:join(root,'state'),KOS_SHELL_DIR:join(root,'no-session'),
        DBUS_SESSION_BUS_ADDRESS:'unix:path=/nonexistent-kos-test-bus',
        QT_FORCE_STDERR_LOGGING:'1',QT_QPA_PLATFORM:'offscreen',QT_QUICK_BACKEND:'software'};
    function run(flag, expected=0) {
        const r=spawnSync(installed,[flag],{env,encoding:'utf8',timeout:10000});
        assert.equal(r.status,expected,r.stdout+r.stderr);
        return r.stdout+r.stderr;
    }
    run('--install-window-defaults');
    assert.match(readFileSync(join(config,'kwinrc'),'utf8'),/library=kos_decoration/);
    run('--restore-window-defaults');
    run('--install-window-defaults');
    assert.match(readFileSync(join(config,'kwinrc'),'utf8'),/library=third_party/);
    assert.equal(JSON.parse(readFileSync(join(config,'kos/window-appearance.json'),'utf8')).enabled,false);
    assert.match(run('--smoke-test-windows'),/installed copy/);
    // A main window that loads successfully while its page is absent must fail.
    writeFileSync(join(prefix,'share/kos/settings/main.qml'),
        'import QtQuick\nimport QtQuick.Controls\nApplicationWindow {visible:true; width:600; height:500; property int currentPage:0}\n');
    assert.match(run('--smoke-test-windows',1),/did not instantiate/);
    console.log('Installed window defaults, upgrade, restoration and page validation passed');
} finally {rmSync(root,{recursive:true,force:true});}
