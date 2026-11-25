import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import vm from 'node:vm';
import * as Family from '../../shell/desktop/modules/dock/WindowFamily.mjs';
import * as Identity from '../../shell/desktop/modules/dock/ProcessIdentity.mjs';
import * as StageGroups from '../../shell/desktop/modules/stage/stage-groups.mjs';

const stageSource = readFileSync(new URL('../../shell/desktop/modules/stage/StageSidebarWindow.qml', import.meta.url), 'utf8');
const serviceSource = readFileSync(new URL('../../shell/desktop/modules/dock/WindowService.qml', import.meta.url), 'utf8');
const bridgeSource = readFileSync(new URL('../../kwin/window-bridge.js', import.meta.url), 'utf8');
function functions(source, names) {
    return names.map(name => {
        const match = source.match(new RegExp(`^    function ${name}\\([^]*?^    }`, 'm'));
        assert.ok(match, name);
        return match[0].replace(/: (?:string|bool)(?=[,) {])/g, '');
    }).join('\n');
}
function record(id, pid, app, extra = {}) {
    return { windowId:id, handleId:'handle-'+id, pid,
        identity:{desktopId:app, rawAppId:app, hasDesktopEntry:false},
        toplevel:{minimized:false},desktopIds:['desk'],onAllDesktops:false, ...extra };
}
function node(pid, ppid, exe, stamp = String(pid * 10)) {
    return {pid,ppid,exe,startTime:stamp};
}
function fixture() {
    const main=record('main',100,'org.example.Editor.desktop');
    main.identity.hasDesktopEntry=true;
    const helper=record('helper',200,'org.example.Preview');
    const other=record('other',300,'org.example.Browser.desktop');
    other.identity.hasDesktopEntry=true;
    const mainProc=node(100,10,'/opt/example-editor/bin/editor');
    const chain={100:[mainProc],200:[node(200,150,'/opt/example-editor/helpers/preview'),
        node(150,100,'/opt/example-editor/runtime/worker'),mainProc],
        300:[node(300,10,'/opt/browser/browser')]};
    return {main,helper,other,records:[main,helper,other],chain};
}

