import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const catalog = {};
vm.createContext(catalog);
vm.runInContext(readFileSync(new URL('../../../../shared/qml/foundation/WallpaperCatalog.js', import.meta.url), 'utf8'), catalog);
const source = readFileSync(new URL('./WallpaperService.qml', import.meta.url), 'utf8');
const state = { config: { transition: 'fade', transitionOptionsJson:'{}', sync() {} }, transitionOptions: {} };
vm.createContext(state);
vm.runInContext(source.slice(source.indexOf('    function setTransition('), source.indexOf('    function setSlideshow(')), state);
for (const {id, label} of catalog.transitions) {
    assert.ok(label);
    assert.equal(state.setTransition(id), true, id);
    for (let seed = 0; seed < 1; seed += 0.031) {
        const selected = catalog.resolvedTransition(id, seed);
        assert.ok(catalog.transitions.some(effect => effect.id === selected));
        assert.ok(!['any', 'random'].includes(selected));
        assert.equal(selected, catalog.resolvedTransition(id, seed), 'screens use the same seed');
    }
}
assert.equal(state.setTransition('unknown'), false);
assert.equal(state.setTransitionOptions('null'), false);
assert.equal(state.setTransitionOptions('[]'), false);
assert.equal(state.setTransitionOptions('{"angle":"invalid"}'), false);
assert.equal(state.setTransitionOptions(JSON.stringify(JSON.stringify({angle:999, positionX:-1, waveWidth:0}))), true);
assert.deepEqual(JSON.parse(state.config.transitionOptionsJson), {angle:360, positionX:0, waveWidth:0.02});
console.log('wallpaper transitions: all effect IDs, synchronized random selection and parameter bounds passed');
