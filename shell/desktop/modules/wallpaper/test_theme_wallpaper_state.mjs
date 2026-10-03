import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const source = readFileSync(new URL('./WallpaperService.qml',import.meta.url),'utf8');
const methods = source.slice(source.indexOf('    function isLocalImage('),source.indexOf('    function setTakeoverEnabled('));
const config = {image:'/original.jpg', mode:'image', themeId:'starfield', slideshowEnabled:true,
    takeoverEnabled:false, sync() {}};
const state = {config, takeoverPending:false, transitionSeed:0, readyOutputNames:['DP-1'],
    settledOutputNames:['DP-1'], appliedProxyKey:'original', calls:0,
    Catalog:{theme:id => ['starfield','blackhole','weather'].includes(id) ? {id} : null},
    SpatialWallpaperService:{cancelPreparation() {}},
    AppearanceConfigService:{updateSpatialWallpaperEnabled(value) { assert.equal(value,false); }},
    WallpaperColorSource:{wallpaperUrl:'/original.jpg',preferredWallpaperUrl:''},
    applyPlasmaBackdropIfReady(){ state.calls++; }};
Object.defineProperties(state,{mode:{get(){return config.mode;}},themeId:{get(){return config.themeId;}}});
vm.createContext(state);vm.runInContext(methods,state);
assert.equal(state.chooseTheme('invalid'),false);
assert.equal(config.mode,'image');
assert.equal(state.chooseTheme('blackhole'),true);
assert.equal(config.mode,'theme');assert.equal(config.themeId,'blackhole');
assert.equal(config.image,'/original.jpg','the original image remains available for restore/lockscreen');
assert.equal(config.slideshowEnabled,false);assert.equal(config.takeoverEnabled,true);
assert.equal(state.readyOutputNames.length,0);
state.reportThemeReady('DP-1','weather');assert.equal(state.readyOutputNames.length,0);
state.reportThemeReady('DP-1','blackhole');assert.equal(state.readyOutputNames.length,1);
state.chooseTheme('blackhole');assert.equal(state.readyOutputNames.length,1,'reselecting a ready theme must not stall takeover');
state.chooseImage('/new.jpg',true);
assert.equal(config.mode,'image');assert.equal(config.image,'/new.jpg');
assert.equal(state.readyOutputNames.length,0);
console.log('Theme wallpaper: validation, original-image preservation, readiness, reselection and return to images passed.');
