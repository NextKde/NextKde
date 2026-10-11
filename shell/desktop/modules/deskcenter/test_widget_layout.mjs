import assert from "node:assert/strict";
import { packWidgets, packWidgetSides, packPixelSides, sizeOrder, spanFor } from "./WidgetLayout.mjs";

const ids = ["clock", "weather", "calendar", "todo", "system", "activity", "music"];

for (const id of ids) {
    for (const size of sizeOrder) {
        const [columns, rows] = spanFor(id, size);
        assert.ok(columns >= 1 && columns <= 3, `${id}/${size} columns`);
        assert.ok(rows >= 1 && rows <= 2, `${id}/${size} rows`);
    }
}

for (const size of sizeOrder) {
    const definitions = ids.map((id, index) => {
        const [columns, rows] = spanFor(id, size);
        return { id, columns, rows, priority: 100 - index };
    });
    const placements = packWidgets(definitions, 4, 8);
    assert.equal(placements.length, ids.length, `${size} widgets all fit`);
    const cells = new Set();
    for (const placement of placements) {
        for (let row = placement.row; row < placement.row + placement.rows; row++) {
            for (let column = placement.column;
                 column < placement.column + placement.columns; column++) {
                assert.ok(column < 4 && row < 8, `${placement.id} remains in bounds`);
                const key = `${column}:${row}`;
                assert.ok(!cells.has(key), `${placement.id} does not overlap`);
                cells.add(key);
            }
        }
    }
}

const constrained = ids.map((id, index) => {
    const [columns, rows] = spanFor(id, "large");
    return { id, columns, rows, priority: 100 - index };
});
const visible = packWidgets(constrained, 4, 3);
assert.ok(visible.length < ids.length, "short screens drop lower priority widgets");
assert.equal(visible[0].id, "clock", "highest priority widget remains first");

console.log("DeskCenter widget layout: all size and packing tests passed");

for (const size of sizeOrder) {
    const [columns, rows] = spanFor("notifications", size);
    const definitions = [
        { id: "music", columns: 1, rows: 1, priority: 10, side: "left" },
        { id: "clock", columns: 1, rows: 1, priority: 100, side: "left" },
        { id: "notifications", columns, rows, priority: 85, side: "right" },
    ];
    const placed = packWidgetSides(definitions, 4, columns, 3);
    assert.deepEqual(placed.map(p => p.id), ["music", "clock", "notifications"], "explicit order overrides priorities");
    assert.equal(placed.find(p => p.id === "notifications").side, "right");
    const cells = new Set();
    for (const p of placed) {
        const width = p.side === "right" ? columns : 4;
        assert.ok(p.column + p.columns <= width && p.row + p.rows <= 3);
        for (let y = p.row; y < p.row + p.rows; y++)
            for (let x = p.column; x < p.column + p.columns; x++) {
                const key = `${p.side}:${x}:${y}`;
                assert.ok(!cells.has(key), "side grids do not overlap");
                cells.add(key);
            }
    }
}
console.log("DeskCenter left/right layout: persisted order and all notification sizes passed");

const pixelWidgets = [
    {id: "clock", side: "left", width: 181.4, height: 181.4},
    {id: "weather", side: "left", width: 564.2, height: 181.4},
    {id: "notifications", side: "right", width: 372.8, height: 751, topOffset: 240},
    {id: "music", side: "right", width: 180, height: 200},
];
const pixelPlaced = packPixelSides(pixelWidgets, 755.6, 372.8, 1048, 10);
assert.equal(pixelPlaced.length, 4, "automatic cards fit around a lowered notification panel");
const notification = pixelPlaced.find(p => p.id === "notifications");
assert.equal(notification.y, 240);
assert.equal(notification.height, 751, "free height is preserved without snapping to rows");
assert.equal(notification.width, 372.8, "fractional width stays continuous");
for (const a of pixelPlaced) {
    assert.ok(a.y >= 0 && a.y + a.height <= 1048);
    assert.ok(a.x >= 0 && a.x + a.width <= (a.side === "right" ? 372.8 : 755.6) + 0.01);
    for (const b of pixelPlaced) {
        if (a === b || a.side !== b.side) continue;
        assert.ok(a.x + a.width + 10 <= b.x + 0.01 || b.x + b.width + 10 <= a.x + 0.01
            || a.y + a.height + 10 <= b.y + 0.01 || b.y + b.height + 10 <= a.y + 0.01, "free rectangles do not overlap");
    }
}
const smallerScreen = packPixelSides(pixelWidgets, 500, 372.8, 600, 10);
assert.ok(smallerScreen.every(p => p.y + p.height <= 600), "restore on a smaller screen stays in bounds");
console.log("DeskCenter free pixel layout: continuous height, banner clearance, collisions and screen bounds passed");
