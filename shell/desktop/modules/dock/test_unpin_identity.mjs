import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const source=readFileSync(new URL('DockModelService.qml',import.meta.url),'utf8');
const unpin=source.match(/^    function unpinApp\(appId\) \{[^]*?^    \}/m)[0];
let refreshes=0,saves=0;
const config={dockItems:[{type:'app',appId:'code.desktop'},{type:'app',appId:'Code'},
    {type:'app',appId:'org.kde.dolphin.desktop'},{type:'separator'}],
    setDockItems(items){this.dockItems=items;return true;},scheduleSave(){saves++;}};
const normalize=id=>['Code','code.desktop','com.microsoft.VSCode.desktop'].includes(id)?'vscode':id;
const context=vm.createContext({ConfigService:config,
    AppIdentityService:{sameApp:(a,b)=>normalize(a)===normalize(b)},
    svc:{_refreshPresentation(){refreshes++;}}});
vm.runInContext(unpin,context);
context.unpinApp('com.microsoft.VSCode.desktop');
assert.deepEqual(Array.from(config.dockItems,x=>x.appId||x.type),['org.kde.dolphin.desktop','separator']);
assert.equal(saves,1);assert.equal(refreshes,1);
context.unpinApp('missing.desktop');
assert.equal(saves,1);assert.equal(refreshes,1);
console.log('Unpin: removes all aliases, preserves unrelated items, saves and refreshes once');
