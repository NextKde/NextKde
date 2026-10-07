import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const source = readFileSync(new URL('./WallpaperImageLayer.qml', import.meta.url), 'utf8');
const functions = source.slice(source.indexOf('    function requestSource()'), source.indexOf('    onSourceChanged:'));
function buffer(path) {
    let value = path;
    return { writes: 0, status: 1, opacity: 1, scale: 1,
        get source() { return value; }, set source(next) { this.writes++; value = next; } };
}
function fixture() {
    const first = buffer('/a.png'), second = buffer('/b.png'), later = [], reports = [];
    const state = { currentImage: first, nextImage: second, effectImage: second,
        source: '/b.png', cleanupFrames: 0, revealProgress: 0.99, previewTarget: false,
        transition: 'left', activeTransition: 'left', useReveal: true,
        Image: {Ready:1, Error:3}, Qt: {callLater: fn => later.push(fn)},
        revealAnimation: {running:false, start() {this.running = true;}, stop() {this.running = false;}},
        revealShader: {progress:0},
        cleanupDelay: {restart() {}, stop() {}},
        switchAnimation: {running:false, start() {this.running = true;}, stop() {this.running = false;}},
        WallpaperService: {transitionSeed:0.4, reportImageFailed() {}},
        // reportSettled 在切片外定义;测试上下文中 targetScreen 为空,其真实
        // 实现会先行 return,这里以桩替代。
        reportSettled() {},
        WallpaperCatalog: {resolvedTransition: value => value},
        reportReady: path => reports.push(path), console };
    Object.defineProperty(state, "transitioning", {get: () => state.switchAnimation.running || state.revealAnimation.running});
    state.root = state;
    vm.createContext(state); vm.runInContext(functions, state);
    const cleanup = source.match(/FrameAnimation \{[\s\S]*?onTriggered: \{([\s\S]*?)\n        \}/)[1];
    vm.runInContext('function frame() {' + cleanup + '}', state);
    return {state, first, second, later, reports};
}
{
    const {state, first, second} = fixture();
    state.promote();
    assert.equal(state.currentImage, second, 'keep the already rendered image object');
    assert.equal(first.writes + second.writes, 0, 'completion must not reload or clear textures');
    assert.equal(second.opacity, 1);
    assert.equal(first.opacity, 0);
    assert.equal(state.effectImage, second, 'keep the final shader frame resident');
    assert.equal(state.cleanupFrames, 0, 'teardown waits for the deferred timer');
    state.cleanupFrames = 4;
    state.frame(); assert.equal(first.source, '/a.png');
    state.frame(); assert.equal(first.source, '');
    assert.equal(state.effectImage, second, 'release old texture separately from effect');
    state.frame(); state.frame();
    assert.equal(state.effectImage, null);
    assert.equal(state.cleanupFrames, 0, 'no ongoing cleanup frames while idle');
    assert.equal(second.source, '/b.png'); assert.equal(second.writes, 0);
}
{
    const {state, first, second, later} = fixture();
    state.switchAnimation.running = true;
    state.source = '/c.png'; state.requestSource();
    state.source = '/a.png'; state.requestSource();
    assert.equal(first.writes + second.writes, 0, 'rapid selection must not interrupt the moving frame');
    state.switchAnimation.running = false; state.promote();
    assert.equal(later.length, 1);
    later.shift()();
    assert.equal(state.nextImage, first);
    assert.equal(state.revealAnimation.running, true);
    assert.equal(first.writes, 0, 'reuse the resident old image when selecting back');
    assert.equal(state.cleanupFrames, 0, 'stale cleanup cannot clear a new transition');
}
{
    const {state, first, second} = fixture();
    state.source = ''; state.switchAnimation.running = true; state.revealAnimation.running = true;
    state.requestSource();
    assert.equal(state.switchAnimation.running, false);
    assert.equal(state.revealAnimation.running, false);
    assert.equal(state.effectImage, null);
    assert.equal(first.source, ''); assert.equal(second.source, '');
}
console.log('wallpaper handoff: resident buffer swap, staggered cleanup and rapid-selection continuity passed');
