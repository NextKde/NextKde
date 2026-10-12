const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(__dirname + '/../cover.qml', 'utf8');
const fn = source.slice(source.indexOf('    function requestReveal('), source.indexOf('    NumberAnimation { id: fade;'));
const events = [];
const ctx = {revealing:false, state:{session:'a'.repeat(32),hash:'b'.repeat(64),version:'v1',fit:'crop'},
 Quickshell:{screens:[{name:'B'},{name:'A'}]}, record:x=>events.push(x),fade:{start(){events.push('fade');}}};
ctx.root = ctx;
vm.createContext(ctx);vm.runInContext(fn,ctx);
const good = {session:ctx.state.session,hash:ctx.state.hash,version:'v1',fit:'crop',outputs:['A','B']};
for (const change of [{session:'c'.repeat(32)},{hash:'d'.repeat(64)},{version:'old'},{fit:'fit'},{outputs:['A']}])
 assert.equal(ctx.requestReveal(JSON.stringify({...good,...change})), 'rejected');
for (const payload of ['invalid','null','{}']) assert.equal(ctx.requestReveal(payload),'rejected');
assert.ok(!events.includes('fade'));
assert.equal(ctx.requestReveal(JSON.stringify(good)),'accepted');
assert.equal(ctx.requestReveal(JSON.stringify(good)),'rejected');
assert.equal(events.filter(x=>x==='fade').length,1);
console.log('PASS T11 stale/duplicate/session/hash/fit/output protocol rejection');
const service = fs.readFileSync(__dirname + '/../../../shell/desktop/modules/common/SessionEntryService.qml', 'utf8');
const clear = service.slice(service.indexOf('    function clearPresentation('), service.indexOf('    function record('));
const selection = fs.readFileSync(__dirname + '/../../../shell/desktop/modules/wallpaper/WallpaperService.qml', 'utf8');
const choose = selection.slice(selection.indexOf('    function chooseImage('),selection.indexOf('    function chooseTheme('));
const state = {defaultBackground:true,sessionImage:'',imageMatches:false,verificationKey:'',frames:{},
 localPath:x=>x,takeoverPending:false,config:{mode:'image',image:'/same.png',takeoverEnabled:true,slideshowEnabled:false,sync(){}},
 WallpaperColorSource:{preferredWallpaperUrl:'/same.png'}};
state.presentationChangeRequested = ()=>state.clearPresentation();
vm.createContext(state);vm.runInContext(clear+choose,state);
assert.equal(state.chooseImage('/same.png',true),true);
assert.equal(state.defaultBackground,false,'same-image user selection clears default cover');
console.log('PASS T11 explicit same-image selection releases default presentation');
const previewHandler = service.match(/property Connections previewChanges:[\s\S]*?function onActiveChanged\(\) \{([\s\S]*?)\n        \}/)[1];
state.root = state;
state.WallpaperPreviewService = {active:true};
state.released = false; state.sessionImage = 'verified'; state.defaultBackground = true;
vm.runInContext(previewHandler,state);
assert.equal(state.sessionImage,'verified','preview cannot bypass pending entry gate');
state.released = true;
vm.runInContext(previewHandler,state);
assert.equal(state.sessionImage,''); assert.equal(state.defaultBackground,false);
assert.equal(state.imageMatches,false);
console.log('PASS T12 daily preview releases static presentation after entry');
const gate = service.slice(service.indexOf('    function check()'), service.indexOf('    function release('));
const ready = {pending:true,defaultBackground:true,imageMatches:false,essentials:{dock:true,bar:true},
 ConfigService:{ready:true},AppearanceConfigService:{ready:true,barIntegratedWithDock:false},
 WindowService:{providerReady:false},Quickshell:{screens:[{name:'A'}]},handoff:{session:'s',hash:'',version:'default',fit:'crop',outputs:['A']},
 frames:{A:true},coverPath:'/fixture/cover.qml',reveal:{running:false}};
vm.createContext(ready); vm.runInContext(gate,ready);
ready.check(); assert.equal(ready.reveal.running,false,'provider initial snapshot must finish');
ready.WindowService.providerReady=true; ready.essentials.dock=false;
ready.check(); assert.equal(ready.reveal.running,false,'Dock needs its ready frame');
ready.essentials.dock=true; ready.check(); assert.equal(ready.reveal.running,true);
console.log('PASS desktop reveal waits for provider and essential frames');