test('explicit multi-level parents override distinct application identities',()=>{
    const {main,helper,other,records}=fixture();
    helper.parentHandleId=main.handleId;
    other.parentHandleId=helper.handleId;
    Family.resolveFamilies(records,{100:[],200:[],300:[]});
    assert.equal(other.familyKey,main.familyKey);
    assert.equal(other.ownerWindowId,'main');
    assert.equal(helper.familyReason,'transient');
    assert.equal(other.identity.desktopId,'org.example.Browser.desktop');
});
test('generic cross-process helper inherits its nearest application owner',()=>{
    const f=fixture(); Family.resolveFamilies(f.records,f.chain);
    assert.equal(f.helper.familyKey,f.main.familyKey);
    assert.equal(f.helper.familyReason,'process');
    assert.equal(f.helper.ownerWindowId,'main');
    assert.notEqual(f.other.familyKey,f.main.familyKey);
    assert.equal(StageGroups.groupRecords(f.records).length,2);
});
test('independent desktop entry is a process-ownership boundary',()=>{
    const f=fixture(); f.helper.identity.hasDesktopEntry=true;
    Family.resolveFamilies(f.records,f.chain);
    assert.notEqual(f.helper.familyKey,f.main.familyKey);
});
test('hidden helper desktop entries require ancestry AND private application origin',()=>{
    const f=fixture();
    f.helper.identity.hasDesktopEntry=true;
    f.helper.identity.desktopEntryNoDisplay=true;
    Family.resolveFamilies(f.records,f.chain);
    assert.equal(f.helper.familyKey,f.main.familyKey);
    f.chain[200][0].exe='/opt/independent-viewer/viewer';
    Family.resolveFamilies(f.records,f.chain);
    assert.notEqual(f.helper.familyKey,f.main.familyKey);
});
test('external programs and shared runtime directories are not application evidence',()=>{
    for(const [parent,child] of [
        ['/usr/bin/terminal','/usr/bin/tool'],
        ['/usr/lib/electron/electron','/usr/lib/electron/electron'],
        ['/opt/terminal/bin/terminal','/opt/editor/editor'],
        ['/home/alex/Downloads/editor','/home/alex/Downloads/helper'],
        ['/opt/editor/editor','/opt/editor-other/helper'],
    ]) {
        const f=fixture(); f.chain[100][0].exe=parent; f.chain[200][0].exe=child;
        Family.resolveFamilies(f.records,f.chain);
        assert.notEqual(f.helper.familyKey,f.main.familyKey,parent+' / '+child);
    }
});
test('private portable and AppImage directories can supply ownership evidence',()=>{
    for(const root of ['/home/alex/Applications/Editor','/tmp/.mount_EditorXYZ','/usr/lib/example-editor']) {
        assert.equal(Family.sharesApplicationDirectory({exe:root+'/helpers/preview'},
            {exe:root+'/editor'}),true);
    }
});
test('PID reuse, ambiguous owners and missing parents do not inherit stale ownership',()=>{
    const f=fixture();
    f.chain[200]=structuredClone(f.chain[200]);
    f.chain[200].at(-1).startTime='old-process';
    Family.resolveFamilies(f.records,f.chain);
    assert.notEqual(f.helper.familyKey,f.main.familyKey);
    const g=fixture(); g.records.push(record('other-root',100,'different-app'));
    Family.resolveFamilies(g.records,g.chain);
    assert.notEqual(g.helper.familyKey,g.main.familyKey);
    Family.resolveFamilies([g.helper],g.chain);
    assert.equal(g.helper.ownerWindowId,'');
    assert.equal(g.helper.familyKey,g.helper.identity.desktopId);
});
test('malformed explicit parent cycles remain bounded and independent',()=>{
    const f=fixture(); f.main.parentHandleId=f.helper.handleId; f.helper.parentHandleId=f.main.handleId;
    Family.resolveFamilies(f.records,f.chain);
    assert.notEqual(f.main.familyKey,f.helper.familyKey);
});
test('unresolved process evidence defers demotion; failed evidence releases it',()=>{
    const f=fixture(); Family.resolveFamilies(f.records,{});
    assert.equal(StageGroups.canAutoDemote(f.main,f.helper),false);
    Family.resolveFamilies(f.records,{100:[],200:[],300:[]});
    assert.equal(f.helper.familyPending,false);
    assert.equal(StageGroups.canAutoDemote(f.main,f.helper),true);
});
test('new helper inherits an existing manual group; manually minimized siblings keep a card',()=>{
    const f=fixture(); Family.resolveFamilies(f.records,f.chain);
    const overrides={[f.main.handleId]:'manual-group'};
    assert.equal(StageGroups.groupKeyOf(f.helper,overrides),'manual-group');
    assert.equal(StageGroups.canAutoDemote(f.main,f.helper,overrides),false);
    f.main.toplevel.minimized=true;
    const cards=StageGroups.groupRecords(f.records,{requireMinimized:true,
        excludeKey:f.helper.familyKey,excludeKeepMinimized:true});
    assert.deepEqual(cards[0].wins.map(w=>w.windowId),['main']);
});
test('real process probe preserves identity output and stamps the live ancestry',()=>{
    const command=Family.probeCommand(process.pid,Identity.probeCommand(process.pid));
    const result=spawnSync(command[0],command.slice(1),{encoding:'utf8',timeout:1500});
    assert.equal(result.status,0,result.stderr);
    const chain=Family.parseProcessProbe(result.stdout,process.pid);
    assert.equal(chain[0].pid,process.pid);
    assert.equal(chain[0].ppid,process.ppid);
    assert.match(chain[0].startTime,/^\d+$/);
    assert.deepEqual(Identity.parseProbeOutput(result.stdout),
        Identity.parseProbeOutput(result.stdout.split('\n').slice(0,3).join('\n')));
    assert.deepEqual(Family.parseProcessProbe(result.stdout,process.pid+1),[]);
    assert.deepEqual(Family.parseProcessProbe(result.stdout.replace('KOS_WINDOW_ANCESTRY_END\n','KOS_WINDOW_ANCESTRY_END\n999'),process.pid),[]);
    assert.deepEqual(Family.parseProcessProbe('',process.pid),[]);
});

