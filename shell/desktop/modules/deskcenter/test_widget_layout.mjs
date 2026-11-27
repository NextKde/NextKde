import assert from "node:assert/strict";
import { canPlace, declaredSizeCeiling, declaredSizeFloor, fitWidgets,
    insetRightEdge, isValidSize, magnetizedSize, maxSpanFor, minSpanFor,
    namedGallerySpan, nearestDeclaredSize, placeAnchoredWidget,
    resolveDeclaredSpan, savedPositionsAfterMove, widgetColumnLimit,
    packWidgets, sizeOrder, snappedPosition, snappedSpan, spanFor }
    from "./WidgetLayout.mjs";

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
assert.deepEqual(spanFor("weather", "small"), [2, 1]);
assert.deepEqual(spanFor("weather", "medium"), [3, 1], "legacy weather size preserved");
assert.deepEqual(spanFor("weather", "large"), [3, 2]);
for (const size of sizeOrder)
    assert.deepEqual(spanFor("weather", size), size.split("x").map(Number));
// Weather's declared spans are three columns wide, so its handle ceiling and
// storable explicit spans must match. The old hard-coded two-column ceiling
// shrank a default 3x1 card the moment its resize handle was pressed.
assert.deepEqual(maxSpanFor("weather"), [3, 2]);
assert.deepEqual(minSpanFor("weather"), [1, 1]);
assert.equal(isValidSize("weather", "3x1"), true);
assert.equal(isValidSize("weather", "3x2"), true);
assert.equal(isValidSize("weather", "4x2"), false);
const weatherLimit = maxSpanFor("weather");
assert.deepEqual(snappedSpan(560, 180, 180, 10, weatherLimit[0], weatherLimit[1]),
    [3, 1], "a 3-column weather card keeps its width on press");
assert.deepEqual(snappedSpan(560, 370, 180, 10, weatherLimit[0], weatherLimit[1]),
    [3, 2], "weather can be stretched to its full 3x2");
assert.deepEqual(snappedSpan(100, 100, 180, 10, weatherLimit[0], weatherLimit[1], 1, 1),
    [1, 1], "weather still shrinks to a single cell");

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

// The grouped view is the anchored exception: four readable layouts from a
// 2x2 floor to a 3x3 ceiling, and explicit spans stored in sizesJson.
assert.deepEqual(spanFor("groups", "small"), [2, 2]);
assert.deepEqual(spanFor("groups", "medium"), [2, 3]);
assert.deepEqual(spanFor("groups", "large"), [3, 3]);
assert.deepEqual(spanFor("groups", "2x3"), [2, 3]);
assert.deepEqual(spanFor("groups", "3x2"), [3, 2]);
assert.equal(isValidSize("groups", "2x2"), true);
assert.equal(isValidSize("groups", "2x3"), true);
assert.equal(isValidSize("groups", "3x2"), true);
assert.equal(isValidSize("groups", "3x3"), true);
assert.equal(isValidSize("groups", "1x1"), false, "the grouped view has a 2x2 floor");
assert.equal(isValidSize("groups", "1x2"), false);
assert.equal(isValidSize("groups", "2x1"), false);
assert.equal(isValidSize("groups", "4x3"), false);
assert.equal(isValidSize("clock", "2x3"), false, "ordinary widgets stay at 2 rows");
assert.deepEqual(maxSpanFor("groups"), [3, 3]);
assert.deepEqual(maxSpanFor("clock"), [2, 2]);
assert.deepEqual(minSpanFor("groups"), [2, 2]);
assert.deepEqual(minSpanFor("clock"), [1, 1]);
assert.deepEqual(snappedSpan(370, 560, 180, 10, 3, 3), [2, 3]);
assert.deepEqual(snappedSpan(370, 560, 180, 10), [2, 2],
    "the default clamp still applies to ordinary widgets");
assert.deepEqual(snappedSpan(100, 100, 180, 10, 3, 3, 2, 2), [2, 2],
    "the grouped view never snaps below its minimum span");
assert.deepEqual(snappedSpan(9999, 9999, 180, 10, 3, 3, 2, 2), [3, 3]);

const anchored = placeAnchoredWidget(
    { id: "groups", columns: 2, rows: 3 }, [], 10, 6);
assert.deepEqual(anchored,
    { id: "groups", column: 8, row: 0, columns: 2, rows: 3 },
    "no saved position lands at the top-right");
const kept = placeAnchoredWidget(
    { id: "groups", columns: 2, rows: 3, column: 3, row: 1 }, [], 10, 6);
assert.deepEqual([kept.column, kept.row], [3, 1],
    "a valid saved position is kept");
