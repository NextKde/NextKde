import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const source = readFileSync(new URL('./WallpaperPreviewService.qml', import.meta.url), 'utf8');
const functions = source.slice(source.indexOf('    function parse('), source.indexOf('    property Timer loadingWatchdog:'));
function fixture() {
    const commits = [], slides = [], themes = [];
    const state = {
        active: false, pending: false, presented: false, available: true,
        image: '', mode: 'image', imageCatalog: [], colorCatalog: [], thumbnailCatalog: {}, selectedImages: [],
        errorMessage: '', direction: 1, readyOutputs: [], transitionSeed: 0,
        intervalMinutes: 15, slideshowPlaying: false,
        Catalog: { themes: [{id:"starfield"}, {id:"blackhole"}, {id:"weather"}],
            theme(id) { return this.themes.find(item => item.id === id) || null; } },
        ScreenLifecycle: { usableScreens: [{ name: 'HDMI-1' }, { name: 'DP-1' }] },
        loadingWatchdog: { restart() {}, stop() {} },
        WallpaperService: {
            takeoverPending: false, slideshowImages: [], slideshowIntervalMinutes: 15,
            localPath: value => String(value).startsWith('/') ? String(value) : '',
            chooseImage(path) { commits.push(path); return true; },
            chooseTheme(id) { themes.push(id); return true; },
            setSlideshow(enabled, minutes, images) { slides.push({ enabled, minutes, images: JSON.parse(images) }); return true; },
        },
        // 现行架构:finish 不再直接调 prepareForEnable,而是写配置,由
        // DesktopEnvironment 响应配置变化触发 prepareForEnable。
        ThemePackService: { has: () => false, accent: () => '' },
        AppearanceConfigService: {
            spatialCalls: [],
            updateSpatialWallpaperEnabled(value) { this.spatialCalls.push(value); }
        },
        SpatialWallpaperService: { previewEnabled: false, canceled: 0, started: 0,
            cancelPreparation() { this.canceled++; this.previewEnabled = false; },
            prepareForEnable() { this.started++; } },
    };
    Object.defineProperty(state, 'images', { get() { return this.mode === 'theme' ? ['theme:starfield', 'theme:blackhole', 'theme:weather']
        : this.mode === 'color' ? this.colorCatalog : this.imageCatalog; } });
    state.service = state;
    vm.createContext(state); vm.runInContext(functions, state);
    return { state, commits, slides, themes };
}
const session = { images: ['/a.jpg', '/b.jpg', '/c.jpg'], colors: ['/wallpaper-colors/pink.png'],
    thumbnails: {'/a.jpg': '/cache/a.webp'},
    selectedImages: ['/a.jpg', '/c.jpg'], mode: 'image', intervalMinutes: 30 };
{
    const { state, commits } = fixture();
    assert.equal(state.beginSession('/a.jpg', JSON.stringify(JSON.stringify(session))), true);
    assert.equal(state.thumbnailFor('/a.jpg'), '/cache/a.webp');
    assert.equal(state.thumbnailFor('/b.jpg'), '', 'uncached pictures fall back to the original');
    state.setThumbnails(JSON.stringify({'/a.jpg': '/cache/a.webp', '/b.jpg': '/cache/b.webp', '/foreign.jpg': '/cache/x.webp'}));
    assert.equal(state.thumbnailFor('/b.jpg'), '/cache/b.webp');
    assert.equal(state.thumbnailFor('/foreign.jpg'), '', 'cache paths must belong to the image catalog');
    assert.equal(state.image, '/a.jpg', 'thumbnail updates never replace the actual wallpaper');
    state.imageReady('/stale.jpg', 'HDMI-1');
    assert.equal(state.presented, false);
    state.imageReady('/a.jpg', 'HDMI-1');
    assert.equal(state.presented, false, 'wait for every screen');
    state.imageReady('/a.jpg', 'DP-1');
    assert.equal(state.presented, true);
    state.select(1); assert.equal(state.image, '/b.jpg');
    state.setMode('color'); assert.equal(state.image, '/wallpaper-colors/pink.png');
    state.setMode('image'); assert.equal(state.image, '/a.jpg');
    assert.equal(state.pending, true);
    state.finish(false); assert.equal(state.active, false);
    assert.equal(state.pending, false, 'cancel also works during loading');
    assert.deepEqual(commits, [], 'browsing and cancel never persist');
}
{
    const { state, commits, slides } = fixture();
    state.beginSession('/a.jpg', JSON.stringify({...session, mode: 'slideshow'}));
    assert.equal(state.slideshowPlaying, true);
    assert.equal(state.thumbnailFor('/a.jpg'), '/cache/a.webp', 'slideshow reuses the same thumbnail cache');
    state.move(1); assert.equal(state.image, '/c.jpg', 'only selected pictures play');
    state.toggleSelected('/c.jpg');
    state.finish(true); assert.equal(state.active, true, 'cannot apply one-picture slideshow');
    state.selectAll(); assert.equal(state.selectedImages.length, 3);
    state.pending = false;
    state.finish(true); assert.equal(state.active, false);
    assert.equal(slides[0].minutes, 30);
    assert.deepEqual(slides[0].images, session.images);
    assert.deepEqual(commits, [], 'apply slideshow uses its own commit path');
}
{
    const { state, commits } = fixture();
    state.begin('/a.jpg', '["/a.jpg"]');
    state.imageReady('/a.jpg', 'HDMI-1'); state.imageReady('/a.jpg', 'DP-1');
    state.finish(true);
    assert.deepEqual(commits, ['/a.jpg']);
    state.begin('/broken.jpg', 'null'); state.imageFailed('/broken.jpg');
    assert.equal(state.active, false); assert.ok(state.errorMessage);
    state.available = false; assert.equal(state.begin('/a.jpg', '[]'), false);
}
console.log('wallpaper preview: catalogs, selection, multi-output readiness and rollback passed');

