import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../../shell/desktop/modules/dock/DockIcon.qml', import.meta.url), 'utf8');
const start = source.indexOf('function windowAnimationTarget()');
const end = source.indexOf('\n    Component.onCompleted:', start);
const targetFor = new Function('icon', 'iconRenderer', `return (${source.slice(start, end).trim()})();`);
for (const edge of ['bottom', 'left', 'right']) {
    for (const scale of [1, 1.2, 1.5]) {
        const size = 44;
        const lift = scale === 1 ? 0 : -8;
        const rotate = edge === 'bottom' ? ([x, y]) => [x, y]
            : ([x, y]) => [-y, x];
        const point = (x, y, zoom, offset) => {
            const [rx, ry] = rotate([(x - size / 2) * zoom, (y - size / 2) * zoom + offset]);
            return { x: 300 + rx, y: 120 + ry };
        };
        const icon = { visible: true, appId: 'probe', iconSize: size, iconSource: 'image://icon/probe',
            animationWindowId: 'window', surfaceOriginX: -1600, surfaceOriginY: 900,
            dockEdge: edge, targetScreen: { name: 'probe-output' },
            x: 0, y: 0, width: size, height: size,
            parent: { mapToItem: (_root, x, y) => point(x, y, 1, 0) } };
        const renderer = { width: size, height: size,
            mapToItem: (_root, x, y) => point(x, y, scale, lift) };
        const result = targetFor(icon, renderer);
        const [cx, cy] = rotate([0, lift]);
        assert.ok(Math.abs(result.x + result.width / 2 - (-1300 + cx)) < 1e-8);
        assert.ok(Math.abs(result.y + result.height / 2 - (1020 + cy)) < 1e-8);
        assert.ok(Math.abs(result.width - size * scale) < 1e-8);
        assert.ok(Math.abs(result.height - size * scale) < 1e-8);
    }
}
console.log('Dock artwork target checks passed: hover lift/scale, side rotation, negative output origin');
