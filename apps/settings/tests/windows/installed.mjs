import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,copyFileSync,cpSync,readFileSync,writeFileSync,rmSync,existsSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const binary=resolve(process.argv[2]);
const gtkModule=resolve(process.argv[3]);
const root=mkdtempSync(join(tmpdir(),'kos-window-install-'));
const repo=fileURLToPath(new URL('../../../..',import.meta.url));
try {
    const prefix=join(root,'prefix');
    mkdirSync(join(prefix,'bin'),{recursive:true});
    cpSync(join(repo,'apps/settings'),join(prefix,'share/kos/settings'),{recursive:true});
    cpSync(join(repo,'shared/qml'),join(prefix,'share/shared/qml'),{recursive:true});
    cpSync(join(repo,'shared/Icons'),join(prefix,'share/shared/Icons'),{recursive:true});
    const installed=join(prefix,'bin/kos-settings'); copyFileSync(binary,installed);
    const config=join(root,'config'); mkdirSync(config);
    writeFileSync(join(config,'kwinrc'),'[org.kde.kdecoration2]\nlibrary=third_party\ntheme=original\n');
    // Registered Firefox profiles must sync from embedded resources, without
    // requiring tools or CSS in the installed checkout.
    const firefox=join(root,'firefox-profile'); mkdirSync(join(firefox,'chrome'),{recursive:true});
    const personalCss='/* Firefox personal theme */\n';
    writeFileSync(join(firefox,'chrome/userChrome.css'),personalCss);
    writeFileSync(join(firefox,'user.js'),'');
    mkdirSync(join(config,'kos'));
    writeFileSync(join(config,'kos/firefox-buttons-state.json'),JSON.stringify({profiles:{[firefox]:{
        pref:'false',files:{'user.js':{original:'',existed:true},'chrome/userChrome.css':{original:personalCss,existed:true}}
    }}}));
    const env={...process.env,XDG_CONFIG_HOME:config,XDG_CACHE_HOME:join(root,'cache'),
        GSETTINGS_BACKEND:'keyfile',
        XDG_STATE_HOME:join(root,'state'),KOS_SHELL_DIR:join(root,'no-session'),
        DBUS_SESSION_BUS_ADDRESS:'unix:path=/nonexistent-kos-test-bus',
        QT_FORCE_STDERR_LOGGING:'1',QT_QPA_PLATFORM:'offscreen',QT_QUICK_BACKEND:'software'};
    function run(flag, expected=0) {
        const r=spawnSync(installed,[flag],{env,encoding:'utf8',timeout:10000});
        assert.equal(r.status,expected,r.stdout+r.stderr);
        return r.stdout+r.stderr;
    }
    env.XDG_CONFIG_HOME=join(root,'missing-module-config');
    mkdirSync(env.XDG_CONFIG_HOME);
    assert.match(run('--install-window-defaults',1),/GTK detection module is missing/);
    env.XDG_CONFIG_HOME=config;
    const installedModule=join(prefix,'lib/gtk-3.0/modules/libkos-gtk-window-controls.so');
    mkdirSync(join(prefix,'lib/gtk-3.0/modules'),{recursive:true});
    copyFileSync(gtkModule,installedModule);
    run('--install-window-defaults');
    const startup=join(config,'plasma-workspace/env/kos-gtk-window-controls.sh');
    assert.ok(readFileSync(startup,'utf8').includes(installedModule));
    run('--install-window-defaults'); // Existing integration state upgrades without an app list.
    assert.ok(readFileSync(startup,'utf8').includes(installedModule));
    assert.match(readFileSync(join(config,'kwinrc'),'utf8'),/library=kos_decoration/);
    assert.match(readFileSync(join(config,'gtk-3.0/gtk.css'),'utf8'),/kos_native_controls/);
    assert.match(readFileSync(join(config,'gtk-4.0/gtk.css'),'utf8'),/#28c840/);
    assert.match(readFileSync(join(firefox,'chrome/userChrome.css'),'utf8'),/NextKde Firefox buttons: begin/);
    assert.match(readFileSync(join(firefox,'user.js'),'utf8'),/legacyUserProfileCustomizations.stylesheets/);
    run('--restore-window-defaults');
    assert.equal(existsSync(startup),false);
    assert.equal(readFileSync(join(firefox,'chrome/userChrome.css'),'utf8'),personalCss);
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
