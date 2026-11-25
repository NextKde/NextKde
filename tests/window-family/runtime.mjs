import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const dock = new URL('../../shell/desktop/modules/dock/',import.meta.url);
const service = readFileSync(new URL('WindowService.qml',dock),'utf8');
const start=service.indexOf('    property Component _processProbeFactory:');
const end=service.indexOf('    // ── Virtual desktops',start);
assert.ok(start>=0 && end>start);
const directory=mkdtempSync(join(tmpdir(),'kos-window-family-'));
try {
    for(const file of ['WindowFamily.mjs','ProcessIdentity.mjs'])
        copyFileSync(new URL(file,dock),join(directory,file));
    writeFileSync(join(directory,'shell.qml'), `
import QtQuick
import Quickshell
import Quickshell.Io
import "WindowFamily.mjs" as WindowFamily
import "ProcessIdentity.mjs" as ProcessIdentity
Scope {
    id: svc
    property var _processHintsByPid: ({})
    property var _processFamilyByPid: ({})
    property var _processScopesByPid: ({})
    property var _processProbeByPid: ({})
    property int phase: 0
    ${service.slice(start,end)}
    function _scheduleUpdate() {
        const pid = Number(Quickshell.processId)
        if (phase === 0) {
            const ancestry = svc._processFamilyByPid[pid]
            if (!ancestry || ancestry.length === 0 || ancestry[0].pid !== pid) {
                console.error("FAMILY_RUNTIME_FAILURE: missing process evidence")
                Qt.quit(); return
            }
            const parent = {windowId:"parent",handleId:"p",pid:pid,
                identity:{desktopId:"editor",hasDesktopEntry:true}}
            const child = {windowId:"child",handleId:"c",pid:pid,parentHandleId:"p",
                identity:{desktopId:"preview"}}
            WindowFamily.resolveFamilies([parent,child],svc._processFamilyByPid)
            if (child.familyKey !== "editor" || child.familyPending) {
                console.error("FAMILY_RUNTIME_FAILURE: relation did not settle")
                Qt.quit(); return
            }
            // A new handle generation must not keep the old probe/cache.
            const old = svc._processScopesByPid[pid].token
            svc._prepareProcessScopes([{pid:pid,id:"replacement"}],true)
            if (svc._processFamilyByPid[pid] !== undefined
                    || svc._processScopesByPid[pid].token === old) {
                console.error("FAMILY_RUNTIME_FAILURE: stale generation")
                Qt.quit(); return
            }
            phase = 1
            svc._ensureProcessHints(pid)
        } else {
            if (!svc._processFamilyByPid[pid]?.length) {
                console.error("FAMILY_RUNTIME_FAILURE: second probe missing")
                Qt.quit(); return
            }
            svc._prepareProcessScopes([],true)
            console.log("FAMILY_RUNTIME_PASS")
            Qt.quit()
        }
    }
    Component.onCompleted: {
        const pid = Number(Quickshell.processId)
        svc._prepareProcessScopes([{pid:pid,id:"first"}],true)
        svc._ensureProcessHints(pid)
    }
    Timer {
        interval:5000; running:true
        onTriggered: { console.error("FAMILY_RUNTIME_FAILURE: timeout"); Qt.quit() }
    }
}
`);
    const result=spawnSync(process.argv[2] || 'quickshell',['-p',directory],{
        encoding:'utf8',timeout:8000,
        env:{...process.env,QT_QPA_PLATFORM:'offscreen',QT_QUICK_BACKEND:'software',WAYLAND_DISPLAY:'',DISPLAY:''}
    });
    const output=(result.stdout||'')+(result.stderr||'');
    assert.equal(result.error,undefined,output);
    assert.equal(result.status,0,output);
    assert.match(output,/FAMILY_RUNTIME_PASS/);
    assert.doesNotMatch(output,/FAMILY_RUNTIME_FAILURE|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign|ERROR:/);
    console.log('Window ownership: real QML process probes, relation resolution and handle generation passed');
} finally { rmSync(directory,{recursive:true,force:true}); }