{
    const { state, commits } = fixture();
    state.beginSession('/a.jpg', JSON.stringify(session));
    assert.equal(state.chooseColor('/wallpaper-colors/custom.png'), true);
    assert.equal(state.image, '/wallpaper-colors/custom.png');
    assert.equal(state.mode, 'color');
    assert.ok(state.colorCatalog.includes(state.image));
    assert.deepEqual(commits, [], 'color changes remain a preview draft');
    state.finish(false);
    assert.deepEqual(commits, [], 'cancel keeps the applied wallpaper');
}

{
    const { state, commits } = fixture();
    state.beginSession('/a.jpg', JSON.stringify(session));
    state.pending = false;
    state.SpatialWallpaperService.previewEnabled = true;
    state.finish(false);
    assert.equal(state.SpatialWallpaperService.previewEnabled, false, 'closing discards spatial preview');
    assert.equal(state.SpatialWallpaperService.started, 0, 'cancel cannot activate a wallpaper');
    assert.deepEqual(commits, []);
}
{
    const { state, commits } = fixture();
    state.beginSession('/a.jpg', JSON.stringify(session));
    state.pending = false;
    state.SpatialWallpaperService.previewEnabled = true;
    state.finish(true);
    assert.deepEqual(commits, ['/a.jpg']);
    assert.deepEqual(state.AppearanceConfigService.spatialCalls, [true],
        'apply enables the spatial setting that triggers prepareForEnable downstream');
}

{
    const { state, commits, themes } = fixture();
    assert.equal(state.beginSession('theme:invalid', JSON.stringify({...session, mode:'theme'})), false);
    assert.equal(state.beginSession('theme:blackhole', JSON.stringify({...session, mode:'theme'})), true);
    state.imageReady('theme:blackhole', 'HDMI-1');
    assert.equal(state.pending, true, 'theme also waits for every output');
    state.imageReady('theme:blackhole', 'DP-1');
    assert.equal(state.pending, false);
    state.finish(false);
    assert.deepEqual(themes, [], 'cancel never commits a theme');
    assert.deepEqual(commits, []);
    state.beginSession('theme:weather', JSON.stringify({...session, mode:'theme'}));
    state.imageReady('theme:weather', 'HDMI-1'); state.imageReady('theme:weather', 'DP-1');
    state.finish(true);
    assert.deepEqual(themes, ['weather']);
    assert.deepEqual(commits, [], 'theme IDs never enter the image pipeline');
}