const shifted = placeAnchoredWidget(
    { id: "groups", columns: 2, rows: 3 },
    [{ id: "blocker", column: 8, row: 0, columns: 2, rows: 3 }], 10, 6);
assert.deepEqual([shifted.column, shifted.row], [6, 0],
    "an occupied top-right scans left first");
assert.equal(placeAnchoredWidget(
    { id: "groups", columns: 2, rows: 7 }, [], 10, 6), null,
    "an anchored span taller than the output has no placement");
// The grid is sized with the 8 px layout margins but placed from the 20 px
// visual inset, so its rightmost column would end 4 px past a 1920 px screen.
// The anchored card must slide back to the visible margin instead.
assert.equal(insetRightEdge(1551, 373, 1920, 20), 1527,
    "the rightmost column stops at the right inset");
assert.equal(insetRightEdge(20, 373, 1920, 20), 20,
    "cards already inside the margin do not move");
assert.equal(insetRightEdge(20, 373, 1920, 200), 20,
    "a card narrower than the inset margin keeps its left edge");
assert.equal(insetRightEdge(10, 2000, 1920, 20), 0,
    "a card wider than the margin never gets a negative left edge");

// The resize drag is magnetic: the corner is held at a cell size and only
// follows freely once the pointer pulls it half a cell away.
const held = magnetizedSize(227, 180, 10);
assert.equal(magnetizedSize(180, 180, 10), 180, "a corner at a cell size is held exactly");
assert.equal(magnetizedSize(275, 180, 10), 275, "halfway between cells the corner follows the pointer");
assert.ok(held > 180 && held < 227, "near a cell the magnet holds the corner back");
const attracted = magnetizedSize(340, 180, 10);
assert.ok(attracted > 340 && attracted < 370, "approaching a cell the magnet pulls the corner in");
assert.equal(magnetizedSize(9999, 180, 10), 370, "the drag never previews past the supported span");
assert.equal(magnetizedSize(-100, 180, 10), 180, "the drag never previews below one cell");
assert.equal(magnetizedSize(-100, 180, 10, 3, 2), 370,
    "the grouped view's drag is held at its 2x2 floor");
assert.equal(magnetizedSize(9999, 180, 10, 3, 2), 560,
    "the grouped view's drag still reaches its 3x3 ceiling");

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

// Qt sequence wrapper / array-like boundary tests (Array.isArray is false).
const boxedPair = { 0: 3, 1: 2, length: 2 };
const boxedSizes = { 0: { 0: 2, 1: 1, length: 2 }, 1: boxedPair, length: 2 };
assert.deepEqual(namedGallerySpan(boxedPair), [3, 2]);
assert.deepEqual(namedGallerySpan([2, 2]), [2, 2]);
assert.deepEqual(namedGallerySpan("3x2"), [3, 2]);
assert.deepEqual(namedGallerySpan("small"), [1, 1]);
assert.deepEqual(namedGallerySpan("medium"), [2, 1]);
assert.deepEqual(namedGallerySpan("large"), [2, 2]);
assert.deepEqual(namedGallerySpan("12"), [1, 1], "two-char string must not be sliced as [1, 2]");
assert.deepEqual(declaredSizeCeiling(boxedSizes), [3, 2]);
assert.deepEqual(declaredSizeFloor(boxedSizes), [2, 1]);
assert.deepEqual(nearestDeclaredSize(3, 2, boxedSizes), [3, 2]);
assert.deepEqual(nearestDeclaredSize(3, 3, boxedSizes), [3, 2]);
const boxedObstacles = { 0: { id: "blocker", column: 8, row: 0, columns: 2, rows: 3 }, length: 1 };
assert.deepEqual(
    placeAnchoredWidget({ id: "groups", columns: 2, rows: 3 }, boxedObstacles, 10, 6),
    { id: "groups", column: 6, row: 0, columns: 2, rows: 3 });

// Package update removed a previously placed size -> auto-snap to nearest declared size.
assert.deepEqual(
    resolveDeclaredSpan(3, 2, [[2, 2], [3, 2]], [2, 2]),
    { span: [3, 2], changed: false });
assert.deepEqual(
    resolveDeclaredSpan(3, 2, [[2, 2]], [2, 2]),
    { span: [2, 2], changed: true });
assert.deepEqual(
    resolveDeclaredSpan(3, 1, [[2, 1], [3, 3]], [2, 1]),
    { span: [2, 1], changed: true });
assert.deepEqual(
    resolveDeclaredSpan(3, 2, { 0: { 0: 2, 1: 2, length: 2 }, length: 1 }, [2, 2]),
    { span: [2, 2], changed: true });
assert.deepEqual(
    resolveDeclaredSpan(0, 0, [[1, 1], [2, 2]], [2, 2]),
    { span: [2, 2], changed: true });
