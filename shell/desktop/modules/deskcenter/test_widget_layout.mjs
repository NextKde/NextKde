import assert from "node:assert/strict";
import { canPlace, fitWidgets, savedPositionsAfterMove, widgetColumnLimit, packWidgets, sizeOrder, snappedPosition, snappedSpan, spanFor } from "./WidgetLayout.mjs";

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

// The user's desktop: music is enabled at 2x2 but the four-column grid
// silently omitted it. Extend the widget field and keep the requested size.
const saved = ids.map(id => {
    const [columns, rows] = spanFor(id, id === "clock" ? "small"
        : id === "music" ? "large" : "medium");
    return { id, columns, rows };
});
assert.ok(!packWidgets(saved, 4, 4).some(widget => widget.id === "music"));
const fitted = fitWidgets(saved, 4, 9, 4);
assert.equal(fitted.placements.length, 7);
assert.ok(fitted.columns > 4);
const music = fitted.placements.find(widget => widget.id === "music");
assert.deepEqual([music.columns, music.rows], [2, 2]);
assert.equal(fitWidgets(saved, 4, 9, 3).placements.length, 7);
assert.deepEqual(spanFor("weather", "medium"), [3, 1], "legacy weather size preserved");
for (const size of sizeOrder)
    assert.deepEqual(spanFor("weather", size), size.split("x").map(Number));

const reversed = saved.slice().reverse();
const ordered = fitWidgets(reversed, 4, 9, 4);
assert.equal(ordered.placements[0].id, "music", "saved order survives layout");
const tiny = fitWidgets(saved, 4, 9, 1);
assert.equal(tiny.placements.length, 7, "short screen retains every enabled widget");
assert.ok(tiny.placements.every(widget => widget.rows === 1));
assert.equal(saved.find(widget => widget.id === "music").rows, 2,
    "temporary compaction never rewrites saved spans");
for (const layout of [fitted, ordered, tiny]) {
    const cells = new Set();
    for (const widget of layout.placements) {
        for (let row = widget.row; row < widget.row + widget.rows; row++) {
            for (let column = widget.column; column < widget.column + widget.columns; column++) {
                assert.ok(column < layout.columns);
                assert.ok(!cells.has(`${column}:${row}`));
                cells.add(`${column}:${row}`);
            }
        }
    }
}
assert.deepEqual(snappedSpan(180, 180, 180, 10), [1, 1]);
assert.deepEqual(snappedSpan(370, 180, 180, 10), [2, 1]);
assert.deepEqual(snappedSpan(180, 370, 180, 10), [1, 2]);
assert.deepEqual(snappedSpan(370, 370, 180, 10), [2, 2]);
assert.deepEqual(snappedSpan(-900, 9000, 180, 10), [1, 2]);
assert.deepEqual(snappedSpan(273, 180, 180, 10), [1, 1], "below half-cell threshold");
assert.deepEqual(snappedSpan(276, 180, 180, 10), [2, 1], "above half-cell threshold");

const positioned = [
    { id: "auto", columns: 2, rows: 1 },
    { id: "moved", columns: 1, rows: 2, column: 8, row: 1 },
    { id: "fixed", columns: 2, rows: 1, column: 0, row: 0 }
];
const free = fitWidgets(positioned, 4, 9, 4);
assert.equal(free.columns, 9, "manual position extends field to the requested cell");
assert.deepEqual(free.placements.find(widget => widget.id === "moved"),
    { id: "moved", columns: 1, rows: 2, column: 8, row: 1 });
assert.equal(free.placements.find(widget => widget.id === "fixed").column, 0,
    "unpositioned widgets never occupy a reserved cell");
assert.equal(canPlace(free.placements, "moved", 7, 0, 1, 2, 9, 4), true);
assert.equal(canPlace(free.placements, "moved", 1, 0, 1, 2, 9, 4), false,
    "an occupied rectangle rejects the drop");
assert.equal(canPlace(free.placements, "moved", 9, 0, 1, 2, 9, 4), false);
assert.equal(canPlace(free.placements, "moved", 8, 1, 1, 2, 9, 4), true,
    "the dragged widget does not collide with itself");
assert.deepEqual(snappedPosition(9000, -20, 2, 2, 180, 10, 9, 4), { column: 7, row: 0 });
assert.equal(fitWidgets(positioned, 4, 4, 3).placements.length, 3,
    "saved position on a larger screen cannot hide a widget on a smaller screen");
const conflicting = positioned.map(widget => Object.assign({}, widget, { column: 0, row: 0 }));
assert.equal(fitWidgets(conflicting, 4, 9, 4).placements.length, 3,
    "resize conflicts repack without losing widgets");

console.log("DeskCenter widget layout: all size and packing tests passed");

const projected = [{id: "clock", column: 0, row: 0}, {id: "music", column: 2, row: 0}];
const original = {music: {column: 2, row: 6}};
const moved = savedPositionsAfterMove(original, projected, "clock", 4, 0);
assert.deepEqual(moved.music, {column: 2, row: 6}, "moving clock must preserve music's offscreen saved row");
assert.deepEqual(moved.clock, {column: 4, row: 0});
assert.deepEqual(original.music, {column: 2, row: 6});
for (const files of [0, 1, 8, 16]) {
    const limit = widgetColumnLimit(1880, 180, 20, 144, files, 6);
    const fileWidth = 1880 - limit * 200;
    assert.ok(fileWidth >= Math.max(1, Math.ceil(files / 6)) * 144,
        "rightmost widget leaves room for desktop files");
}
assert.deepEqual(fitWidgets(saved, 4, 0, 4), {columns: 0, placements: []});
assert.deepEqual(fitWidgets(saved, 4, 8, 0), {columns: 0, placements: []});