function stageContext(records,active='helper') {
    const calls={capture:[],minimize:[],swaps:[],reset:[]};
    const timer={stop(){},restart(){}};
    const root={open:true,_mergeOverrides:{},_lastDeskToggleAt:0,
        deskCollectedIds:[],_pendingMinimize:[],_pendingMinimizeAutomatic:true,
        _prevActiveId:'main',_captureThenMinTimer:timer,_minimizeDispatchTimer:timer,
        _deskHoldActive:false,_engageQueue:[],_lastDispatchedKey:'',_lastDispatchedAt:0,
        _groupOrder:[],_pendingSwaps:[],_engageDispatchTimer:timer,
        _idsOf:JSON.parse,_resetEngaging:key=>calls.reset.push(key),_markEngagingByIds(){}};
    const ws={records,stageActiveWindowId:active,currentDesktopId:'desk',
        windowById:id=>records.find(r=>r.windowId===id),requestThumbnail(){},
        minimizeGroup:(ids,value,automatic)=>calls.minimize.push({ids:Array.from(ids),value,automatic}),
        engageSwap:(ids,focusId,minimizeIds)=>calls.swaps.push({ids:Array.from(ids),focusId,minimizeIds:Array.from(minimizeIds)}),
        minimizeWindow(){}};
    const context=vm.createContext({root,WindowService:ws,StageGroups,open:true,
        StageModeService:{enabled:true},StageConfigService:{autoMinimize:true},
        _deskFocusYieldMs:0,_engagingDispatch:false,console:{info(){}},
        captureAndDemote:ids=>calls.capture.push(Array.from(ids)),
        _cancelPendingDemote(){},publishSimulatedLayout(){}});
    const names=['_effKey','_appOf','hasWindowId','_demoteGroupIds',
        '_validatedPendingMinimize','_dispatchPendingMinimize',
        'applyAutoMinimize','activateWithSwap','engageFromActivation','_dispatchNextEngage'];
    vm.runInContext(functions(stageSource,names),context);
    for(const name of names)root[name]=context[name];
    return {context,root,ws,calls};
}
test('production activation and automatic collection preserve main + helper',()=>{
    const f=fixture(); Family.resolveFamilies(f.records,f.chain);
    const s=stageContext(f.records);
    s.root.engageFromActivation(); assert.deepEqual(s.calls.capture,[]);
    s.ws.stageActiveWindowId='main';
    s.root.activateWithSwap('helper'); assert.deepEqual(s.calls.capture,[]);
    s.ws.stageActiveWindowId='helper';
    s.root.applyAutoMinimize(); assert.deepEqual(s.calls.capture,[['other']]);
    s.calls.capture=[]; s.root._prevActiveId='helper'; s.ws.stageActiveWindowId='other';
    s.root.engageFromActivation(); assert.deepEqual(s.calls.capture,[['main','helper']]);
});
test('production pending queue rechecks ownership and focus at dispatch',()=>{
    const f=fixture(); Family.resolveFamilies(f.records,f.chain);
    const s=stageContext(f.records);
    s.root._pendingMinimize=['main','other'];
    s.root._dispatchPendingMinimize();
    assert.deepEqual(s.calls.minimize,[{ids:['other'],value:true,automatic:true}]);
    s.calls.minimize=[]; s.root._pendingMinimize=['main','helper'];
    f.helper.familyPending=true;
    s.root._dispatchPendingMinimize(); assert.deepEqual(s.calls.minimize,[]);
    s.root._pendingMinimize=['main','helper']; s.root._pendingMinimizeAutomatic=false;
    s.root._dispatchPendingMinimize();
    assert.deepEqual(s.calls.minimize,[{ids:['main','helper'],value:true,automatic:false}]);
});
test('queued group activation refreshes membership after family resolution',()=>{
    const f=fixture(); Family.resolveFamilies(f.records,f.chain);
    const s=stageContext(f.records,'other');
    s.root._engageQueue=[{targetId:'helper',appKey:'old-helper-key',idsJson:'["helper"]'}];
    s.root._dispatchNextEngage();
    assert.deepEqual(s.calls.swaps,[{ids:['main','helper'],focusId:'helper',minimizeIds:['other']}]);
    assert.deepEqual(s.calls.reset,['old-helper-key']);
});
test('process cache generation follows handles, discarding replaced and late processes',()=>{
    const svc={_processScopesByPid:{},_processHintsByPid:{},_processFamilyByPid:{},_processProbeByPid:{}};
    const context=vm.createContext({svc});
    vm.runInContext(functions(serviceSource,['_prepareProcessScopes']),context);
    const prepare=context._prepareProcessScopes;
    prepare([{pid:100,id:'old'}],true);
    const oldToken=svc._processScopesByPid[100].token;
    svc._processHintsByPid[100]=['old']; svc._processFamilyByPid[100]=[node(100,1,'/opt/old/main')];
    let killed=false,destroyed=false;
    svc._processProbeByPid[100]={running:true,signal(){killed=true;},destroy(){destroyed=true;}};
    prepare([{pid:100,id:'old'},{pid:100,id:'sibling'}],true);
    assert.equal(svc._processScopesByPid[100].token,oldToken);
    prepare([{pid:100,id:'replacement'}],true);
    assert.notEqual(svc._processScopesByPid[100].token,oldToken);
    assert.equal(svc._processFamilyByPid[100],undefined);
    assert.equal(svc._processHintsByPid[100],undefined);
    assert.ok(killed && destroyed);
    prepare([],true); assert.deepEqual(Object.keys(svc._processScopesByPid),[]);
});

