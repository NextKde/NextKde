import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const catalog = vm.createContext({});
vm.runInContext(readFileSync(new URL('../../../../shared/qml/foundation/WallpaperCatalog.js', import.meta.url), 'utf8'), catalog);

// Exercise the full RGB cube at coarse intervals, including achromatic colors,
// near-black inputs and both extremes of the depth control.
for (let r = 0; r <= 255; r += 17) {
    for (let g = 0; g <= 255; g += 17) {
        for (let b = 0; b <= 255; b += 17) {
            const base = '#' + [r, g, b].map(c => c.toString(16).padStart(2, '0')).join('');
            for (const depth of [0, 0.5, 1, NaN]) {
                const palette = catalog.colorGradient(base, depth);
                for (const color of [palette.start, palette.end, ...(palette.colors || [])])
                    assert.match(color, /^#[0-9A-F]{6}$/);
                assert.notEqual(palette.start, palette.end);
            }
        }
    }
}
for (const base of ['#000000', '#777777', '#FFFFFF']) {
    const palette = catalog.colorGradient(base, 0.5);
    for (const hex of [palette.start, palette.end])
        assert.equal(new Set(hex.slice(1).match(/../g)).size, 1, 'neutral colors must stay neutral');
}
const blue = catalog.colorGradient('#70A0F5', 0.5);
const top = catalog.colorLch(blue.start), bottom = catalog.colorLch(blue.end);
assert.ok(bottom.l - top.l > 0.2, 'blue needs an open, light lower field');
assert.ok(Math.abs(top.h - bottom.h) > 20, 'blue needs visible violet-to-sky hue travel');
console.log('wallpaper palettes: RGB cube, depth extremes, neutrals and blue color separation passed');

assert.equal(blue.colors.length, 3, 'blue needs independent middle and accent colors');
const hues = [blue.start, blue.end, ...blue.colors].map(c => catalog.colorLch(c).h);
assert.ok(Math.max(...hues)-Math.min(...hues) > 90, 'blue palette needs independent violet, blue and cyan hues');

// Similar base swatches must not collapse to near-identical complete presets.
const perceptual = hex => {
    const c = catalog.colorLch(hex), radians = c.h*Math.PI/180;
    return [c.l, c.c*Math.cos(radians), c.c*Math.sin(radians)];
};
const presets = catalog.palettes.filter(palette => palette.colors?.length === 3);
for (let i = 0; i < presets.length; ++i) {
    for (let j = i+1; j < presets.length; ++j) {
        const a = presets[i], b = presets[j];
        const left = [a.start, a.end, ...a.colors].map(perceptual);
        const right = [b.start, b.end, ...b.colors].map(perceptual);
        const distance = left.reduce((sum, color, k) => sum + Math.hypot(
            ...color.map((channel, n) => channel-right[k][n])), 0)/left.length;
        assert.ok(distance > 0.045, `${a.title} and ${b.title} are too similar`);
    }
}
console.log('wallpaper presets: perceptual separation between every preset pair passed');