function bridgeContext() {
    const c=vm.createContext({workspace:{activeWindow:null},calls:[],
        print(){},publishAction:(command,found)=>c.calls.push({found}),
        publishSnapshotNow:()=>{},findWindow:id=>c.windows.find(w=>w.internalId===id),windows:[]});
    for(const name of ['normalizeId','windowId','propertyValue','includeWindow','trackedParentId','handleCommand']) {
        const m=bridgeSource.match(new RegExp(`^function ${name}\\([^]*?^}`, 'm'));
        assert.ok(m,name); vm.runInContext(m[0],c);
    }
    return c;
}
test('bridge resolves normal children and filtered dialog chains, with cycle protection',()=>{
    const c=bridgeContext();
    const main={internalId:'main',pid:1,normalWindow:true};
    const dialog={internalId:'dialog',transientFor:main,normalWindow:false};
    const child={internalId:'child',transientFor:dialog,normalWindow:true};
    assert.equal(c.trackedParentId(child),'main');
    assert.equal(c.trackedParentId(dialog),'main');
    dialog.transientFor=child; assert.equal(c.trackedParentId(child),'');
});
test('bridge drops stale automatic batches and preserves explicit desktop collection',()=>{
    const c=bridgeContext(); const main={internalId:'main',minimized:false};
    c.windows=[main]; c.workspace.activeWindow={internalId:'new-focus'};
    c.handleCommand(JSON.stringify({action:'minimize-group',ids:['main'],value:true,expectedActiveId:'old-focus'}));
    assert.equal(main.minimized,false); assert.equal(c.calls.at(-1).found,false);
    c.handleCommand(JSON.stringify({action:'minimize-group',ids:['main'],value:true}));
    assert.equal(main.minimized,true);
});
